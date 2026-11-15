# Devuelve exit 0 si el monitor NO esta en ejecucion (para que la automatizacion lo arranque).
# Devuelve exit 1 si ya esta en ejecucion (la automatizacion no hace nada).
$procs = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match '[\\/]monitor\.ps1' }

if ($procs) { exit 1 } else { exit 0 }
