#Requires -Version 5.1
<#
.SYNOPSIS
    Removes Claude Notifier: hooks from settings.json, startup entry, and kills tray process.
#>

$ErrorActionPreference = 'Stop'

$settingsPath = "$env:USERPROFILE\.claude\settings.json"

# --- 1. Remove hooks ---
if (Test-Path $settingsPath) {
    Copy-Item $settingsPath "$settingsPath.bak" -Force
    $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($settings.PSObject.Properties['hooks']) {
        $settings.hooks.PSObject.Properties.Remove('Notification')
        $settings.hooks.PSObject.Properties.Remove('Stop')
        if (($settings.hooks.PSObject.Properties | Measure-Object).Count -eq 0) {
            $settings.PSObject.Properties.Remove('hooks')
        }
    }
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
    Write-Host "Claude Code hooks removed."
}

# --- 2. Remove startup entry ---
$regKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if (Get-ItemProperty -Path $regKey -Name 'ClaudeNotifier' -ErrorAction SilentlyContinue) {
    Remove-ItemProperty -Path $regKey -Name 'ClaudeNotifier'
    Write-Host "Startup entry removed."
}

# --- 3. Stop tray process ---
$trayPath = Join-Path $PSScriptRoot 'tray.ps1'
Get-Process -Name powershell -ErrorAction SilentlyContinue | Where-Object {
    $_.MainModule.FileName -and (
        (Get-WmiObject Win32_Process -Filter "ProcessId=$($_.Id)" -ErrorAction SilentlyContinue).CommandLine -like "*tray.ps1*"
    )
} | Stop-Process -Force -ErrorAction SilentlyContinue
Write-Host "Tray app stopped."

Write-Host ""
Write-Host "Claude Notifier uninstalled." -ForegroundColor Yellow
