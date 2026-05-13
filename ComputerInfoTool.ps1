Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationFramework

$global:CurrentTheme = "light"
$global:Favorites = @()
$global:SettingsPath = "$env:APPDATA\ComputerInfoTool\settings.json"

$ColorSchemes = @{
    light = @{ Primary=[Drawing.Color]::FromArgb(25,118,210); Success=[Drawing.Color]::FromArgb(56,142,60); Warning=[Drawing.Color]::FromArgb(251,140,0); Danger=[Drawing.Color]::FromArgb(211,47,47); Background=[Drawing.Color]::FromArgb(245,245,245); GroupBox=[Drawing.Color]::FromArgb(240,240,240); TextDark=[Drawing.Color]::FromArgb(33,33,33); TextLight=[Drawing.Color]::White }
    dark  = @{ Primary=[Drawing.Color]::FromArgb(66,165,245); Success=[Drawing.Color]::FromArgb(102,187,106); Warning=[Drawing.Color]::FromArgb(255,167,38); Danger=[Drawing.Color]::FromArgb(239,83,80); Background=[Drawing.Color]::FromArgb(33,33,33); GroupBox=[Drawing.Color]::FromArgb(50,50,50); TextDark=[Drawing.Color]::FromArgb(240,240,240); TextLight=[Drawing.Color]::FromArgb(33,33,33) }
}

$Fonts = @{ Title=New-Object Drawing.Font("Segoe UI",14,[Drawing.FontStyle]::Bold); Group=New-Object Drawing.Font("Segoe UI",10,[Drawing.FontStyle]::Bold); Label=New-Object Drawing.Font("Segoe UI",9); Button=New-Object Drawing.Font("Segoe UI",9,[Drawing.FontStyle]::Bold); Text=New-Object Drawing.Font("Consolas",9) }

function Load-Settings {
    if (Test-Path $global:SettingsPath) {
        try {
            $s = Get-Content $global:SettingsPath -Raw | ConvertFrom-Json
            $global:Favorites = @($s.Favorites)
            if ($s.Theme) { $global:CurrentTheme = $s.Theme }
        } catch {
            $global:Favorites = @()
            $global:CurrentTheme = "light"
        }
    }
}

function Save-Settings {
    $dir = Split-Path $global:SettingsPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    @{ Favorites=$global:Favorites; Theme=$global:CurrentTheme } | ConvertTo-Json | Set-Content $global:SettingsPath -Encoding UTF8
}

function Add-Favorite([string]$Computer) {
    if ($Computer -and $Computer -notin $global:Favorites) {
        $global:Favorites += $Computer
        Save-Settings
    }
}

function Remove-Favorite([string]$Computer) {
    $global:Favorites = @($global:Favorites | Where-Object { $_ -ne $Computer })
    Save-Settings
}

function Clean-Model([string]$Model) {
    if (-not $Model) { return "" }
    return $Model.Replace("Ultra-Slim Desktop","USDT").Replace("Small Form Factor","SFF").Replace("HP Compaq ","").Replace(" PC","").Replace(" Desktop","").Trim()
}

function Get-UptimeString([datetime]$LastBoot) {
    if (-not $LastBoot) { return "Unknown" }
    $span = (Get-Date) - $LastBoot
    if ($span.Days -gt 0) { return "$($span.Days)d $($span.Hours)h $($span.Minutes)m" }
    return "$($span.Hours)h $($span.Minutes)m"
}

function New-UiLabel($text,$x,$y,$w=120,$h=20) {
    $c = New-Object Windows.Forms.Label
    $c.Location = [Drawing.Point]::new($x,$y)
    $c.Size = [Drawing.Size]::new($w,$h)
    $c.Text = $text
    $c.Font = $Fonts.Label
    $c.ForeColor = $ColorSchemes[$global:CurrentTheme].TextDark
    return $c
}

function New-UiTextBox($x,$y,$w=300,$h=20,[bool]$ro=$false,[bool]$multi=$false) {
    $c = New-Object Windows.Forms.TextBox
    $c.Location = [Drawing.Point]::new($x,$y)
    $c.Size = [Drawing.Size]::new($w,$h)
    $c.Font = $Fonts.Text
    $c.ReadOnly = $ro
    $c.Multiline = $multi
    $c.WordWrap = $multi
    $c.BorderStyle = [Windows.Forms.BorderStyle]::FixedSingle
    return $c
}

function New-UiButton($text,$x,$y,$w=100,$h=30,$bg=$null) {
    $c = New-Object Windows.Forms.Button
    $c.Location = [Drawing.Point]::new($x,$y)
    $c.Size = [Drawing.Size]::new($w,$h)
    $c.Text = $text
    $c.Font = $Fonts.Button
    $c.BackColor = if ($bg) { $bg } else { $ColorSchemes[$global:CurrentTheme].Primary }
    $c.ForeColor = $ColorSchemes[$global:CurrentTheme].TextLight
    $c.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    return $c
}

