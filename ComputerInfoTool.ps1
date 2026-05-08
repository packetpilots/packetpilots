# NOTE:
# Avoid setting execution policy from inside scripts; it can be blocked by Group Policy.
# If needed, launch with:
#   powershell.exe -ExecutionPolicy Bypass -File .\ComputerInfoTool.ps1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationFramework

# ===== GLOBAL STATE =====
$global:CurrentTheme = "light"
$global:Favorites = @()
$global:SettingsPath = "$env:APPDATA\ComputerInfoTool\settings.json"
$global:QueryInProgress = $false
$global:LastQueryTime = 0

# ===== COLORS and FONTS =====
$ColorSchemes = @{
    light = @{
        Primary      = [System.Drawing.Color]::FromArgb(25, 118, 210)
        Success      = [System.Drawing.Color]::FromArgb(56, 142, 60)
        Warning      = [System.Drawing.Color]::FromArgb(251, 140, 0)
        Danger       = [System.Drawing.Color]::FromArgb(211, 47, 47)
        Background   = [System.Drawing.Color]::FromArgb(245, 245, 245)
        GroupBox     = [System.Drawing.Color]::FromArgb(240, 240, 240)
        TextDark     = [System.Drawing.Color]::FromArgb(33, 33, 33)
        TextLight    = [System.Drawing.Color]::White
        Border       = [System.Drawing.Color]::FromArgb(200, 200, 200)
    }
    dark = @{
        Primary      = [System.Drawing.Color]::FromArgb(66, 165, 245)
        Success      = [System.Drawing.Color]::FromArgb(102, 187, 106)
        Warning      = [System.Drawing.Color]::FromArgb(255, 167, 38)
        Danger       = [System.Drawing.Color]::FromArgb(239, 83, 80)
        Background   = [System.Drawing.Color]::FromArgb(33, 33, 33)
        GroupBox     = [System.Drawing.Color]::FromArgb(50, 50, 50)
        TextDark     = [System.Drawing.Color]::FromArgb(240, 240, 240)
        TextLight    = [System.Drawing.Color]::FromArgb(33, 33, 33)
        Border       = [System.Drawing.Color]::FromArgb(80, 80, 80)
    }
}

$Fonts = @{
    Title    = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    GroupBox = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    Label    = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
    Button   = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    TextBox  = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Regular)
    Status   = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    Small    = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Regular)
}

function Load-Settings {
    if (Test-Path $global:SettingsPath) {
        try {
            $settings = Get-Content $global:SettingsPath | ConvertFrom-Json
            $global:Favorites = $settings.Favorites
            $global:CurrentTheme = $settings.Theme
        } catch {
            $global:Favorites = @()
            $global:CurrentTheme = "light"
        }
    } else {
        $global:Favorites = @()
        $global:CurrentTheme = "light"
    }
}

function Save-Settings {
    $settingsDir = Split-Path $global:SettingsPath
    if (-not (Test-Path $settingsDir)) { New-Item -Path $settingsDir -ItemType Directory -Force | Out-Null }
    $settings = @{
        Favorites = $global:Favorites
        Theme     = $global:CurrentTheme
    }
    $settings | ConvertTo-Json | Set-Content $global:SettingsPath
}

function Add-Favorite($computer) {
    if ($computer -and $computer -notin $global:Favorites) {
        $global:Favorites += $computer
        Save-Settings
    }
}

function Remove-Favorite($computer) {
    $global:Favorites = $global:Favorites | Where-Object { $_ -ne $computer }
    Save-Settings
}

function Get-UptimeString {
    param($LastBoot)
    if (-not $LastBoot) { return "Unknown" }
    $span = (Get-Date) - $LastBoot
    $days = $span.Days
    $hours = $span.Hours
    $minutes = $span.Minutes

    if ($days -gt 0) {
        return "$days day$(if($days -ne 1){'s'}), $hours hour$(if($hours -ne 1){'s'}), $minutes min"
    }
    return "$hours hour$(if($hours -ne 1){'s'}), $minutes min"
}

function Clean-Model($model) {
    if (-not $model) { return $null }
    $model = $model.Replace("Ultra-Slim Desktop", "USDT")
    $model = $model.Replace("Small Form Factor", "SFF")
    $model = $model.Replace("HP Compaq ", "")
    $model = $model.Replace("Elite 8300", "8300 Elite")
    $model = $model.Replace(" PC", "").Replace(" Desktop","")
    return $model.Trim()
}

function Create-Tooltip {
    param($control, $text)
    $tooltip = New-Object System.Windows.Forms.ToolTip
    $tooltip.SetToolTip($control, $text)
    return $tooltip
}

function Create-Label {
    param([string]$text, [int]$x, [int]$y, [int]$width=120, [int]$height=20, [System.Drawing.Color]$color)
    $lbl = New-Object Windows.Forms.Label
    $lbl.Location = [Drawing.Point]::new($x, $y)
    $lbl.Size = [Drawing.Size]::new($width, $height)
    $lbl.Text = $text
    $lbl.Font = $Fonts.Label
    $lbl.ForeColor = if ($color) { $color } else { $ColorSchemes[$global:CurrentTheme].TextDark }
    return $lbl
}

function Create-TextBox {
    param([int]$x, [int]$y, [int]$width=200, [int]$height=20, [bool]$readonly=$false, [bool]$multiline=$false)
    $tb = New-Object Windows.Forms.TextBox
    $tb.Location = [Drawing.Point]::new($x, $y)
    $tb.Size = [Drawing.Size]::new($width, $height)
    $tb.Font = $Fonts.TextBox
    $tb.ReadOnly = $readonly
    $tb.BackColor = [System.Drawing.Color]::White
    $tb.BorderStyle = [Windows.Forms.BorderStyle]::FixedSingle
    if ($multiline) { $tb.Multiline = $true; $tb.WordWrap = $true }
    return $tb
}

function Create-Button {
    param([string]$text, [int]$x, [int]$y, [int]$width=100, [int]$height=30, [System.Drawing.Color]$bgColor)
    $btn = New-Object Windows.Forms.Button
    $btn.Location = [Drawing.Point]::new($x, $y)
    $btn.Size = [Drawing.Size]::new($width, $height)
    $btn.Text = $text
    $btn.Font = $Fonts.Button
    $btn.BackColor = if ($bgColor) { $bgColor } else { $ColorSchemes[$global:CurrentTheme].Primary }
    $btn.ForeColor = $ColorSchemes[$global:CurrentTheme].TextLight
    $btn.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 0
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $btn
}

Write-Host "Loaded helper functions. Paste or restore full UI/query section, then call Show-EnhancedComputerInfoForm."