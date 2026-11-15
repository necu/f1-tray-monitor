# Fase 2 — 2.0 «Reproducción universal y descargas legales»

Documento de dirección. Sustituye al borrador `ROADMAP-1.4.md` y responde a tres objetivos:

1. **Compatibilidad extrema de formatos** sin salir de la app.
2. **Descargas gestionadas** (HTTP y torrents) con reproducción mientras se descargan.
3. **Todo dentro de la ventana**, sin reproductores externos ni pestañas del navegador.

La publicación (página, release por tag, alta de fuentes) ya está preparada y solo espera
`git init` + push. Este documento se centra en lo que viene después.

---

## 1. Revisión de la base actual

### Sólido y no se toca

- Instancia única, BOM UTF-8, escritura atómica, red silenciosa con `Write-Log`.
- Listado cacheado (~0,3 s / 246 tarjetas), ventana precalentada, divisor proporcional.
- Catálogo con `priority`/`starts`/`expires`, esquema, CI y autopruebas.
- Paquete reproducible con lista blanca, BOM, hashes y `SHA256SUMS`.

### Límites reales que motivan esta fase

| Límite | Consecuencia | Decisión |
|---|---|---|
| `player.html` solo reproduce embeds web dentro de un iframe cross-origin | No hay control de pistas, subtítulos, velocidad ni posición | El reproductor propio pasa a primer plano |
| WebView2 es Chromium: MP4/H.264/AAC, WebM/VP9/Opus, AV1, HLS sí; **MKV, HEVC, AC3/EAC3, DTS, MPEG-2 y subtítulos SRT/ASS no** (o dependen de códecs del sistema) | La mayoría de archivos descargados no se abren | Motor de decodificación propio (mpv) |
| No hay descargas ni archivos locales | La app solo sirve para embeds | Gestor de descargas con cola |
| No hay forma de ver un archivo a medias | «Ver mientras se descarga» es imposible | Descarga priorizada + reproductor tolerante a archivos incompletos |
| Sin repo git | No hay CI ni releases reales | Publicar (fase 0, ya preparada) |

Comprobado en esta máquina: WebView2 157.0.4341.46; `mpv`, `vlc`, `ffmpeg` y `aria2c` **no
están instalados**. Cualquier motor que se elija hay que empaquetarlo o detectarlo.

---

## 2. Principios

1. **Todo dentro de la app.** Nada de lanzar VLC ni el navegador por defecto para lo que la app
   pueda reproducir. Un reproductor externo queda solo como último recurso explícito.
2. **Decodificar, no reencodar.** Se reproduce el archivo tal cual siempre que el motor sepa;
   el remux/transcodificado es la excepción, no la norma (calidad y CPU).
3. **Legalidad por diseño.** Sin índices, catálogos ni trackers de contenido con derechos
   incluidos en el proyecto. Torrents solo para contenido de dominio público, Creative
   Commons, distribuciones libres o archivos que el usuario aporte y tenga derecho a usar.
4. **Portable y silenciosa.** Sin instalador, sin telemetría, sin servicios en la nube.
5. **PowerShell 5.1.** Sin módulos .NET nuevos ni runtime adicional.

> **Alcance excluido de forma explícita:** no se integrará ningún buscador de películas o
> series con copyright ni el «mayor repositorio de torrents». Eso es un índice de contenido
> pirata; la app no lo incluye, no lo consulta y no lo enlaza. Lo que sí se construye es el
> motor y la interfaz para que el usuario aporte sus propios enlaces legales.

---

## 3. Compatibilidad de formatos

### Matriz real (no teórica)

| Contenedor / códec | WebView2 (Chromium) | mpv (FFmpeg) | Nota |
|---|---|---|---|
| MP4 · H.264 + AAC | Sí | Sí | Caso base de los embeds |
| WebM · VP9/Opus, AV1 | Sí | Sí | |
| HLS (`.m3u8`) | Sí | Sí | |
| **MKV · H.264 + AAC** | **No** | Sí | El contenedor no se expone a `<video>` |
| **MKV · HEVC** | No (según códec del sistema) | Sí | Decodificación por hardware |
| **MKV · AV1** | Parcial | Sí | |
| **AC3 / EAC3 / DTS / TrueHD** | **No** | Sí | Chromium no habilita AC3/EAC3 |
| MPEG-TS · H.264/MPEG-2 | No / parcial | Sí | Grabaciones de TV |
| AVI · DivX/Xvid | No | Sí | Bibliotecas antiguas |
| FLAC / Opus en MKV | No | Sí | |
| Subtítulos SRT / ASS / PGS | Solo WebVTT | Sí | PGS = bitmap |
| Varias pistas de audio | No controlable | Sí | Cambio en caliente |
| DRM (Netflix, Prime, HBO…) | No | No | Requiere app propia; fuera de alcance |

**Conclusión:** WebView2 se queda para lo que ya hace bien (embeds y páginas de los
proveedores). Para archivos locales y descargas hace falta un decodificador completo: **mpv**.

### Por qué mpv y no otras opciones

