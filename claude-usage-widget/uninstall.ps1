#Requires -Version 5.1

$regKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if (Get-ItemProperty -Path $regKey -Name 'ClaudeUsageWidget' -ErrorAction SilentlyContinue) {
    Remove-ItemProperty -Path $regKey -Name 'ClaudeUsageWidget'
    Write-Host "Startup entry removed."
}

# Stop running widget process
Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*widget.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Write-Host "Widget stopped."
Write-Host "Claude Usage Widget uninstalled." -ForegroundColor Yellow
