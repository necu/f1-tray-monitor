---
name: verificar-app
description: Valida F1 Tray Monitor antes de dar un cambio por terminado (sintaxis PS 5.1, JSON, catálogo, paquete y autoprueba). Úsala tras tocar monitor.ps1, player.html, sources.json o package.ps1.
license: MIT
metadata:
  category: development
---

# Verificar F1 Tray Monitor

Ejecuta las comprobaciones del proyecto en este orden y para en el primer fallo real.

## 1. Sintaxis y BOM

```powershell
foreach ($f in 'monitor.ps1','f1_scraper.ps1','package.ps1','check_sources.ps1') {
  $e = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f), [ref]$null, [ref]$e)
  if ($e) { $e | ForEach-Object { "$f : $($_.Message)" } } else { "OK $f" }
  $b = [System.IO.File]::ReadAllBytes((Resolve-Path $f))
  if ($f -in 'monitor.ps1','f1_scraper.ps1' -and ($b[0] -ne 0xEF -or $b[1] -ne 0xBB -or $b[2] -ne 0xBF)) {
    "FALTA BOM UTF-8 en $f"
  }
}
```

## 2. JSON y catálogo

```powershell
'config.json','sources.json','sources.example.json','sources.schema.json',
'opera-extension/manifest.json','opera-extension/rules.json' |
  ForEach-Object { Get-Content $_ -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null; "JSON OK $_" }
.\check_sources.ps1
```

## 3. Paquete reproducible

```powershell
.\package.ps1 -Verify
```

Comprueba archivos obligatorios, BOM, sintaxis, hashes y ausencia de cachés. No publica nada.

## 4. Autoprueba de interfaz

El monitor normal y la autoprueba comparten `Local\F1TrayMonitor_SingleInstance`: para el
monitor antes (nunca lo dejes abierto si el usuario está viéndolo; pregunta o espera).

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\monitor.ps1 -SelfTest -SelfTestAction catalog
```

Revisa `monitor.log` (`SelfTest ...`) y las capturas en `%TEMP%`. `ui` tarda ~18 s y genera
`f1-selftest-ui.png`, `-settings.png` y `-tray.png`.

## 5. Informe

Di qué comandos pasaron, qué falló y qué no se pudo comprobar (por ejemplo, una captura que
no se revisó). No afirmes que algo «se ve bien» si no lo has mirado.
