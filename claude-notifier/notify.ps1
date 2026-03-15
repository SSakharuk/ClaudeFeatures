#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Code notification handler.
    Called by Claude Code hooks (Notification + Stop events) via stdin JSON.
    Reads config.json (managed by tray.ps1) to decide what to do.
#>

$ErrorActionPreference = 'SilentlyContinue'

# --- Ensure UTF-8 so non-ASCII text (e.g. Cyrillic) renders correctly ---
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- Read stdin payload ---
$rawInput = [Console]::In.ReadToEnd()
$payload  = $rawInput | ConvertFrom-Json

$event = $payload.hook_event_name
$cwd   = if ($payload.cwd) { $payload.cwd } else { $PWD.Path }

$projectName = Split-Path -Leaf $cwd

# --- Build title + message ---
if ($event -eq 'Stop') {
    if ($payload.stop_hook_active -eq $true) { exit 0 }
    $raw     = if ($payload.last_assistant_message) { $payload.last_assistant_message } else { 'Task complete.' }
    $title   = "Claude done - $projectName"
    $message = if ($raw.Length -gt 200) { $raw.Substring(0, 197) + '...' } else { $raw }
}
else {
    $notifType = $payload.notification_type
    $raw       = if ($payload.message) { $payload.message } else { 'Waiting for your input.' }
    $message   = if ($raw.Length -gt 200) { $raw.Substring(0, 197) + '...' } else { $raw }
    switch ($notifType) {
        'permission_prompt'  { $title = "Claude needs permission - $projectName" }
        'idle_prompt'        { $title = "Claude is waiting - $projectName" }
        'elicitation_dialog' { $title = "Claude has a question - $projectName" }
        default              { $title = "Claude Code - $projectName" }
    }
}

# --- Load config ---
$configPath = Join-Path $PSScriptRoot 'config.json'
$config = if (Test-Path $configPath) {
    Get-Content $configPath -Raw | ConvertFrom-Json
} else {
    [PSCustomObject]@{ soundEnabled = $true; toastEnabled = $true; soundFile = 'C:\Windows\Media\Windows Notify.wav' }
}

# --- Sound ---
if ($config.soundEnabled) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $player = New-Object System.Media.SoundPlayer($config.soundFile)
        $player.PlaySync()
    } catch {}
}

# --- Toast ---
if ($config.toastEnabled) {
    try {
        Import-Module BurntToast -ErrorAction Stop
        New-BurntToastNotification -Text $title, $message
    } catch {
        # Fallback: wscript popup
        $safeTitle   = $title   -replace '"', "'"
        $safeMessage = $message -replace '"', "'"
        $vbs = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.vbs'
        Set-Content -Path $vbs -Value "CreateObject(""WScript.Shell"").Popup ""$safeMessage"", 8, ""$safeTitle"", 64" -Encoding ASCII
        Start-Process -FilePath 'wscript.exe' -ArgumentList "`"$vbs`""
    }
}
