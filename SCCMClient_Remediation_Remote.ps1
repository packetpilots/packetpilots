<#
.SYNOPSIS
Repairs a corrupted SCCM (ConfigMgr) client locally or remotely.

.DESCRIPTION
Performs a full SCCM client remediation sequence:
- Optional remote execution through PowerShell remoting
- Client uninstall and process wait
- Service stop and folder cleanup
- WMI repository consistency check/salvage (optional)
- Client source staging and reinstall
- Post-install validation and policy triggers

.NOTES
Run elevated. For remote execution, WinRM must be enabled on targets.
#>

[CmdletBinding(DefaultParameterSetName = 'Local')]
param(
    [Parameter(ParameterSetName = 'Remote', Mandatory)]
    [string[]]$ComputerName,

    [Parameter(ParameterSetName = 'Remote')]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SiteCode = 'S12',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DnsSuffix = 'amc.uwmedicine.org',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SCCMSource = '\\amc\data\EDS\INSTALL\Software\SCCMsoftware\SCCM2503Client',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LocalPath = 'C:\Temp\SCCMClient',

    [switch]$RepairWmi,
    [switch]$SkipGpupdate
)

$ErrorActionPreference = 'Stop'

$script:RepairBlock = {
    param($SiteCode, $DnsSuffix, $SCCMSource, $LocalPath, $RepairWmi, $SkipGpupdate)

    $LogFile = "C:\Windows\Temp\SCCM_Remediation_$env:COMPUTERNAME.log"

    function Write-Log {
        param([string]$Message)
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        "$ts - $Message" | Tee-Object -FilePath $LogFile -Append
    }

    function Invoke-BestEffort {
        param([scriptblock]$Script, [string]$Description)
        try {
            & $Script
            Write-Log "SUCCESS: $Description"
            return $true
        }
        catch {
            Write-Log "WARNING: $Description failed: $($_.Exception.Message)"
            return $false
        }
    }

    Write-Log '=== Starting SCCM Client Remediation ==='
    Write-Log "ComputerName: $env:COMPUTERNAME"

    if (-not (Test-Path $SCCMSource)) {
        throw "SCCM source path not reachable: $SCCMSource"
    }

    $ccmSetupPath = 'C:\Windows\ccmsetup\ccmsetup.exe'
    if (Test-Path $ccmSetupPath) {
        Write-Log 'Uninstalling existing SCCM client...'
        Start-Process -FilePath $ccmSetupPath -ArgumentList '/uninstall' -Wait -NoNewWindow
    }
    else {
        Write-Log 'ccmsetup.exe not found in C:\Windows\ccmsetup. Continuing with cleanup/reinstall.'
    }

    Write-Log 'Waiting for ccmsetup process to exit...'
    while (Get-Process -Name ccmsetup -ErrorAction SilentlyContinue) {
        Start-Sleep -Seconds 5
    }

    Invoke-BestEffort -Description 'Stopping CCMEXEC service' -Script {
        Stop-Service -Name CcmExec -Force -ErrorAction Stop
    } | Out-Null

    $folders = @(
        'C:\Windows\CCMSetup',
        'C:\Windows\CCM',
        'C:\Windows\CCMCache',
        'C:\Windows\SMSCFG.ini'
    )

    foreach ($item in $folders) {
        if (Test-Path $item) {
            Invoke-BestEffort -Description "Removing $item" -Script {
                Remove-Item -Path $item -Recurse -Force -ErrorAction Stop
            } | Out-Null
        }
    }

    if ($RepairWmi) {
        Write-Log 'Checking WMI repository consistency...'
        $verify = & winmgmt /verifyrepository 2>&1
        Write-Log "WMI verify output: $($verify -join ' ')"
        if (($verify -join ' ') -match 'inconsistent') {
            Write-Log 'WMI repository inconsistent. Attempting salvage...'
            $salvage = & winmgmt /salvagerepository 2>&1
            Write-Log "WMI salvage output: $($salvage -join ' ')"
        }
    }

    if (Test-Path $LocalPath) {
        Remove-Item -Path $LocalPath -Recurse -Force
    }
    New-Item -Path $LocalPath -ItemType Directory -Force | Out-Null

    Write-Log "Copying SCCM client source from $SCCMSource to $LocalPath"
    Copy-Item -Path "$SCCMSource\*" -Destination $LocalPath -Recurse -Force

    $setupExe = Join-Path $LocalPath 'ccmsetup.exe'
    if (-not (Test-Path $setupExe)) {
        throw "ccmsetup.exe not found in $LocalPath"
    }

    $arguments = @(
        "SMSSITECODE=$SiteCode",
        "DNSSUFFIX=$DnsSuffix",
        '/source:C:\Temp\SCCMClient',
        '/noservice'
    )

    Write-Log "Installing SCCM client with args: $($arguments -join ' ')"
    Start-Process -FilePath $setupExe -ArgumentList $arguments -Wait -NoNewWindow

    Start-Sleep -Seconds 20

    try {
        $client = Get-CimInstance -Namespace 'root\ccm' -ClassName 'SMS_Client'
        Write-Log "Assigned Site Code: $($client.AssignedSiteCode)"

        if ($client.AssignedSiteCode -ne $SiteCode) {
            Write-Log "WARNING: Site assignment mismatch. Expected $SiteCode, got $($client.AssignedSiteCode)"
        }

        Write-Log 'Triggering Machine Policy Retrieval/Evaluation schedules.'
        Invoke-CimMethod -Namespace 'root\ccm' -ClassName 'SMS_Client' -MethodName TriggerSchedule -Arguments @{sScheduleID='{00000000-0000-0000-0000-000000000021}'} | Out-Null
        Invoke-CimMethod -Namespace 'root\ccm' -ClassName 'SMS_Client' -MethodName TriggerSchedule -Arguments @{sScheduleID='{00000000-0000-0000-0000-000000000022}'} | Out-Null
    }
    catch {
        Write-Log "ERROR: Unable to validate SCCM client post-install: $($_.Exception.Message)"
    }

    if (-not $SkipGpupdate) {
        Invoke-BestEffort -Description 'Running gpupdate /force' -Script {
            gpupdate /force | Out-Null
        } | Out-Null
    }

    Write-Log '=== SCCM Remediation Completed ==='
}

if ($PSCmdlet.ParameterSetName -eq 'Remote') {
    foreach ($computer in $ComputerName) {
        Write-Host "Starting remote remediation on $computer..." -ForegroundColor Cyan
        $invokeParams = @{
            ComputerName = $computer
            ScriptBlock  = $script:RepairBlock
            ArgumentList = @($SiteCode, $DnsSuffix, $SCCMSource, $LocalPath, $RepairWmi, $SkipGpupdate)
            ErrorAction  = 'Stop'
        }

        if ($Credential) { $invokeParams.Credential = $Credential }

        try {
            Invoke-Command @invokeParams
            Write-Host "Completed remediation on $computer" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed remediation on $computer: $($_.Exception.Message)"
        }
    }
}
else {
    & $script:RepairBlock $SiteCode $DnsSuffix $SCCMSource $LocalPath $RepairWmi $SkipGpupdate
}
