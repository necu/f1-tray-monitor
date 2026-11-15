' Lanza el monitor de F1 sin ventana de consola.
' Doble clic para iniciar el monitor manualmente.
Dim sh, scriptDir
Set sh = CreateObject("WScript.Shell")
scriptDir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & scriptDir & "monitor.ps1""", 0, False