function Get-ComputerInfoObj([string]$Computer) {
    $obj = [PSCustomObject]@{ Name=$Computer; Status='Offline'; IPAddress=''; User=''; Model=''; Serial=''; BIOSVer=''; OsInfo=''; Uptime='Unknown'; RamGB=''; SysDrive=''; Gateway=''; DNS=''; MAC=''; DiskAlert=$false }

    $ping = Test-Connection -ComputerName $Computer -Count 1 -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $ping) { return $obj }

    $obj.Status = 'Online'
    $obj.IPAddress = $ping.IPV4Address.IPAddressToString

    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ComputerName $Computer -ErrorAction Stop
        $obj.Model = Clean-Model $cs.Model
        $obj.User = $cs.UserName
        $obj.RamGB = "{0:N2} GB" -f ($cs.TotalPhysicalMemory/1GB)
    } catch {}

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ComputerName $Computer -ErrorAction Stop
        $obj.OsInfo = "$($os.Caption) ($($os.Version))"
        $obj.Uptime = Get-UptimeString $os.LastBootUpTime
    } catch {}

    try {
        $bios = Get-CimInstance Win32_BIOS -ComputerName $Computer -ErrorAction Stop
        $obj.BIOSVer = $bios.SMBIOSBIOSVersion
        $obj.Serial = $bios.SerialNumber
    } catch {}

    try {
        $drive = Get-CimInstance Win32_LogicalDisk -ComputerName $Computer -Filter "DeviceID='C:'" -ErrorAction Stop
        if ($drive.Size -gt 0) {
            $pct = [math]::Round(($drive.FreeSpace/$drive.Size)*100,1)
            $obj.SysDrive = "{0:N2} GB free of {1:N2} GB ({2}%)" -f ($drive.FreeSpace/1GB),($drive.Size/1GB),$pct
            if ($pct -lt 20) { $obj.DiskAlert = $true }
        }
    } catch {}

    try {
        $nic = Get-CimInstance Win32_NetworkAdapterConfiguration -ComputerName $Computer -Filter "IPEnabled=True" -ErrorAction Stop | Select-Object -First 1
        if ($nic) {
            $obj.Gateway = $nic.DefaultIPGateway -join ', '
            $obj.DNS = $nic.DNSServerSearchOrder -join ', '
            $obj.MAC = $nic.MACAddress
        }
    } catch {}

    return $obj
}