| Opción | Formatos | Integración | Tamaño | Licencia | Veredicto |
|---|---|---|---|---|---|
| **mpv embebido** (`--wid=<HWND>`) | Todo lo que decodifica FFmpeg | Ventana hija dentro de un panel WinForms + IPC JSON | ~55-70 MB | GPLv2+ | **Recomendado** |
| ffmpeg → fMP4/HLS → WebView2 | Casi todo, pero HEVC exige transcodificar | Servidor local + MSE; mucha CPU | ~80-110 MB | LGPL/GPL según build | Alternativa si se quiere un solo renderizador |
| libVLC | Todo | LibVLCSharp necesita .NET moderno; P/Invoke a libvlc es frágil en PS 5.1 | ~45 MB | LGPLv2.1+ | Descartado por integración |
| Media Foundation | MKV/AC3 no | Nativo | 0 | — | Insuficiente |
| Reproductor externo | Todo | Rompe «siempre dentro» | 0 | — | Solo último recurso |

Detalle de la opción recomendada:

- mpv acepta `--wid` con un `HWND` en Windows y crea su ventana como hija del panel.
- Control por named pipe: `--input-ipc-server=\\.\pipe\f1mpv` + JSON (`loadfile`, `pause`,
  `seek`, `set_property`, `get_property`).
- Opciones de arranque: `--no-border`, `--force-window=no`, `--keep-open=no`, `--hwdec=auto-safe`,
  `--cache=yes`, `--sub-auto=fuzzy`, `--audio-file-auto=fuzzy`, `--save-position-on-quit`,
  `--osc=no` (los controles los pone la app).
- Controles propios en WinForms: play/pausa, barra de progreso, volumen, velocidad, pista de
  audio, subtítulos, pantalla completa y «siguiente».
- La ventana de mpv tapa los controles WinForms (airspace). Se resuelve con barra de controles
  en un panel aparte, OSD de mpv o una ventana de controles superpuesta; hay que prototiparlo.

---

## 4. Reproducción mientras se descarga

### Con torrent o HTTP

1. El motor escribe el archivo con **prioridad cabeza y cola**:
   `aria2c --bt-prioritize-piece=head=8M,tail=8M --file-allocation=none --seed-time=0`.
   La cola importa porque el átomo `moov` de muchos MP4 está al final.
2. mpv abre el archivo en crecimiento directamente (tolera que aún no exista el final) con
   caché de lectura amplia.
3. La app consulta el progreso por JSON-RPC y habilita **Ver ahora** cuando están la cabecera,
   la cola y el `moov`.
4. Si el usuario salta a una zona no descargada, se muestra «buffering» y se espera; nunca se
   sirven ceros de un hueco como si fueran vídeo.

### Papel del servidor local

`tools/stream-part.ps1` sigue siendo útil para:

- servirlo a WebView2 cuando la fuente es HTTP y queremos el reproductor web;
- depuración y pruebas con `curl`/VLC;
- fuentes que exigen una URL (`http://127.0.0.1:8099/stream`).

Para mpv no hace falta: abre el archivo directamente y evita una capa de indirección.

### Riesgos técnicos

- Los huecos de un archivo disperso se leen como ceros. Mitigación: prioridad secuencial tras
  cabeza/cola y puerta de reproducción basada en el prefijo contiguo descargado.
- MKV con `moov`/índices al final: sin la cola, mpv no conoce la duración; se espera.
- Velocidad de descarga menor que el bitrate: la reproducción se para; la UI debe avisarlo.

---

## 5. Motor de descargas

### Arquitectura

```
monitor.ps1
 ├─ Download-Manager      cola, pausa, límites, estado en f1_downloads.json
 ├─ Engine adapter        aria2c (JSON-RPC en 127.0.0.1, secreto aleatorio)
 │                        ├─ HTTP/HTTPS directo
 │                        └─ .torrent / magnet
 ├─ Stream-Server         tools/stream-part.ps1 (opcional)
 └─ Player                mpv embebido | WebView2 para embeds
```

- **Motor:** `aria2c` por JSON-RPC (`--enable-rpc --rpc-listen-all=false --rpc-secret=…`).
  Cola, pausa/reanudación, límite de velocidad, progreso y prioridad de piezas.
- **UI:** panel *Descargas* con estado, velocidad, ETA, tamaño, «Ver ahora» y «Abrir carpeta».
- **Persistencia:** `f1_downloads.json` (rutas, magnet, estado, bytes, prioridad).
- **Ciclo de vida:** el proceso hijo se cierra con la app; el servidor de streaming también.
- **Detección:** si falta el motor, la app explica cómo instalarlo y deshabilita las descargas
  sin romper el resto.

### Orígenes permitidos

1. **Archivo local** (arrastrar o elegir).
2. **URL HTTP/HTTPS** directa (contenido propio o con derechos).
3. **`.torrent` o `magnet`** que aporte el usuario, con confirmación y registro en el log.
4. **Catálogo legal integrado** (opcional): Internet Archive (dominio público y Creative
   Commons, con colecciones en español), distribuciones Linux y material similar. Se consulta
   su API pública y se usa el `.torrent` del propio ítem.

No hay índice de películas/series con copyright, ni búsqueda de torrents comercial, ni trackers
incluidos.

