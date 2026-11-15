# Changelog

Todos los cambios relevantes de este proyecto se documentan aquí.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el proyecto
usa [Versionado semántico](https://semver.org/lang/es/).

## [1.3.0] - 2026-11-15

### Añadido

- **Página del proyecto** (`docs/index.html`) lista para GitHub Pages: estilo oscuro/neón,
  capturas reales, características, instalación, hash del ZIP y hoja de ruta, sin recursos
  externos ni JavaScript.
- **Release automatizada** (`.github/workflows/release.yml`): al empujar un tag `v*` valida el
  catálogo, construye el paquete reproducible y adjunta ZIP + `SHA256SUMS` a la release.
- **Alta guiada de fuentes** (`tools/add-source.ps1`): valida URL, servicio, prioridad y
  caducidad, evita duplicados, guarda copia de seguridad y ejecuta `check_sources.ps1`.
- **Skill `fuentes-nuevas`** para investigar enlaces, verificarlos y convertirlos en reglas
  del catálogo sin inventar calidades ni duplicar URLs.
- **Streaming progresivo** (`tools/stream-part.ps1`): servidor HTTP local con `Range` sobre un
  archivo que crece, con `206` para rangos cerrados y transferencia por chunks para rangos
  abiertos, más un endpoint `/health`. Base para «ver mientras se descarga».
- **Hoja de ruta** (`docs/ROADMAP.md`) con la revisión de 1.3.0, las categorías
  pendientes y el diseño técnico y legal de torrents y proveedores gestionables.
- **Favoritos**: estrella en cada tarjeta para marcar un GP o una sesión. La clave es estable
  (`race|año|gpKey|sesión`, o `post|id` para sueltas), así que sobrevive a cambios de título
  del blog y a los refrescos del catálogo. El filtro *solo favoritos* es global y afecta a la
  ventana y al panel de bandeja por igual.
- **Historial de búsquedas**: últimas 8 consultas con sugerencias al enfocar el buscador en un
  panel flotante que no roba el foco (`WS_EX_NOACTIVATE`). Puedes borrar una entrada con su
  aspa o todo el historial desde el pie del panel.
- **Importar y exportar ajustes**: un único JSON portable con configuración, favoritos,
  búsquedas y catálogo, para cambiar de equipo sin editar archivos a mano.
- **Visor de registro**: las últimas 800 líneas de `monitor.log` en una ventana oscura, con
  *Recargar*, *Copiar* y cierre con `Esc`. Ya no hace falta abrir el Explorador.
- **Comprobación de versiones**: consulta asíncrona a GitHub Releases (manual o silenciosa
  cada 24 h, desactivable) con enlace directo a la descarga. Usa
  `WebClient.DownloadStringTaskAsync` y un `Timer`, así que la ventana nunca se bloquea y
  cualquier fallo de red se resuelve en silencio.
- **Catálogo por prioridad y caducidad**: `priority`, `starts` y `expires` (ISO 8601). Las
  reglas se ordenan de mayor a menor prioridad y las cadenas vencidas se ignoran sin borrar
  nada.
- **Memoria por servicio** en el reproductor: recuerda calidad e idioma elegidos en cada
  plataforma (hasta 12) y preselecciona la fuente equivalente en el siguiente vídeo.
- **Accesibilidad del reproductor**: región `role="status"` con `aria-live`, anuncios de
  cambio de fuente y de carga, y foco visible (`:focus-visible`) en todos los botones.
- **Esquema del catálogo**: `sources.schema.json`, `sources.example.json` y
  `check_sources.ps1`, validados en cada push junto al resto de JSON.
- **Autoprueba `catalog`**: comprueba sobre la caché real que las reglas casan, que los
  favoritos se filtran y que el historial se guarda y se borra.
- **`package.ps1`**: empaquetado reproducible con lista blanca de archivos, `config.json` por
  defecto, verificación de BOM y sintaxis, comparación de hashes y escritura de
  `releases/SHA256SUMS`.

### Cambiado

- El panel de Ajustes crece a 628×950 y añade el bloque *Mantenimiento* (versión, carpeta,
  registro, exportar, importar, buscar versión y aviso de actualizaciones) sin scroll en
  1920×1080.
- La versión de la app pasa a `1.3.0`; la comprobación de actualizaciones compara contra
  `AppVersion` en lugar de un número fijo.
- El filtro de favoritos se aplica dentro de `Get-FilteredPosts`, de modo que la ventana, el
  contador y el panel de bandeja muestran siempre lo mismo.
- **Listado cacheado**: cada tarjeta se construye una sola vez y se reutiliza al buscar,
  filtrar o refrescar. Repintar las 246 entradas baja de ~6 s a ~0,3 s, y abrir un vídeo ya no
  reconstruye la lista ni pierde la posición de lectura.
- **Opciones perezosas**: los botones de fuentes de una tarjeta se crean al desplegarla, no al
  construir el listado.
- **Ventana precalentada**: con «iniciar en bandeja», la ventana y WebView2 se montan ocultos
  a los ~2 s del arranque, así que el primer clic en el icono la muestra al instante.
- **Redimensionado inteligente**: sin mínimos rígidos en el divisor. Se guarda una proporción
  (`splitRatio` en `f1_state.json`), se reaplica al cambiar el tamaño, arrastrar hasta el borde
  oculta el listado y el doble clic en el divisor lo devuelve al 42 %. El mínimo de la ventana
  baja a 520×400 y la cabecera y la barra de herramientas se adaptan al ancho.
- **Autoprueba `resize`**: recorre siete tamaños, comprueba la proporción del divisor, el
  ocultado del listado y que mostrar la ventana no reconstruya la lista.
- **Paquete reproducible de verdad**: el ZIP fija la fecha de todas sus entradas, así que dos
  builds del mismo código producen el mismo SHA256 en cualquier equipo.
- **Escalado de Windows**: la app deja de declararse DPI-aware. A 125–150 % Windows escala la
  ventana completa y desaparecen los textos recortados de Ajustes y de la cabecera; el diseño
  sigue midiéndose en píxeles de 96 ppp. El escalado por monitor queda para la fase 2.0.
- **Barras de desplazamiento oscuras** en el listado, la bandeja, Ajustes y el visor de
  registro, con el tema `DarkMode_Explorer` de Windows 10/11.
- **Pie adaptativo**: la ayuda del pie acorta su texto según el ancho y usa elipsis, igual que
  el contador de entradas.
- **Banner y kit de difusión**: `docs/banner.png` encabeza los README y `docs/PROMOCION.md`
  reúne el plan por canal con mensajes listos para copiar. El paquete pasa a 54 entradas.

### Corregido

- El panel de sugerencias se cierra al salir del buscador, al pulsar `Esc` y al cambiar de
  ventana, sin quedarse flotando sobre Ajustes o el reproductor externo.
- Las reglas del catálogo solapadas ya no dependen del orden del archivo: la prioridad decide.
- **Cabecera a ancho mínimo**: el ancho de los botones se mide en lugar de estimarse, así que a
  520 px ya no se recortan el filtro de favoritos ni *Actualizar*; si faltara sitio por DPI
  alto se oculta primero el filtro.
- **Caché de tarjetas**: la firma de la lista incluye el estado del catálogo, una marca de sus
  ficheros y una huella de id+título de las entradas. Activar o desactivar el catálogo, editarlo
  sin subir su versión o corregir un título ya refrescan las opciones sin reiniciar la app.
- **Sugerencias del buscador**: cerrar el panel mientras WinForms lo estaba mostrando lanzaba
  una excepción modal que dejaba la app bloqueada. El cierre se aplaza al final de `Show()` y
  las excepciones de interfaz se registran sin abrir un diálogo.
- **Textos a ancho mínimo**: el pie, el contador y las etiquetas largas usan elipsis; la
  cabecera mide sus botones y el pie cambia de texto antes de recortarse.

## [1.2.0] - 2026-11-14

### Añadido

- **Catálogo remoto de fuentes** (`sources.json`): servicios, colores y reglas que añaden
  opciones de reproducción sin volver a escrapear. Se puede editar en GitHub y la app lo
  descarga cada 6 horas (configurable) con copia de seguridad local (`sources.cache.json`).
- Reglas por `id`, `year`, `gp`, `session`, `type`, `titleContains` o comodín, con opciones
  curadas, calidad, idioma y fuente principal.
- **Selector inteligente de fuentes** en el reproductor: botón con el servicio activo y panel
  agrupado por plataforma, con insignias de calidad/idioma, estrella para la opción principal
  y navegación completa por teclado.
- Ajustes: fila del catálogo con URL editable, botón *Actualizar* y estado de la última
  descarga; baldosas nuevas *Catálogo de fuentes* y *Aviso de bandeja*.
- **Aviso animado sobre la bandeja**: globo con fundido y deslizamiento las dos primeras
  veces, cancelable con clic derecho y desactivable en Ajustes.
- **Icono oficial multirresolución** (`f1.ico`, 16–256 px) y AppUserModelID propio para
  agrupar la ventana con su icono en la barra de tareas.
- **Capas de ventana**: normal → siempre encima → fondo de escritorio, desde la barra del
  reproductor (`L`) o desde el panel de bandeja.
- **Tarjetas con identidad de carrera**: placa de ronda inclinada, GP en tipografía
  condensada, circuito y ciudad, y chips de año, sesión, catálogo y número de fuentes.
- **Carga por lotes** en «Cargar todo»: páginas y fichas en paralelo, progreso en la barra y
  escritura atómica de la caché. El botón *Detener* termina todo el árbol de procesos.
- Carpeta `releases/` con los paquetes anteriores y el paquete actual.

### Cambiado

- «Cargar todo» ya no notifica entradas: solo avisa de lo que aparece en un scrapeo normal.
- Las notificaciones se agrupan en un único globo resumen por comprobación.
- El neón tiñe de forma coherente la barra de marca, el botón *Actualizar*, el borde de
  *Cargar todo*, el panel de bandeja y el marco de ajustes.
- El bloqueador de anuncios amplía hosts y patrones, neutraliza `beforeunload`, los popups de
  `window.open`, las notificaciones push y los overlays con botón; WebView2 cancela además
  navegaciones a esquemas raros o anunciantes.
- WebView2 arranca con `--autoplay-policy=no-user-gesture-required` y sin throttling en
  segundo plano, para que el vídeo empiece solo y no se congele.
- La paginación y el catálogo conviven con la búsqueda: el listado se refresca sin perder el
  filtro activo.

### Corregido

- El chip de fuentes mide el texto real y ya no se recorta ni duplica la ronda.
- El panel del selector se alinea a la derecha y no queda oculto por el marco del vídeo.
- El aviso de bandeja no roba el foco ni aparece en Alt+Tab (`WS_EX_NOACTIVATE`).
- Los estados de las baldosas se sincronizan cuando el catálogo se activa desde su botón.

## [1.1.0] - 2026-11-12

### Añadido

- Clic izquierdo en el icono de la bandeja para mostrar u ocultar la ventana sin cerrar la
  app ni detener las comprobaciones.
- Panel de bandeja propio (clic derecho): formulario sin bordes con el mismo estilo oscuro de
  la app, buscador integrado con sinónimos y erratas, entradas desplegables para elegir fuente
  y accesos a *Abrir*, *Actualizar*, *Cargar todo*, *Ajustes* y *Salir*.
- Ajustes por iconos: siete baldosas con interruptor y globo explicativo, contador `−` / `+`
  para el intervalo y selector de equipo del neón.
- Neón por equipos en `player.html`: doce equipos memorables de F1 (Ferrari, McLaren,
  Mercedes, Red Bull, Williams, Alpine, Aston Martin, Haas, Sauber, Lotus, Brawn GP y
  Renault), aplicados al borde animado del reproductor y al marco de los ajustes.
- Neón rotativo que cambia de equipo cada 12 segundos.
- Ajustes nuevos persistidos en `config.json`: `notifications`, `startMinimized`,
  `openVideoOnly`, `autoLoadAll`, `rememberSearch`, `neonTeam` y `neonCycle`.
- Búsqueda recordada en `f1_state.json`: se guarda al filtrar y se restaura al abrir la
  ventana y el panel de bandeja.
- Carga automática de todas las páginas al iniciar cuando `autoLoadAll` está activo.
- Autopruebas `ui` y `loadall`, y captura del panel de bandeja y de los ajustes con
  `Save-WindowShot -Form`.

### Cambiado

- La ventana se muestra al arrancar salvo que `startMinimized` esté activo; así el ajuste
  *Iniciar en bandeja* resulta útil y el clic de bandeja alterna de forma coherente.
- El menú contextual clásico de Windows se sustituye por el panel propio de la bandeja.
- El buscador principal y el del panel comparten `Get-FilteredPosts`, con el mismo ranking.
- Los avisos de la bandeja respetan el ajuste `notifications`.
- El intervalo de comprobación se puede cambiar en caliente desde Ajustes, sin reiniciar.

### Corregido

- Los acentos y signos se muestran correctamente al guardar `monitor.ps1` como UTF-8 con BOM.
- Los controles nativos blancos (contador y desplegable) se sustituyen por controles propios
  integrados en el tema oscuro.
- Los textos de las baldosas y del panel ya no se recortan.

## [1.0.0] - 2026-11-12

### Añadido

- Icono en la bandeja del sistema con menú contextual y notificaciones nativas.
- Comprobación periódica del blog mediante DNS-over-HTTPS (Cloudflare), configurable por
  intervalo y por días de la semana.
- Ventana WinForms con tarjetas en acordeón: solo una entrada abierta a la vez.
- Buscador instantáneo que ignora tildes y filtra por GP, sesión u opción de reproducción.
- Paginación del blog con el botón *Cargar página N*, que añade entradas antiguas sin
  duplicados ni notificaciones.
- Reproductor incrustado con WebView2: el vídeo se abre a la derecha del listado, sin salir
  de la aplicación. El SDK .NET se distribuye en `lib/webview2/` con sus licencias.
- Selector de fuentes en la barra del reproductor para cambiar entre las opciones de una
  misma entrada (ESPN, DAZN, previa, post...) sin volver al listado.
- Botón *Ocultar lista* y modo *Solo vídeo*: ventana sin bordes, redimensionable y con
  controles propios (arrastrar, mostrar listado, minimizar, maximizar y cerrar).
- Reproductor `player.html` con barra "pit wall" que aparece al acercar el ratón al borde
  superior: recarga, enlace a la fuente y pantalla completa.
- Atajos de teclado `F` (pantalla completa), `R` (recargar) y `Esc` (ocultar barra).
- Perfil dedicado de Opera en `%LOCALAPPDATA%\F1TrayMonitor\PlayerProfile` para el modo
  externo, sin tocar el perfil personal.
- Extensión local MV3 (`opera-extension/`) con bloqueo de popups, diálogos, dominios
  publicitarios y overlays a pantalla completa.
- Limpiador compartido entre WebView2 y la extensión de Opera, con bloqueo de peticiones
  publicitarias, cancelación de ventanas nuevas, descargas y permisos.
- Aceptación automática de las puertas de edad de los reproductores.
- Archivo `config.json` con intervalo, días, modo de reproductor, navegador, limpieza y
  número de entradas iniciales.
- Lanzadores portables `F1 Monitor.cmd`, `setup.cmd` y `uninstall.cmd`.
- Modo de autoprueba (`-SelfTest` y `-SelfTestAction`, incluida la variante `video`) con
  registro y captura de pantalla.
- Documentación en español e inglés, guía de contribución, código de conducta, política de
  seguridad, plantillas de issues y pull requests, y flujo de integración continua.

### Cambiado

- El reproductor externo con Opera pasa a ser opcional: `playerMode: "embedded"` es el modo
  por defecto y `playerMode: "external"` conserva el comportamiento anterior.
- Si WebView2 no está disponible, la app lo registra en `monitor.log` y usa el modo externo.
- La ventana principal pierde el marco del sistema y dibuja su propia cabecera.
- La ventana principal usa una barra de búsqueda en lugar de los botones
  *Expandir todo* / *Contraer todo*.
- El contador de entradas se muestra alineado a la derecha en el pie de la ventana.
- El estado de la ventana informa del número de entradas en caché y de la última
  actualización.
- Los tipos de sesión se identifican con una barra de color y un glifo compatible con
  Segoe UI, evitando emojis que se veían como cajas.

### Corregido

- La detección de la ventana del reproductor usa `GetWindowText` en Unicode, por lo que el
  prefijo `F1 ▸` ya no se corrompe.
- El reproductor pasa a primer plano incluso cuando Windows bloquea el cambio de foco.
- La limpieza de perfiles y archivos temporales de pruebas ya no deja procesos abiertos.

### Seguridad

- No se distribuye ninguna copia de Opera ni perfiles de usuario.
- No hay telemetría ni conexiones a servidores propios.
- Los enlaces legítimos del reproductor se marcan con `data-f1-allow` para no romper el
  botón de abrir la fuente.

[1.3.0]: https://github.com/necu/f1-tray-monitor/releases/tag/v1.3.0
[1.2.0]: https://github.com/necu/f1-tray-monitor/releases/tag/v1.2.0
[1.1.0]: https://github.com/necu/f1-tray-monitor/releases/tag/v1.1.0
[1.0.0]: https://github.com/necu/f1-tray-monitor/releases/tag/v1.0.0