function Show-EnhancedComputerInfoForm {
    Load-Settings
    $theme = $ColorSchemes[$global:CurrentTheme]

    $Form = New-Object Windows.Forms.Form
    $Form.Text = 'Computer Information Tool'
    $Form.Size = [Drawing.Size]::new(980,700)
    $Form.StartPosition = 'CenterScreen'
    $Form.BackColor = $theme.Background

    $title = New-UiLabel 'COMPUTER INFORMATION TOOL' 10 10 500 30
    $title.Font = $Fonts.Title
    $title.ForeColor = $theme.Primary
    $Form.Controls.Add($title)

    $Form.Controls.Add((New-UiLabel 'Hostname/IP:' 10 55 90 20))
    $txtComp = New-UiTextBox 105 53 240 22
    $Form.Controls.Add($txtComp)

    $cmbFav = New-Object Windows.Forms.ComboBox
    $cmbFav.Location = [Drawing.Point]::new(355,53)
    $cmbFav.Size = [Drawing.Size]::new(180,22)
    $cmbFav.DropDownStyle = [Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$cmbFav.Items.Add('-- Favorites --')
    foreach ($f in $global:Favorites) { [void]$cmbFav.Items.Add($f) }
    $cmbFav.SelectedIndex = 0
    $Form.Controls.Add($cmbFav)

    $btnQuery = New-UiButton 'Query' 545 51 80 26 $theme.Primary
    $btnAddFav = New-UiButton 'Add Fav' 630 51 90 26 $theme.Warning
    $btnTheme = New-UiButton 'Toggle Theme' 780 10 160 30 $theme.Warning
    $Form.Controls.AddRange(@($btnQuery,$btnAddFav,$btnTheme))

    # Enter-to-query support
    $Form.AcceptButton = $btnQuery
    $txtComp.Add_KeyDown({
        if ($_.KeyCode -eq [Windows.Forms.Keys]::Enter) {
            $btnQuery.PerformClick()
            $_.SuppressKeyPress = $true
        }
    })

    $grp = New-Object Windows.Forms.GroupBox
    $grp.Text = 'System Information'
    $grp.Font = $Fonts.Group
    $grp.Location = [Drawing.Point]::new(10,95)
    $grp.Size = [Drawing.Size]::new(930,500)
    $grp.BackColor = $theme.GroupBox
    $grp.ForeColor = $theme.Primary
    $Form.Controls.Add($grp)

    $defs = @(
        @{K='Name';L='Computer Name';Y=30}, @{K='Status';L='Status';Y=60}, @{K='IPAddress';L='IP Address';Y=90},
        @{K='User';L='Current User';Y=120}, @{K='Model';L='Model';Y=150}, @{K='Serial';L='Serial';Y=180},
        @{K='RamGB';L='RAM';Y=210}, @{K='SysDrive';L='C: Drive';Y=240}, @{K='OsInfo';L='OS';Y=270},
        @{K='BIOSVer';L='BIOS Version';Y=300}, @{K='Uptime';L='Uptime';Y=330}, @{K='Gateway';L='Gateway';Y=360},
        @{K='DNS';L='DNS';Y=390}, @{K='MAC';L='MAC';Y=420}
    )

    $txt = @{}
    foreach ($d in $defs) {
        $grp.Controls.Add((New-UiLabel "$($d.L):" 15 $d.Y 120 20))
        $tb = New-UiTextBox 140 ($d.Y-2) 760 22 $true
        $grp.Controls.Add($tb)
        $txt[$d.K] = $tb
    }

    $lblStatus = New-UiLabel 'Ready' 10 610 700 20
    $lblStatus.ForeColor = $theme.Primary
    $Form.Controls.Add($lblStatus)

    $btnExport = New-UiButton 'Export TXT' 760 605 85 28 $theme.Success
    $btnClose  = New-UiButton 'Close' 855 605 85 28 $theme.Danger
    $Form.Controls.AddRange(@($btnExport,$btnClose))

    $cmbFav.Add_SelectedIndexChanged({ if ($cmbFav.SelectedIndex -gt 0) { $txtComp.Text = [string]$cmbFav.SelectedItem } })

    $btnTheme.Add_Click({
        $global:CurrentTheme = if ($global:CurrentTheme -eq 'light') { 'dark' } else { 'light' }
        Save-Settings
        [Windows.Forms.MessageBox]::Show('Theme saved. Re-open app to apply.','Theme')
    })

    $btnAddFav.Add_Click({
        $c = $txtComp.Text.Trim()
        if ($c) {
            Add-Favorite $c
            $cmbFav.Items.Clear()
            [void]$cmbFav.Items.Add('-- Favorites --')
            foreach ($f in $global:Favorites) { [void]$cmbFav.Items.Add($f) }
            $cmbFav.SelectedIndex = 0
            [Windows.Forms.MessageBox]::Show('Added to favorites.','Saved')
        }
    })

    $btnQuery.Add_Click({
        $c = $txtComp.Text.Trim()
        if (-not $c) {
            [Windows.Forms.MessageBox]::Show('Enter a hostname or IP.','Input Required')
            return
        }

        $lblStatus.Text = "Querying $c ..."
        $Form.Refresh()

        $info = Get-ComputerInfoObj $c
        foreach ($k in $txt.Keys) {
            if ($info.PSObject.Properties.Name -contains $k) { $txt[$k].Text = [string]$info.$k }
        }

        if ($info.Status -eq 'Online') {
            $lblStatus.Text = 'Online - query complete'
            $lblStatus.ForeColor = $ColorSchemes[$global:CurrentTheme].Success
            if ($info.DiskAlert) { [Windows.Forms.MessageBox]::Show('Warning: Low disk space on C:','Disk Alert') }
        } else {
            $lblStatus.Text = 'Offline / unreachable'
            $lblStatus.ForeColor = $ColorSchemes[$global:CurrentTheme].Danger
        }
    })

    $btnExport.Add_Click({
        if (-not $txt['Name'].Text) {
            [Windows.Forms.MessageBox]::Show('Query a computer first.','No Data')
            return
        }

        $file = "$env:USERPROFILE\Documents\ComputerInfo_$($txt['Name'].Text)_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        @(
            '===== COMPUTER INFO REPORT =====',
            "Computer: $($txt['Name'].Text)", "Status: $($txt['Status'].Text)", "IP: $($txt['IPAddress'].Text)",
            "User: $($txt['User'].Text)", "Model: $($txt['Model'].Text)", "Serial: $($txt['Serial'].Text)",
            "RAM: $($txt['RamGB'].Text)", "Disk: $($txt['SysDrive'].Text)", "OS: $($txt['OsInfo'].Text)",
            "BIOS: $($txt['BIOSVer'].Text)", "Uptime: $($txt['Uptime'].Text)", "Gateway: $($txt['Gateway'].Text)",
            "DNS: $($txt['DNS'].Text)", "MAC: $($txt['MAC'].Text)", "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        ) | Set-Content -Path $file -Encoding UTF8

        [Windows.Forms.MessageBox]::Show("Exported to:`n$file",'Export')
    })

    $btnClose.Add_Click({ $Form.Close() })
    [void]$Form.ShowDialog()
}

Show-EnhancedComputerInfoForm
