#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Notifier - system tray app.
    Right-click the tray icon to toggle sound/toast and change the notification sound.
    Run hidden at startup via install.ps1.
#>

# Single-instance guard
$mutex = New-Object System.Threading.Mutex($false, 'ClaudeNotifierTray')
if (-not $mutex.WaitOne(0)) { exit 0 }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptDir  = $PSScriptRoot
$configPath = Join-Path $scriptDir 'config.json'

# --- Config helpers ---
function Get-Config {
    if (Test-Path $configPath) {
        return Get-Content $configPath -Raw | ConvertFrom-Json
    }
    return [PSCustomObject]@{
        soundEnabled = $true
        toastEnabled = $true
        soundFile    = 'C:\Windows\Media\Windows Notify.wav'
    }
}

function Save-Config($cfg) {
    $cfg | ConvertTo-Json | Set-Content $configPath -Encoding UTF8
}

# --- Tray icon (blue circle with "C") ---
$bmp = New-Object System.Drawing.Bitmap(16, 16)
$g   = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.FillEllipse([System.Drawing.Brushes]::DodgerBlue, 0, 0, 15, 15)
$font = New-Object System.Drawing.Font('Arial', 8, [System.Drawing.FontStyle]::Bold)
$g.DrawString('C', $font, [System.Drawing.Brushes]::White, 2, 1)
$g.Dispose()
$trayIcon       = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Icon  = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
$trayIcon.Text  = 'Claude Notifier'
$trayIcon.Visible = $true

# --- Context menu ---
$menu = New-Object System.Windows.Forms.ContextMenuStrip

# Sound toggle
$soundItem            = New-Object System.Windows.Forms.ToolStripMenuItem
$soundItem.Text       = 'Sound'
$soundItem.CheckOnClick = $true
$soundItem.Checked    = (Get-Config).soundEnabled
$soundItem.Add_Click({
    $cfg = Get-Config
    $cfg.soundEnabled = $soundItem.Checked
    Save-Config $cfg
})
$menu.Items.Add($soundItem) | Out-Null

# Toast toggle
$toastItem            = New-Object System.Windows.Forms.ToolStripMenuItem
$toastItem.Text       = 'Toast notification'
$toastItem.CheckOnClick = $true
$toastItem.Checked    = (Get-Config).toastEnabled
$toastItem.Add_Click({
    $cfg = Get-Config
    $cfg.toastEnabled = $toastItem.Checked
    Save-Config $cfg
})
$menu.Items.Add($toastItem) | Out-Null

$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

# Sound picker submenu
$soundMenu      = New-Object System.Windows.Forms.ToolStripMenuItem
$soundMenu.Text = 'Change Sound'

$sounds = [ordered]@{
    'Windows Notify'  = 'C:\Windows\Media\Windows Notify.wav'
    'Message Nudge'   = 'C:\Windows\Media\Windows Message Nudge.wav'
    'Balloon'         = 'C:\Windows\Media\Windows Balloon.wav'
    'Chimes'          = 'C:\Windows\Media\chimes.wav'
    'Ding'            = 'C:\Windows\Media\ding.wav'
    'Notify'          = 'C:\Windows\Media\notify.wav'
    'Tada'            = 'C:\Windows\Media\tada.wav'
}

$currentSound = (Get-Config).soundFile

foreach ($name in $sounds.Keys) {
    $path = $sounds[$name]
    $item = New-Object System.Windows.Forms.ToolStripMenuItem
    $item.Text    = $name
    $item.Tag     = $path
    $item.Checked = ($path -eq $currentSound)
    $item.Add_Click({
        foreach ($sibling in $soundMenu.DropDownItems) { $sibling.Checked = $false }
        $this.Checked = $true
        $cfg = Get-Config
        $cfg.soundFile = $this.Tag
        Save-Config $cfg
        # Preview
        if (Test-Path $this.Tag) {
            $player = New-Object System.Media.SoundPlayer($this.Tag)
            $player.Play()
        }
    })
    $soundMenu.DropDownItems.Add($item) | Out-Null
}
$menu.Items.Add($soundMenu) | Out-Null

$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

# Exit
$exitItem      = New-Object System.Windows.Forms.ToolStripMenuItem
$exitItem.Text = 'Exit'
$exitItem.Add_Click({
    $trayIcon.Visible = $false
    $trayIcon.Dispose()
    [System.Windows.Forms.Application]::Exit()
})
$menu.Items.Add($exitItem) | Out-Null

$trayIcon.ContextMenuStrip = $menu

# Run message loop
[System.Windows.Forms.Application]::Run()
$mutex.ReleaseMutex()
