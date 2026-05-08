# Run on Windows PowerShell / PowerShell 7 on Windows
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationFramework

# ===== GLOBAL STATE =====
$global:CurrentTheme = "light"
$global:Favorites = @()
$global:SettingsPath = "$env:APPDATA\ComputerInfoTool\settings.json"

# ===== COLORS / FONTS =====
$ColorSchemes = @{
    light = @{
        Primary    = [System.Drawing.Color]::FromArgb(25,118,210)
        Success    = [System.Drawing.Color]::FromArgb(56,142,60)
        Warning    = [System.Drawing.Color]::FromArgb(251,140,0)
        Danger     = [System.Drawing.Color]::FromArgb(211,47,47)
        Background = [System.Drawing.Color]::FromArgb(245,245,245)
        GroupBox   = [System.Drawing.Color]::FromArgb(240,240,240)
        TextDark   = [System.Drawing.Color]::FromArgb(33,33,33)
        TextLight  = [System.Drawing.Color]::White
    }
    dark = @{
        Primary    = [System.Drawing.Color]::FromArgb(66,165,245)
        Success    = [System.Drawing.Color]::FromArgb(102,187,106)
        Warning    = [System.Drawing.Color]::FromArgb(255,167,38)
        Danger     = [System.Drawing.Color]::FromArgb(239,83,80)
        Background = [System.Drawing.Color]::FromArgb(33,33,33)
        GroupBox   = [System.Drawing.Color]::FromArgb(50,50,50)
        TextDark   = [System.Drawing.Color]::FromArgb(240,240,240)
        TextLight  = [System.Drawing.Color]::FromArgb(33,33,33)
    }
}

$Fonts = @{
    Title   = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    Group   = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    Label   = New-Object System.Drawing.Font("Segoe UI", 9)
    Button  = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    TextBox = New-Object System.Drawing.Font("Consolas", 9)
}

# ===== SETTINGS =====
function Load-Settings {
    if (Test-Path $global:SettingsPath) {
        try {
            $settings = Get-Content $global:SettingsPath -Raw | ConvertFrom-Json
            $global:Favorites = @($settings.Favorites)
            if ($settings.Theme) { $global:CurrentTheme = $settings.Theme }
        } catch {
            $global:Favorites = @()
            $global:CurrentTheme = "light"
        }
    }
}

function Save-Settings {
    $dir = Split-Path $global:SettingsPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    @{
        Favorites = $global:Favorites
        Theme     = $global:CurrentTheme
    } | ConvertTo-Json | Set-Content $global:SettingsPath -Encoding UTF8
}

function Add-Favorite([string]$computer) {
    if ($computer -and $computer -notin $global:Favorites) {
        $global:Favorites += $computer
        Save-Settings
    }
}

function Remove-Favorite([string]$computer) {
    $global:Favorites = @($global:Favorites | Where-Object { $_ -ne $computer })
    Save-Settings
}

# ===== HELPERS =====
function Get-UptimeString([datetime]$LastBoot) {
    if (-not $LastBoot) { return "Unknown" }
    $span = (Get-Date) - $LastBoot
    if ($span.Days -gt 0) { return "$($span.Days)d $($span.Hours)h $($span.Minutes)m" }
    return "$($span.Hours)h $($span.Minutes)m"
}

function Clean-Model([string]$model) {
    if (-not $model) { return "" }
    $model = $model.Replace("Ultra-Slim Desktop","USDT")
    $model = $model.Replace("Small Form Factor","SFF")
    $model = $model.Replace("HP Compaq ","")
    $model = $model.Replace(" PC","").Replace(" Desktop","")
    $model.Trim()
}

function Create-Label($text,$x,$y,$w=120,$h=20) {
    $l = New-Object Windows.Forms.Label
    $l.Location = New-Object Drawing.Point($x,$y)
    $l.Size = New-Object Drawing.Size($w,$h)
    $l.Text = $text
    $l.Font = $Fonts.Label
    $l.ForeColor = $ColorSchemes[$global:CurrentTheme].TextDark
    return $l
}

function Create-TextBox($x,$y,$w=300,$h=20,[bool]$ro=$false,[bool]$multi=$false) {
    $t = New-Object Windows.Forms.TextBox
    $t.Location = New-Object Drawing.Point($x,$y)
    $t.Size = New-Object Drawing.Size($w,$h)
    $t.Font = $Fonts.TextBox
    $t.ReadOnly = $ro
    $t.Multiline = $multi
    $t.WordWrap = $multi
    $t.BorderStyle = [Windows.Forms.BorderStyle]::FixedSingle
    return $t
}

function Create-Button($text,$x,$y,$w=100,$h=30,$bg=$null) {
    $b = New-Object Windows.Forms.Button
    $b.Location = New-Object Drawing.Point($x,$y)
    $b.Size = New-Object Drawing.Size($w,$h)
    $b.Text = $text
    $b.Font = $Fonts.Button
    $b.BackColor = if ($bg) { $bg } else { $ColorSchemes[$global:CurrentTheme].Primary }
    $b.ForeColor = $ColorSchemes[$global:CurrentTheme].TextLight
    $b.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    return $b
}

