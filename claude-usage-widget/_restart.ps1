Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*widget.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
Start-Sleep 1
Start-Process wscript.exe -ArgumentList "`"$PSScriptRoot\launch.vbs`""
Write-Host "Widget restarted"
