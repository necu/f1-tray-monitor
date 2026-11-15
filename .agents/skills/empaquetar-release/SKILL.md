---
name: empaquetar-release
description: Cierra una versión de F1 Tray Monitor: sube AppVersion, actualiza CHANGELOG y READMEs, genera el ZIP reproducible y SHA256SUMS, y relanza el monitor. Úsala al publicar 1.x.0.
license: MIT
metadata:
  category: release
---

# Empaquetar una release de F1 Tray Monitor

## Antes de empaquetar

1. `$script:AppVersion` en `monitor.ps1` y la sección de `CHANGELOG.md` coinciden.
2. `README.md` y `README.en.md` documentan lo nuevo; `docs/ideas.md` marca el estado.
3. `sources.json` valida con `.\check_sources.ps1`.
4. `.github/workflows/ci.yml` incluye los pasos nuevos (sintaxis, JSON, catálogo, paquete).

## Paquete

```powershell
.\package.ps1            # releases\F1-Tray-Monitor-<version>.zip + releases\SHA256SUMS
.\package.ps1 -Verify     # ensayo en %TEMP%, no publica
```

El script lee la versión de `monitor.ps1`, usa lista blanca de archivos, genera un
`config.json` por defecto (con `updateCheck`), valida BOM/sintaxis/hashes y escribe los hashes
de todos los ZIP de `releases/`.

## Verificación del ZIP

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead('releases\F1-Tray-Monitor-<version>.zip')
$zip.Entries.Count
$zip.Entries | Where-Object { $_.FullName -match 'f1_posts|f1_state|monitor\.log|releases/' }
$zip.Dispose()
```

No debe aparecer ninguna caché, registro ni la carpeta `releases/`, y todas las entradas deben
empezar por `f1-tray-monitor/`.

## Relanzar el monitor

Solo si el usuario lo pide o ya lo autorizó. Parar el proceso identificado (no por patrón) y:

```powershell
Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','<carpeta-del-proyecto>\monitor.ps1' -WindowStyle Hidden
```

## Cierre

Conserva los ZIP anteriores en `releases/`. No borres versiones antiguas ni `releases/README.md`.
