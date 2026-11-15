# AGENTS.md — F1 Tray Monitor

Instrucciones y memoria de desarrollo para agentes (Freebuff/Codebuff) que trabajen en este
repositorio. Léelo antes de tocar nada.

## Qué es

Aplicación **standalone de Windows** para seguir el blog de F1 y ver las carreras sin salir del
escritorio. No hay instalador, no hay telemetría y no hay servidor propio.

- `monitor.ps1` — app WinForms + WebView2, bandeja, catálogo, ajustes, autopruebas.
- `f1_scraper.ps1` — scraping del blog por DNS-over-HTTPS; se ejecuta como proceso hijo.
- `player.html` — reproductor y selector de fuentes (HTML/CSS/JS sin dependencias).
- `sources.json` — catálogo editable de servicios y reglas de fuentes.
- `opera-extension/` — extensión MV3 opcional que comparte `cleaner.js` con WebView2.
- `lib/webview2/` — SDK de WebView2 distribuido con el proyecto.

## Reglas que no se negocian

1. **PowerShell 5.1** (Windows PowerShell, no Core). Nada de operadores o cmdlets solo de PW7.
2. **BOM UTF-8 (EF BB BF) obligatorio** en `monitor.ps1` y `f1_scraper.ps1`. Sin BOM, PS 5.1
   lee el archivo como ANSI y rompe tildes y símbolos.
3. **Español** en interfaz, comentarios, logs y documentación principal; `README.en.md` en inglés.
4. **Estilo oscuro/neón** con los colores ya existentes (`Get-NeonColor`, `#E10600`, fondos
   `13,13,19` / `17,17,24`). Nada de controles blancos nativos sin tematizar.
5. **Sin instalador, sin telemetría, sin dependencias nuevas** salvo que sean imprescindibles.
6. **No reiniciar el monitor mientras el usuario lo usa.** Para recargar, parar el PID y
   relanzar con:
   ```
   Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','<carpeta-del-proyecto>\monitor.ps1' -WindowStyle Hidden
   ```
7. **Mutex `Local\F1TrayMonitor_SingleInstance`**: no puede convivir el monitor normal con una
   autoprueba. Parar el monitor antes de `-SelfTest`.
8. Conservar `sources.json` editable a mano, el selector del reproductor, los ZIP de
   `releases/` y la documentación bilingüe.
9. Los cambios de usuario van a `config.json` y `f1_state.json`; nunca metas datos personales
   en el paquete.

## Estado actual: 1.3.0

### Hecho

- Catálogo remoto (`sources.json`, caché atómica, refresco 6 h), selector agrupado con teclado,
  bloqueador ampliado, aviso de bandeja, icono multirresolución, capas de ventana, tarjetas y
  carga por lotes (1.2.0).
- **Favoritos**: estrella por tarjeta, clave estable `race|año|gpKey|sesión` (o `post|id`),
  filtro global `$script:FavoritesOnly` compartido por ventana y bandeja, persistidos en
  `f1_state.json`.
- **Historial de búsquedas**: 8 consultas, sugerencias en panel flotante `F1.HintForm`
  (`WS_EX_NOACTIVATE`), borrado individual y total, enganchado a GotFocus/TextChanged/Enter/
  Escape/Leave/Deactivate.
- **Importar/exportar ajustes**: un JSON portable con config, favoritos, búsquedas y catálogo.
- **Visor de registro**: 800 líneas de `monitor.log`, recargar, copiar, `Esc`.
- **Comprobación de versiones**: `WebClient.DownloadStringTaskAsync` + `Timer` contra
  `api.github.com/repos/necu/f1-tray-monitor/releases/latest`, manual o silenciosa cada 24 h,
  desactivable, sin bloquear la UI.
- **Catálogo**: `priority`, `starts` y `expires`; reglas ordenadas por prioridad y caducadas
  omitidas.
- **Memoria por servicio** en `player.html` (`localStorage`, 12 servicios) y **accesibilidad**:
  `aria-live`, `role="status"`, `:focus-visible`.
- **Esquema y validación**: `sources.schema.json`, `sources.example.json`, `check_sources.ps1`
  y pasos de CI.