---

## 6. Buscador y proveedores

- `providers.json` gestionable por el usuario: plantilla de URL, cabeceras con
  `${ENV:CLAVE}`, mapeo JSON y capacidades (`http`, `magnet`, `torrent`).
- Resultados normalizados: título, año, tipo, calidad, idioma, tamaño, proveedor.
- La app **no incluye** proveedores con contenido ilícito; el usuario añade los que tenga
  derecho a usar y aporta sus claves.
- El catálogo legal de la sección 5 aparece como proveedor de solo lectura.

---

## 7. Fases y criterios de aceptación

### 2.0 — Publicar (hecho, pendiente de git)
- [x] Página, release por tag, alta de fuentes, streaming base, CI.
- [ ] `git init` + push + Pages + release `v1.3.0`.

### 2.1 — Reproductor universal (prioridad máxima)
- [ ] `bin/mpv/mpv.exe` detectado o empaquetado; arranque con `--wid` dentro de un panel.
- [ ] IPC JSON: cargar, pausar, buscar, volumen, velocidad, pistas de audio y subtítulos.
- [ ] Controles WinForms sincronizados (sin depender del OSD de mpv).
- [ ] Pantalla completa sin salir de la app y sin perder el estado.
- [ ] Matriz de pruebas: MP4 H.264/AAC, MKV H.264, MKV HEVC, MKV AV1, AC3 5.1, DTS,
  MPEG-TS, AVI, SRT y ASS.
- [ ] Si mpv no está: mensaje claro y reproducción web intacta.

### 2.2 — Descargas HTTP legales
- [ ] Adaptador aria2 + panel de descargas + estado persistente.
- [ ] Pausa, reanudación, límite de velocidad y borrado con confirmación.
- [ ] «Ver ahora» sobre archivo local ya descargado.

### 2.3 — Torrents y progresivo
- [ ] `.torrent`/magnet del usuario con confirmación legal.
- [ ] `--bt-prioritize-piece=head,tail` y arranque de mpv sobre el `.part`.
- [ ] Puerta de reproducción por prefijo contiguo y aviso de buffering.
- [ ] Prueba real con un torrent de dominio público (p. ej. Internet Archive).

### 2.4 — Proveedores gestionables
- [ ] `providers.json`, claves por entorno, buscador unificado y apertura en mpv/WebView2.

### 2.5 — Pulido
- [ ] Teclado en tarjetas, Pester para reglas y descargas, firma de los ZIP.

---

## 8. Empaquetado y licencias

| Sabor | Contenido | Tamaño estimado |
|---|---|---|
| **Lite** | App actual; detecta mpv/aria2 en `PATH` o en `bin/` | ~0,6 MB |
| **Full** | App + `mpv.exe` + `aria2c.exe` + licencias | ~65-80 MB |

- `package.ps1` gana `-WithPlayer` y `-WithDownloader`; `SHA256SUMS` lista cada artefacto.
- **mpv** es GPLv2+: se distribuye como binario independiente (agregación), con su licencia,
  enlace al código y oferta escrita. La app sigue siendo MIT.
- **aria2** es GPLv2+: mismo criterio.
- Sin firmar, los ejecutables pueden disparar avisos de SmartScreen y antivirus; la firma
  Authenticode queda como tarea de 2.5.

---

## 9. Decisiones abiertas

1. **¿mpv empaquetado o detectado?** Empaquetado garantiza «funciona siempre» a costa de
   ~60 MB; detectado mantiene el ZIP por debajo de 1 MB pero exige instalación manual.
   Recomendación: **Lite por defecto y Full opcional**, generados por el mismo script.
2. **¿Se añade ffmpeg además de mpv?** Solo si se quieren miniaturas, remux a MP4 para compartir
   o conversión de subtítulos; añade otros ~80 MB y no es necesario para reproducir.
3. **¿Un único reproductor o dos?** Mantener WebView2 para embeds y mpv para archivos es lo
   realista; unificarlo todo en mpv obligaría a resolver DRM y páginas interactivas.
4. **¿Se acepta el alcance legal?** Las descargas se limitan a contenido legal, dominio público
   o archivos aportados por el usuario. Sin esto, la fase 2.3 no se implementa.
5. **¿Orden?** 2.1 (compatibilidad) antes que 2.3 (torrents), porque sin reproductor universal
   el resto no se puede disfrutar.

## 10. Riesgos

- **Airspace de ventanas:** la ventana hija de mpv siempre queda por encima de los controles
  WinForms. Hay que prototipar la barra de controles antes de prometer una UI integrada.
- **GPL:** distribuir mpv/aria2 obliga a incluir licencia y oferta de código; no contamina la
  licencia MIT de la app si se mantienen como ejecutables separados.
- **Antivirus/SmartScreen:** binarios sin firmar; documentar los hashes y la procedencia.
- **Rendimiento:** decodificar HEVC 4K por software puede no ser viable; `--hwdec=auto-safe`
  y aviso de fallback.
- **Legal:** cualquier catálogo integrado debe ser de dominio público o licencia abierta, con
  atribución y sin trackers de terceros.