function Get-ComputerInfoObj([string]$computer) {
    $o = [PSCustomObject]@{
        Name=$computer; Status="Offline"; IPAddress=""; User=""; Model=""; Serial=""; BIOSVer=""
        Description=""; OsInfo=""; LastBoot=$null; Uptime="Unknown"; RamGB=""; SysDrive=""
        Gateway=""; DNS=""; MAC=""; SoftwareCount=0; DiskAlert=$false; Pingable=$false
    }

    $ping = Test-Connection -ComputerName $computer -Count 1 -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $ping) { return $o }

    $o.Pingable = $true
    $o.Status = "Online"
    $o.IPAddress = $ping.IPV4Address.IPAddressToString

    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ComputerName $computer -ErrorAction Stop
        $o.Model = Clean-Model $cs.Model
        $o.User = $cs.UserName
        $o.RamGB = "{0:N2} GB" -f ($cs.TotalPhysicalMemory / 1GB)
    } catch {}

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ComputerName $computer -ErrorAction Stop
        $o.Description = $os.Description
        $o.OsInfo = "$($os.Caption) ($($os.Version))"
        $o.LastBoot = $os.LastBootUpTime
        $o.Uptime = Get-UptimeString $os.LastBootUpTime
    } catch {}

    try {
        $bios = Get-CimInstance Win32_BIOS -ComputerName $computer -ErrorAction Stop
        $o.BIOSVer = $bios.SMBIOSBIOSVersion
        $o.Serial = $bios.SerialNumber
    } catch {}

    try {
        $d = Get-CimInstance Win32_LogicalDisk -ComputerName $computer -Filter "DeviceID='C:'" -ErrorAction Stop
        if ($d.Size -gt 0) {
            $freePct = [math]::Round(($d.FreeSpace/$d.Size)*100,1)
            $o.SysDrive = "{0:N2} GB free of {1:N2} GB ({2}%)" -f ($d.FreeSpace/1GB),($d.Size/1GB),$freePct
            if ($freePct -lt 20) { $o.DiskAlert = $true }
        }
    } catch {}

    try {
        $nic = Get-CimInstance Win32_NetworkAdapterConfiguration -ComputerName $computer -Filter "IPEnabled=True" -ErrorAction Stop | Select-Object -First 1
        if ($nic) {
            $o.Gateway = ($nic.DefaultIPGateway -join ", ")
            $o.DNS = ($nic.DNSServerSearchOrder -join ", ")
            $o.MAC = $nic.MACAddress
        }
    } catch {}

    return $o
}