- **Autoprueba `catalog`**: reglas aplicadas sobre la caché, favoritos e historial.
- **`package.ps1`** reproducible + `releases/SHA256SUMS`.
- Ajustes ampliados a 628×950 con panel de mantenimiento.

### Rendimiento y redimensionado (mismo ciclo)

- `$script:CardCache` reutiliza las tarjetas: buscar/filtrar/refrescar ya no recrea 246
  controles (de ~6 s a ~0,3 s). Las tarjetas se invalidan si cambia el catálogo o el título.
- `Build-CardOptionButtons` crea las fuentes de una tarjeta solo al desplegarla.
- `Show-MainWindow -Hidden` precalienta ventana y WebView2 ~0,9 s después del arranque;
  el primer clic en la bandeja ya no espera. `Show-EmbeddedPlayer` llama a `Show-MainWindow`,
  así que abrir un vídeo tampoco reconstruye la lista (antes ese era el fallo del «refresco»).
- Divisor sin `Panel1MinSize`/`Panel2MinSize`: `Set-SplitRatio` mantiene `splitRatio`
  (persistido en `f1_state.json`), `SplitterMoved` solo cuenta si el botón izquierdo sigue
  pulsado, arrastrar al borde oculta el listado y el doble clic vuelve al 42 %.
- `Request-Layout` agrupa los resize cada 80 ms; `Update-ToolbarLayout` y la cabecera
  adaptativa esconden botones antes de solaparse. Mínimo de ventana: 520×400.

### Pulido de cierre

- **DPI**: se eliminó `SetProcessDPIAware()`. A 150 % Windows escala la ventana entera y ya no
  se recortan «Ver registro», «Buscar versión» ni las descripciones. El diseño sigue en píxeles
  de 96 ppp; el escalado por monitor v2 queda para 2.0.
- **Barras de desplazamiento oscuras** (`SetWindowTheme` + `DarkMode_Explorer`) en listado,
  bandeja, Ajustes y visor de registro.
- **Sugerencias**: guardas `SearchHistoryShowing`/`SearchHistoryHidePending` y
  `Application.add_ThreadException` para que un cierre durante `Show()` no deje un diálogo modal.
- **Pie adaptativo** y elipsis en pie, contador y etiquetas largas.
- **Banner y difusión**: `docs/banner.png`, `docs/social-preview.png`, metadatos Open Graph y
  `docs/PROMOCION.md` con el plan y los mensajes por canal.

### Verificado en 1.3.0

- Autoprueba `catalog`: catálogo v4 (0 reglas, 13 servicios), favorito añadido/quitado, filtro
  1 de 246, historial y sugerencias creadas.
- Autopruebas `search` (12 de 246 con «mexico»), `accordion`, `resize` (7 tamaños, sin
  `RECORTA`, 0 reconstrucciones), `catalog` y `ui`: todas exit 0.
- Autoprueba `ui`: panel de bandeja (40 filas, filtro 15, fila desplegada) y Ajustes; a 150 %
  la ventana lógica es 1180×600 y Ajustes se limita a 740 de alto con scroll oscuro.
- Capturas `docs/monitor.png` (1180×600), `settings.png` (628×740) y `tray.png` (446×604)
  regeneradas desde esa ejecución.
- ZIP 1.3.0: 54 entradas, raíz `f1-tray-monitor/`, separadores `/`, sin cachés ni `releases/`,
  `config.json` por defecto presente. Incluye `tools/`, `docs/ROADMAP.md` y `docs/banner.png`.
  Hash en `releases/SHA256SUMS`. Las entradas llevan fecha fija (1980-01-01), así que dos
  builds del mismo árbol dan el mismo SHA256.
- QA de cierre 1.3.0: cabecera medida sobre los botones visibles (`cabecera=262` a 520 px,
  `496` con vídeo embebido) sin recortes en 520…1440; firma de lista con estado del catálogo,
  marca de ficheros y huella de id+título (probado con un script aparte sobre `monitor.ps1`).
- Fase de publicación: `docs/index.html` (GitHub Pages, sin JS, con Open Graph), `release.yml`
  por tag, `tools/publicar.ps1` con `-DryRun` y `tools/add-source.ps1` probado con `-DryRun`,
  alta real en copia (v5) y rechazo de duplicados (exit 1); `tools/stream-part.ps1` verificado
  con `Range` cerrado (206 exacto), rango abierto desde 0 con crecimiento del archivo
  (151.552 B → 307.200 B, hash idéntico) y `/health`.
