# Instala el arranque automatico del monitor F1 al iniciar sesion en Windows.
# Ejecutar una vez:  powershell -ExecutionPolicy Bypass -File install-autostart.ps1

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$vbs = Join-Path $scriptDir 'start-monitor.vbs'

if (-not (Test-Path $vbs)) { throw "No se encontro $vbs" }

$startup = [Environment]::GetFolderPath('Startup')
$lnkPath = Join-Path $startup 'F1 Tray Monitor.lnk'

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($lnkPath)
$shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
$shortcut.Arguments = '"' + $vbs + '"'
$shortcut.WorkingDirectory = $scriptDir
$shortcut.WindowStyle = 7
$shortcut.Description = 'F1 Tray Monitor - Avisos de descargas de Formula 1'
$shortcut.Save()

Write-Host "Acceso directo creado en: $lnkPath"

# Arrancar ahora si no esta en ejecucion
$running = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match '[\\/]monitor\.ps1' }

if ($running) {
    Write-Host 'El monitor ya esta en ejecucion.'
}
else {
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\wscript.exe') -ArgumentList ('"' + $vbs + '"')
    Write-Host 'Monitor iniciado.'
}

Write-Host ''
Write-Host 'Listo. El monitor arrancara solo al iniciar sesion y ahora mismo esta activo en la bandeja.'
