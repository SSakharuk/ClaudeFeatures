#Requires -Version 5.1
<#
.SYNOPSIS
    Manually test the notify.ps1 script without needing Claude Code.
    Run from any PowerShell terminal.

.EXAMPLE
    .\test.ps1                    # tests all notification types
    .\test.ps1 -Type permission   # tests permission_prompt only
    .\test.ps1 -Type stop         # tests Stop event
#>

param(
    [ValidateSet('permission', 'idle', 'question', 'stop', 'all')]
    [string]$Type = 'all'
)

$scriptPath = Join-Path $PSScriptRoot 'notify.ps1'
$testCwd    = 'C:/Users/Serhiy Sakharuk/ClaudeCode/ClaudeFeatures'

function Send-TestNotification($payload) {
    $json = $payload | ConvertTo-Json -Compress
    Write-Host "Sending: $json" -ForegroundColor Cyan
    # Pipe with UTF-8 so non-ASCII (Cyrillic, etc.) survives transit
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $json | powershell -NonInteractive -WindowStyle Hidden -File $scriptPath
    Start-Sleep -Seconds 2
}

if ($Type -in 'all', 'permission') {
    Send-TestNotification @{
        hook_event_name   = 'Notification'
        notification_type = 'permission_prompt'
        message           = 'Claude needs permission to run: npm install'
        session_id        = 'test-session-1'
        cwd               = $testCwd
    }
}

if ($Type -in 'all', 'idle') {
    Send-TestNotification @{
        hook_event_name   = 'Notification'
        notification_type = 'idle_prompt'
        message           = 'Claude is waiting for your next instruction.'
        session_id        = 'test-session-2'
        cwd               = $testCwd
    }
}

if ($Type -in 'all', 'question') {
    Send-TestNotification @{
        hook_event_name   = 'Notification'
        notification_type = 'elicitation_dialog'
        message           = 'Should I overwrite the existing config file?'
        session_id        = 'test-session-3'
        cwd               = $testCwd
    }
}

if ($Type -in 'all', 'stop') {
    Send-TestNotification @{
        hook_event_name        = 'Stop'
        stop_hook_active       = $false
        last_assistant_message = 'Done! I created notify.ps1, install.ps1, and test.ps1 in the claude-notifier folder.'
        session_id             = 'test-session-4'
        cwd                    = $testCwd
    }
}

Write-Host "`nTest complete." -ForegroundColor Green
