#Requires -Version 5.1
<#
.SYNOPSIS
    Registers the Claude Usage Widget to start with Windows and launches it immediately.
#>

$launchVbs  = (Resolve-Path "$PSScriptRoot\launch.vbs").Path
$regKey     = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$startCmd   = "wscript.exe `"$launchVbs`""

Set-ItemProperty -Path $regKey -Name 'ClaudeUsageWidget' -Value $startCmd
Write-Host "Startup entry registered."

# Launch now (detached via wscript — survives terminal close)
$mutex = [System.Threading.Mutex]::new($false, 'ClaudeUsageWidget')
$free  = $mutex.WaitOne(0)
$mutex.ReleaseMutex()
if ($free) {
    Start-Process wscript.exe -ArgumentList "`"$launchVbs`""
    Write-Host "Widget launched (detached)."
} else {
    Write-Host "Widget already running."
}

Write-Host "Done. The widget will appear on screen shortly." -ForegroundColor Green