function Show-EnhancedComputerInfoForm {
    Load-Settings
    $theme = $ColorSchemes[$global:CurrentTheme]

    $form = New-Object Windows.Forms.Form
    $form.Text = "Computer Information Tool"
    $form.Size = New-Object Drawing.Size(980,700)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = $theme.Background

    $title = Create-Label "COMPUTER INFORMATION TOOL" 10 10 420 30
    $title.Font = $Fonts.Title
    $title.ForeColor = $theme.Primary
    $form.Controls.Add($title)

    $lblComp = Create-Label "Hostname/IP:" 10 55 90 20
    $txtComp = Create-TextBox 105 53 220 22
    $cmbFav = New-Object Windows.Forms.ComboBox
    $cmbFav.Location = New-Object Drawing.Point(335,53)
    $cmbFav.Size = New-Object Drawing.Size(180,22)
    $cmbFav.DropDownStyle = [Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$cmbFav.Items.Add("-- Favorites --")
    foreach ($f in $global:Favorites) { [void]$cmbFav.Items.Add($f) }
    $cmbFav.SelectedIndex = 0

    $btnQuery = Create-Button "Query" 525 51 80 26 $theme.Primary
    $btnAddFav = Create-Button "Add Fav" 610 51 80 26 $theme.Warning
    $btnTheme = Create-Button "Toggle Theme" 780 10 160 30 $theme.Warning

    $form.Controls.AddRange(@($lblComp,$txtComp,$cmbFav,$btnQuery,$btnAddFav,$btnTheme))

    $grp = New-Object Windows.Forms.GroupBox
    $grp.Text = "System Information"
    $grp.Font = $Fonts.Group
    $grp.Location = New-Object Drawing.Point(10,95)
    $grp.Size = New-Object Drawing.Size(930,500)
    $grp.BackColor = $theme.GroupBox
    $grp.ForeColor = $theme.Primary
    $form.Controls.Add($grp)

    $fields = @(
        @{K="Name";L="Computer Name";Y=30},
        @{K="Status";L="Status";Y=60},
        @{K="IPAddress";L="IP Address";Y=90},
        @{K="User";L="Current User";Y=120},
        @{K="Model";L="Model";Y=150},
        @{K="Serial";L="Serial";Y=180},
        @{K="RamGB";L="RAM";Y=210},
        @{K="SysDrive";L="C: Drive";Y=240},
        @{K="OsInfo";L="OS";Y=270},
        @{K="BIOSVer";L="BIOS Version";Y=300},
        @{K="Uptime";L="Uptime";Y=330},
        @{K="Gateway";L="Gateway";Y=360},
        @{K="DNS";L="DNS";Y=390},
        @{K="MAC";L="MAC";Y=420}
    )

    $txt = @{}
    foreach ($f in $fields) {
        $grp.Controls.Add((Create-Label "$($f.L):" 15 $f.Y 120 20))
        $tb = Create-TextBox 140 ($f.Y-2) 760 22 $true
        $grp.Controls.Add($tb)
        $txt[$f.K] = $tb
    }

    $lblStatus = Create-Label "Ready" 10 610 700 20
    $lblStatus.ForeColor = $theme.Primary
    $form.Controls.Add($lblStatus)

    $btnExport = Create-Button "Export TXT" 760 605 85 28 $theme.Success
    $btnClose = Create-Button "Close" 855 605 85 28 $theme.Danger
    $form.Controls.AddRange(@($btnExport,$btnClose))

    $cmbFav.Add_SelectedIndexChanged({
        if ($cmbFav.SelectedIndex -gt 0) { $txtComp.Text = [string]$cmbFav.SelectedItem }
    })

    $btnTheme.Add_Click({
        $global:CurrentTheme = if ($global:CurrentTheme -eq "light") { "dark" } else { "light" }
        Save-Settings
        [Windows.Forms.MessageBox]::Show("Theme saved. Re-open the app to apply fully.","Theme")
    })

    $btnAddFav.Add_Click({
        $c = $txtComp.Text.Trim()
        if ($c) {
            Add-Favorite $c
            $cmbFav.Items.Clear()
            [void]$cmbFav.Items.Add("-- Favorites --")
            foreach ($f in $global:Favorites) { [void]$cmbFav.Items.Add($f) }
            $cmbFav.SelectedIndex = 0
            [Windows.Forms.MessageBox]::Show("Added to favorites.","Saved")
        }
    })

    $btnQuery.Add_Click({
        $c = $txtComp.Text.Trim()
        if (-not $c) {
            [Windows.Forms.MessageBox]::Show("Enter a hostname or IP.","Input Required")
            return
        }

        $lblStatus.Text = "Querying $c ..."
        $form.Refresh()

        $info = Get-ComputerInfoObj $c
        foreach ($k in $txt.Keys) {
            if ($info.PSObject.Properties.Name -contains $k) {
                $val = $info.$k
                $txt[$k].Text = if ($val -is [datetime]) { $val.ToString("yyyy-MM-dd HH:mm:ss") } else { [string]$val }
            }
        }

        if ($info.Status -eq "Online") {
            $lblStatus.Text = "Online - query complete"
            $lblStatus.ForeColor = $ColorSchemes[$global:CurrentTheme].Success
            if ($info.DiskAlert) {
                [Windows.Forms.MessageBox]::Show("Warning: Low disk space on C:","Disk Alert")
            }
        } else {
            $lblStatus.Text = "Offline / unreachable"
            $lblStatus.ForeColor = $ColorSchemes[$global:CurrentTheme].Danger
        }
    })

    $btnExport.Add_Click({
        if (-not $txt["Name"].Text) {
            [Windows.Forms.MessageBox]::Show("Query a computer first.","No Data")
            return
        }
        $file = "$env:USERPROFILE\Documents\ComputerInfo_$($txt["Name"].Text)_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        $out = @(
            "===== COMPUTER INFO REPORT ====="
            "Computer: $($txt["Name"].Text)"
            "Status: $($txt["Status"].Text)"
            "IP: $($txt["IPAddress"].Text)"
            "User: $($txt["User"].Text)"
            "Model: $($txt["Model"].Text)"
            "Serial: $($txt["Serial"].Text)"
            "RAM: $($txt["RamGB"].Text)"
            "Disk: $($txt["SysDrive"].Text)"
            "OS: $($txt["OsInfo"].Text)"
            "BIOS: $($txt["BIOSVer"].Text)"
            "Uptime: $($txt["Uptime"].Text)"
            "Gateway: $($txt["Gateway"].Text)"
            "DNS: $($txt["DNS"].Text)"
            "MAC: $($txt["MAC"].Text)"
            "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        )
        $out | Set-Content -Path $file -Encoding UTF8
        [Windows.Forms.MessageBox]::Show("Exported to:`n$file","Export")
    })

    $btnClose.Add_Click({ $form.Close() })

    [void]$form.ShowDialog()
}

# Launch
Show-EnhancedComputerInfoForm