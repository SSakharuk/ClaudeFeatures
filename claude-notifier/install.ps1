#Requires -Version 5.1
<#
.SYNOPSIS
    - Registers notify.ps1 as a Claude Code hook (Notification + Stop events)
    - Registers tray.ps1 to launch at Windows startup
    - Starts the tray app immediately
#>

$ErrorActionPreference = 'Stop'

$settingsPath = "$env:USERPROFILE\.claude\settings.json"
$notifyScript = (Resolve-Path "$PSScriptRoot\notify.ps1").Path
$trayScript   = (Resolve-Path "$PSScriptRoot\tray.ps1").Path
$hookCommand  = "powershell -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$notifyScript`""

# --- 1. Claude Code hooks ---
if (Test-Path $settingsPath) {
    $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
    Write-Error "settings.json not found at $settingsPath. Is Claude Code installed?"
    exit 1
}

Copy-Item $settingsPath "$settingsPath.bak" -Force
Write-Host "Backup saved: $settingsPath.bak"

if (-not $settings.PSObject.Properties['hooks']) {
    $settings | Add-Member -NotePropertyName 'hooks' -NotePropertyValue ([PSCustomObject]@{})
}

$hookEntry = [ordered]@{ type = 'command'; command = $hookCommand }
$settings.hooks | Add-Member -NotePropertyName 'Notification' -NotePropertyValue @(@{ matcher = ''; hooks = @($hookEntry) }) -Force
$settings.hooks | Add-Member -NotePropertyName 'Stop'         -NotePropertyValue @(@{ hooks = @($hookEntry) })               -Force
$settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
Write-Host "Claude Code hooks registered."

# --- 2. Startup registry entry ---
$regKey     = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$startCmd   = "powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$trayScript`""
Set-ItemProperty -Path $regKey -Name 'ClaudeNotifier' -Value $startCmd
Write-Host "Tray app registered at startup."

# --- 3. Launch tray now (if not already running) ---
$mutex = [System.Threading.Mutex]::new($false, 'ClaudeNotifierTray')
$free  = $mutex.WaitOne(0)
$mutex.ReleaseMutex()
if ($free) {
    Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$trayScript`""
    Write-Host "Tray app started."
} else {
    Write-Host "Tray app already running."
}

Write-Host ""
Write-Host "All done. Right-click the 'C' icon in your system tray to manage settings." -ForegroundColor Green
Write-Host "To remove everything, run: .\uninstall.ps1"