- Git 2.56.0 y GitHub CLI 2.104.0 instalados; repo local inicializado y commit preparado.
  Falta la autenticación del usuario (`gh auth login`) para crear el repo, Pages y el tag.

### Pendiente (siguiente ciclo)

- **Publicación con credenciales del usuario**: `gh auth login`, luego `tools/publicar.ps1`
  (commit, repo público, topics, Pages y tag `v1.3.0`). Después, subir
  `docs/social-preview.png` en Settings → Social preview y comprobar la release.
- **Ejecutar la difusión** de `docs/PROMOCION.md`: Show HN, r/formula1, r/PowerShell, X,
  LinkedIn, Mastodon, Bluesky y foros, escalonado y respondiendo comentarios 48 h.
- Dirección 2.0 acordada en `docs/ROADMAP.md`: **mpv embebido** (`--wid` + IPC) para
  compatibilidad total, **aria2c** como motor de descargas, reproducción sobre archivo en
  crecimiento y descargas limitadas a contenido legal o aportado por el usuario. Nada de
  índices de torrents con copyright.
- Firmar los ZIP (Authenticode) o publicar hashes en la nota de release.
- Ideas descartadas por arquitectura: controles de bandeja, PiP, miniaturas, salud de fuentes y
  estadísticas (el vídeo vive en un iframe cross-origin; `player.html` no puede controlarlo).
- Resto de ideas y su estado: `docs/ideas.md`.

## Comandos de verificación

```powershell
# Sintaxis de todos los scripts
foreach ($f in 'monitor.ps1','f1_scraper.ps1','package.ps1','check_sources.ps1') {
  $e = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f), [ref]$null, [ref]$e)
  if ($e) { $e | ForEach-Object { "$f : $($_.Message)" } } else { "OK $f" }
}

# JSON y catálogo
'config.json','sources.json','sources.example.json','sources.schema.json' |
  ForEach-Object { Get-Content $_ -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null; "JSON OK $_" }
.\check_sources.ps1

# Paquete reproducible sin publicar
.\package.ps1 -Verify

# Autoprueba (parar antes el monitor: mutex de instancia única)
powershell -NoProfile -ExecutionPolicy Bypass -File .\monitor.ps1 -SelfTest -SelfTestAction catalog
powershell -NoProfile -ExecutionPolicy Bypass -File .\monitor.ps1 -SelfTest -SelfTestAction resize
```

La autoprueba `ui` tarda ~18 s y deja `f1-selftest-ui.png`, `-settings.png` y `-tray.png` en
`%TEMP%`. La autoprueba escribe en `monitor.log`.

## Convenciones de código

- Funciones en `Verbo-Sustantivo` (`Show-LogViewer`, `Add-SearchHistory`), estado en
  `$script:` (`$script:Favorites`, `$script:SearchHistory`, `$script:FavoritesOnly`).
- Cada bloque grande empieza con un comentario `# --- Título ---`.
- Los controles WinForms se crean a mano y se registran en `$script:` si se actualizan luego.
- Los `Add_Click`/`Add_KeyDown` usan `$this` o `param($sender, $e)`; no capturar variables de
  bucle sin `Tag`.
- Todo fallo de red se resuelve en silencio y se registra con `Write-Log`; la UI nunca se
  bloquea.
- Fechas ISO 8601 en el catálogo; textos de UI en español con `dd/MM HH:mm`.

## Paquete

`package.ps1` lee `AppVersion` de `monitor.ps1`, copia solo la lista blanca de archivos, genera
un `config.json` por defecto (incluye `updateCheck`), valida BOM y sintaxis, compara hashes con
el proyecto, comprime con entradas `f1-tray-monitor/...` y separador `/` (compatible con
`unzip` en macOS/Linux) y escribe `releases/SHA256SUMS`. Nunca incluye `f1_posts.json`,
`f1_state.json`, `f1_loadall_progress.json`, `sources.cache.json`, `monitor.log` ni `releases/`.
