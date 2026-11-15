# Quita el arranque automatico del monitor F1.
# Ejecutar:  powershell -ExecutionPolicy Bypass -File uninstall-autostart.ps1

$startup = [Environment]::GetFolderPath('Startup')
$lnkPath = Join-Path $startup 'F1 Tray Monitor.lnk'

if (Test-Path $lnkPath) {
    Remove-Item $lnkPath -Force
    Write-Host "Acceso directo eliminado: $lnkPath"
}
else {
    Write-Host 'No habia acceso directo de arranque automatico.'
}

$running = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match '[\\/]monitor\.ps1' }

foreach ($p in $running) {
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    Write-Host "Monitor detenido (PID $($p.ProcessId))."
}
