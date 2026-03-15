Set WshShell = CreateObject("WScript.Shell")
Dim scriptPath
scriptPath = Replace(WScript.ScriptFullName, "launch.vbs", "widget.ps1")
WshShell.Run "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & scriptPath & """", 0, False
