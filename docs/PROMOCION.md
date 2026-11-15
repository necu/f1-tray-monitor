# Plan de difusión — F1 Tray Monitor 1.3.0

Documento de trabajo para publicar el proyecto sin ruido, sin spam y sin promesas que la app no
cumple. Cada bloque está listo para copiar y pegar; solo hay que sustituir lo que va entre
`<...>` si cambia el usuario de GitHub.

- **Repo:** https://github.com/necu/f1-tray-monitor
- **Web:** https://necu.github.io/f1-tray-monitor/
- **Release:** https://github.com/necu/f1-tray-monitor/releases/tag/v1.3.0
- **Licencia:** MIT
- **Idioma:** español primero; inglés en README, release y canales internacionales.

---

## 1. Encuadre: qué se cuenta y qué no

**Qué es:** un cliente de escritorio para Windows que vigila el blog de F1, avisa de las
entradas nuevas y reproduce las fuentes que el usuario añade, dentro de la propia app.

**Qué no es:** no aloja vídeo, no indexa enlaces, no incluye torrents ni contenido con
copyright, no vende cuentas ni suscripciones, no tiene telemetría.

**Mensaje corto (ES):**
> La Fórmula 1, en tu bandeja. Avisos de nuevas sesiones y reproductor integrado, sin
> instalador, sin cuentas y sin publicidad.

**Mensaje corto (EN):**
> Formula 1 in your system tray. New-session alerts and a built-in player. No installer,
> no accounts, no ads.

**Reglas de estilo para todos los mensajes:**

1. Nunca decir «descargas gratis», «streaming gratis» ni «pirata». Se dice «fuentes que
   aporta el usuario» y «cliente de escritorio».
2. Siempre aclarar «proyecto de fans, sin afiliación con Formula 1» cuando el canal sea
   grande.
3. No usar el logotipo oficial de F1 ni capturas con marcas de agua de terceros.
4. Un enlace al repo, no cinco. La web del proyecto ya hace de escaparate.
5. Responder a todo con educación, incluso a las críticas. La primera impresión de un
   proyecto open source se juega en los comentarios.

> **Riesgo de marca:** «F1» es una marca registrada. Es un proyecto de fans y no hay ánimo
> de lucro, pero si Formula 1 o un broadcaster contacta, la respuesta correcta es retirar el
> nombre/marca y seguir como «Tray Monitor». Tenlo previsto; no discutas.

---

## 2. Activos que ya están listos

| Activo | Ruta | Uso |
|---|---|---|
| Banner 1280×320 | `docs/banner.png` | Cabecera del README y de la web |
| Social preview 1280×640 | `docs/social-preview.png` | GitHub → Settings → Social preview; OG/Twitter |
| Captura principal 1180×600 | `docs/monitor.png` | README, web, Reddit, X |
| Ajustes 628×740 | `docs/settings.png` | Segundo pantallazo |
| Bandeja 446×604 | `docs/tray.png` | Tercer pantallazo |
| Página del proyecto | `docs/index.html` | GitHub Pages |
| ZIP + SHA256 | `releases/` + `releases/SHA256SUMS` | Release |
| Textos legales | `LICENSE`, `SECURITY.md`, `CONTRIBUTING.md` | Credibilidad |

**GIF que falta (opcional, 10 s):** grabar con ScreenToGif: abrir la ventana → escribir
«brasil» → desplegar una tarjeta → reproducir → arrastrar el divisor. Sin audio. Un GIF de
10 s convierte más que tres capturas. Se guarda como `docs/demo.gif` y se enlaza en el
README y en la web.

---

## 3. Calendario recomendado

La difusión funciona mejor cuando hay una carrera cerca: el interés por F1 sube de jueves a
domingo. Publica el **martes o miércoles por la mañana (CET)**, nunca el domingo de carrera.

| Momento | Acción |
|---|---|
| D-2 (martes) | Repo público, Pages activa, release `v1.3.0` y social preview. Silencio. |
| D-1 (miércoles) | Show HN + r/PowerShell. Responde comentarios 2 h seguidas. |
| D0 (jueves) | r/formula1 + X (hilo ES/EN) + LinkedIn. |
| D+1 (viernes) | Mastodon + Bluesky + foros en español. |
| D+3 (domingo) | No publicar. Solo responder. |
| D+7 | Revisar métricas, abrir 3 issues con ideas de `docs/ideas.md`, agradecer. |
| D+14 | Segundo empujón: «cómo se hizo» (PowerShell/WinForms) en r/PowerShell o dev.to. |

No publiques lo mismo en cinco sitios el mismo día: los moderadores lo leen como spam.

---

## 4. Canales y mensajes

### 4.1 GitHub — ficha del repositorio

**Descripción (160 caracteres):**

> Monitor de escritorio para Windows que avisa de las nuevas sesiones de F1 y las reproduce dentro de la app. Portable, sin instalador y sin telemetría.

**Topics:**

```text
formula1 f1 powershell winforms webview2 windows desktop-app tray motorsport open-source
```

**Homepage:** `https://necu.github.io/f1-tray-monitor/`

**Social preview:** subir `docs/social-preview.png` en Settings → Social preview.

**Release `v1.3.0` (título y cuerpo):**

```text
F1 Tray Monitor 1.3.0 — favoritos, historial y paquete reproducible

- Favoritos por GP y sesión, con filtro global.
- Historial de búsquedas con sugerencias.
- Importar/exportar ajustes en un JSON portable.
- Visor de registro y comprobación de versiones.
- Catálogo con prioridad y caducidad.
- Reproductor accesible y paquete reproducible (mismo SHA256 en cada build).

Descarga: F1-Tray-Monitor-1.3.0.zip
SHA256: 9D7FA28830B278245F0B258D76C18942E3D2043363D2AF17097A73DA22D1B8BF

Windows 10/11 · PowerShell 5.1 · WebView2 · MIT
Proyecto de fans sin afiliación con Formula 1. No aloja ni redistribuye vídeo.
```

**Primer issue (creado por ti, etiqueta `enhancement`):**

> **Roadmap abierto: ¿qué falta para 2.0?**
> La 1.3.0 está cerrada. La siguiente fase apunta a mpv embebido y aria2c para descargas
> legales. Si echas en falta algo, dilo aquí: qué usas, qué te falta y en qué Windows.

---

### 4.2 Hacker News — Show HN (inglés)

**Cuándo:** martes o miércoles, 09:00–11:00 CET (08:00–10:00 UTC).

**Título:**

```text
Show HN: F1 Tray Monitor – a Windows tray app for race weekends
```

**Texto:**

```text
I built a small Windows tray app for following Formula 1 sessions. It watches the blog for
new posts, shows a toast, and plays the sources I add in a WebView2 panel next to the list.
No installer, no account, no telemetry: it is a PowerShell 5.1 + WinForms app bundled with
the WebView2 SDK.

What is interesting (to me): the whole UI is hand-built WinForms, the source catalog is a
versioned JSON file, the player is a local HTML deck, and the app has self-tests for the
catalog, layout and tray panel. Packaging is reproducible: fixed ZIP timestamps, same hash
on every build.

It does not host, index or redistribute video. It is a desktop client for links the user
provides; the catalog ships empty and is meant to be edited.

Repo: https://github.com/necu/f1-tray-monitor
Release: https://github.com/necu/f1-tray-monitor/releases/tag/v1.3.0

Happy to answer questions about the WinForms/WebView2 side, the DPI mess, or the packaging.
```

**Primer comentario propio (para dejar contexto):**

```text
A few implementation notes:
- The list caches 246 WinForms cards and reorders them instead of rebuilding, so filtering
  went from ~6 s to ~0.3 s.
- The app is intentionally not DPI-aware: Windows scales the whole window, which avoids
  clipped labels at 125–150 %. Per-monitor v2 is a 2.0 task.
- The ZIP excludes runtime state and uses fixed entry dates, so two builds give the same
  SHA256.
```

---

### 4.3 Reddit — r/formula1 (inglés)

**Antes de publicar:** lee las reglas del día y el hilo de autopromoción. Si no está claro,
manda un modmail corto preguntando si un proyecto de fans gratuito encaja. Un «no» a tiempo
ahorra un baneo.

**Título:**

```text
I built a Windows tray app that notifies you when new F1 sessions are posted (open source, no ads)
```

**Cuerpo:**

```text
I follow the blog during race weekends and got tired of refreshing it, so I built a small
Windows app that sits in the tray and tells me when a new session appears.

What it does:
- Checks the blog every few minutes and shows a Windows notification.
- Lets you search by GP, year or session and expand a card to see the available sources.
- Plays the source you pick inside the app (WebView2), next to the list.
- Favorites, search history and portable settings.
- No installer, no account, no telemetry. MIT.

What it does not do: it does not host, index or redistribute video. It is a desktop client
for links the user provides. The catalog is a JSON file you can edit; the app ships with no
sources configured.

Screenshots: <link a la web o a las imágenes>
Repo: https://github.com/necu/f1-tray-monitor
Release: https://github.com/necu/f1-tray-monitor/releases/tag/v1.3.0

It is a fan project, not affiliated with Formula 1. Feedback welcome, especially from people
on 125–150 % display scaling.
```

**Si preguntan «¿de dónde salen los enlaces?»:**

> The app does not ship sources. You add them to `sources.json` (or use the catalog file you
> maintain). I do not host or index anything; it is the same as opening a link in your browser,
> but with a clean player and a list.

---

### 4.4 Reddit — r/PowerShell (inglés)

**Título:**

```text
F1 Tray Monitor: a PowerShell 5.1 + WinForms tray app with WebView2 and self-tests
```

**Cuerpo:**

```text
Sharing a completed side project because the constraints may be useful to others:

- Windows PowerShell 5.1 only (no PS7), WinForms built by hand, WebView2 for the player.
- ~9k lines in one script, but organized by sections and with `-SelfTest` actions for
  catalog, search, accordion, resize and UI screenshots.
- The source catalog is a versioned JSON with schema + validator (`check_sources.ps1`).
- Packaging is reproducible: fixed ZIP entry timestamps, SHA256SUMS, no runtime state.
- Two bugs worth mentioning: removing `SetProcessDPIAware()` fixed clipped labels at 150 %,
  and a `Show()`/`Close()` race in a suggestion popup needed a re-entrancy guard.

Repo: https://github.com/necu/f1-tray-monitor
It is an F1 fan app, but the PowerShell/WinForms bits are the interesting part for this sub.
Happy to share details about the DPI decision or the self-test harness.
```

---

### 4.5 Reddit — r/Windows10 y r/software (inglés)

**Título (r/Windows10):**

```text
A portable Windows tray app for F1 race weekends (no installer, no telemetry)
```

**Título (r/software):**

```text
F1 Tray Monitor – open-source tray app for F1 sessions, with a built-in player
```

**Cuerpo común (adaptar el primer párrafo):**

```text
F1 Tray Monitor is a portable Windows 10/11 app: it lives in the tray, watches the F1 blog
for new sessions, and plays the source you choose in a WebView2 panel. No installer, no
account, no telemetry, MIT.

It is a client for links the user provides; it does not host or index video.
Repo + screenshots: https://github.com/necu/f1-tray-monitor
```

---

### 4.6 X / Twitter — hilo en español

**Tuit 1 (con `docs/social-preview.png`):**

> He publicado **F1 Tray Monitor 1.3.0**: una app de bandeja para Windows que te avisa cuando
> salen nuevas sesiones de F1 y las reproduce dentro de la app.
>
> Sin instalador, sin cuentas y sin telemetría. Código abierto. 🏁
>
> https://github.com/necu/f1-tray-monitor

**Tuit 2:**

> Vive en la bandeja y revisa el blog cada pocos minutos. Cuando hay algo nuevo, salta el
> aviso. Abres, buscas el GP y ves la sesión sin popups ni capas raras.

**Tuit 3:**

> El catálogo de fuentes es un JSON versionado que puedes editar: servicios, prioridad,
> caducidad y reglas por GP, año o sesión. Sin recompilar nada.

**Tuit 4:**

> Favoritos por sesión, historial de búsquedas, ajustes portables en un JSON, visor de
> registro y comprobación de versiones. Todo en una ventana de 1180×600.

**Tuit 5:**

> Por dentro: PowerShell 5.1 + WinForms + WebView2. Sin instalador, sin dependencias raras y
> con autopruebas. El ZIP es reproducible: mismo SHA256 en cada build.

**Tuit 6:**

> Web, capturas y descarga:
> https://necu.github.io/f1-tray-monitor/
>
> Es un proyecto de fans, sin afiliación con Formula 1. No aloja ni redistribuye vídeo.

**Versión EN (un solo tuit con imagen):**

> I shipped F1 Tray Monitor 1.3.0: a Windows tray app that notifies you about new F1 sessions
> and plays the source you pick inside the app. No installer, no account, no telemetry. MIT.
> https://github.com/necu/f1-tray-monitor

**Hashtags (máximo 3):** `#F1 #OpenSource #PowerShell`

---

### 4.7 LinkedIn — español

**Texto:**

> Después de varias semanas de trabajo, he cerrado **F1 Tray Monitor 1.3.0**, una app de
> escritorio para Windows que reúne tres cosas que uso cada fin de semana de carrera:
> avisos de nuevas sesiones, un listado buscable y un reproductor integrado.
>
> Lo interesante no es la app, es cómo está hecha: PowerShell 5.1 y WinForms, sin instalador,
> sin telemetría y con un ZIP reproducible. El catálogo de fuentes es un JSON versionado y
> la app incluye autopruebas de catálogo, búsqueda, disposición y bandeja.
>
> Es código abierto (MIT) y un proyecto de fans, sin afiliación con Formula 1. No aloja ni
> redistribuye vídeo: es un cliente para enlaces que aporta el usuario.
>
> Repo: https://github.com/necu/f1-tray-monitor
> Web: https://necu.github.io/f1-tray-monitor/
>
> Si trabajas con PowerShell, WinForms o WebView2 y quieres comentar el enfoque, soy todo
> oídos.

**Primer comentario:** añade una captura y el enlace a la release.

---

### 4.8 Mastodon — español

**Instancia recomendada:** `fosstodon.org` (tecnología/open source) o `mastodon.social`.

> F1 Tray Monitor 1.3.0 ya está publicado: una app de bandeja para Windows que avisa de las
> nuevas sesiones de F1 y las reproduce dentro de la app. Portable, sin cuentas y sin
> telemetría. Código abierto (MIT).
>
> https://github.com/necu/f1-tray-monitor
>
> #F1 #Formula1 #OpenSource #Windows #PowerShell #WebView2

**Versión EN:**

> F1 Tray Monitor 1.3.0 is out: a Windows tray app that notifies you about new F1 sessions
> and plays the source you pick inside the app. Portable, no account, no telemetry. MIT.
> https://github.com/necu/f1-tray-monitor
> #F1 #OpenSource #Windows #PowerShell

---

### 4.9 Bluesky — español

> He publicado F1 Tray Monitor 1.3.0 🏁
> Una app de bandeja para Windows: avisa de nuevas sesiones de F1 y las reproduce dentro de
> la app. Sin instalador, sin cuentas, sin telemetría. Open source.
> https://github.com/necu/f1-tray-monitor

Adjunta `docs/social-preview.png`.

---

### 4.10 Product Hunt — inglés (opcional)

Solo si tienes cuenta con antigüedad y alguien puede acompañar el lanzamiento. Un lanzamiento
en solitario sin comunidad previa suele quedar en la página 3.

**Tagline (60 caracteres):**

```text
Formula 1 in your tray: alerts + player, no installer
```

**Descripción:**

```text
F1 Tray Monitor is a portable Windows app for race weekends. It sits in the tray, watches the
F1 blog for new sessions, and plays the source you choose in a clean built-in player. It does
not host or index video: it is a desktop client for links the user provides. No account, no
telemetry, MIT.
```

**Primer comentario:**

```text
Maker here. I built this because I was tired of refreshing the blog and fighting popups on
race weekends. The app is PowerShell 5.1 + WinForms + WebView2, with a versioned JSON catalog
and reproducible packaging. Happy to answer anything about the stack or the legal framing.
```

---

### 4.11 Foros y comunidades en español

**ForoCoches (subforo F1) / Motorpasión / comunidades de F1:**

> **Proyecto: monitor de F1 para Windows (open source)**
>
> He hecho una app de bandeja para seguir las sesiones: avisa cuando hay una entrada nueva,
> permite buscar por GP y reproduce la fuente que elijas dentro de la app. Sin instalador,
> sin cuentas y sin publicidad. El catálogo de fuentes es un JSON editable.
>
> No aloja ni indexa vídeo; es un cliente para enlaces que aporta el usuario. Es un proyecto
> de fans sin afiliación con Formula 1.
>
> Repo y capturas: https://github.com/necu/f1-tray-monitor
>
> Si algún mod considera que no encaja, lo retiro sin problema.

**F1Technical (inglés):**

> **Small open-source Windows client for race weekends**
>
> I built a tray app that watches the blog and plays the source you add, with a clean player
> and a searchable list. No installer, no account, no telemetry. It does not host or index
> video. Repo: https://github.com/necu/f1-tray-monitor — feedback welcome, especially on the
> WebView2/DPI side.

---

### 4.12 Discord / Telegram (mensaje corto)

Solo en servidores donde la autopromoción esté permitida y en el canal correcto.

> Hola 👋 He publicado una app de bandeja para Windows para seguir las sesiones de F1: avisa
> de entradas nuevas y reproduce la fuente que elijas dentro de la app. Sin instalador, sin
> cuentas y sin telemetría. Es open source y no aloja vídeo.
> https://github.com/necu/f1-tray-monitor
> Si no va aquí, decídmelo y lo borro.

---

### 4.13 Creadores de contenido (DM / email)

**Asunto:** `F1 Tray Monitor — app gratuita para tus fines de semana de carrera`

> Hola <nombre>:
>
> Soy <tu nombre>, desarrollador de F1 Tray Monitor, una app de escritorio gratuita y open
> source para Windows que avisa de las nuevas sesiones y las reproduce en un reproductor
> limpio dentro de la app.
>
> No aloja ni indexa vídeo: es un cliente para enlaces que aporta el usuario. Puede venirte
> bien para seguir el fin de semana sin pestañas ni popups. Si quieres, te paso el ZIP y una
> captura; no hay ningún pago ni condición.
>
> Repo: https://github.com/necu/f1-tray-monitor
>
> Gracias por el contenido que haces.

---

## 5. Respuestas a las objeciones más probables

**«Esto es piratería.»**

> No. La app no incluye, aloja ni indexa enlaces. Es un cliente de escritorio: el usuario
> añade sus fuentes igual que abriría una URL en el navegador. El catálogo del repo está
> vacío y solo contiene metadatos.

**«Windows me dice que el ZIP no es seguro / SmartScreen.»**

> Es normal en un proyecto sin certificado de firma. El ZIP es reproducible y publico su
> SHA256 en `releases/SHA256SUMS`; puedes comprobarlo con `Get-FileHash`. Si quieres, firma
> el binario con Authenticode y compártelo.

**«¿Por qué PowerShell y no Electron?»**

> Porque el objetivo era no instalar nada: PowerShell 5.1 y WebView2 ya están en Windows.
> El precio es una UI hecha a mano y algo más de trabajo en DPI; la ventaja es un ZIP de
> ~580 KB y cero dependencias.

**«¿Funciona en Mac/Linux?»**

> No. Es WinForms + WebView2 y usa la bandeja de Windows. Si hay interés, la vía sería un
> frontend web o mpv, pero no está en el roadmap inmediato.

**«No me reproduce un vídeo.»**

> Abre el registro (Ajustes → Ver registro) y mira si el iframe cargó. La app no controla el
> contenido de fuentes cross-origin: si el proveedor bloquea iframes, hay que abrir la
> entrada en el navegador o cambiar de fuente. Es una limitación del proveedor, no del
> reproductor.

**«¿Qué pasa con la marca F1?»**

> Es un proyecto de fans, gratuito y sin afiliación. No usa el logotipo oficial. Si Formula 1
> lo pide, se renombra el proyecto; no hay ánimo de lucro.

---

## 6. Métricas y seguimiento

| Métrica | Dónde | Objetivo realista (primer mes) |
|---|---|---|
| Visitas al repo | GitHub → Insights → Traffic | 1.000–3.000 |
| Descargas del ZIP | Release → Assets | 100–300 |
| Estrellas | GitHub | 30–100 |
| Comentarios útiles | HN / Reddit | 10–30 |
| Issues abiertas | GitHub | 3–10 |

Apunta el **referrer** de cada pico (GitHub Traffic → Referring sites) para saber qué canal
funciona. No cambies el discurso a mitad de semana: deja que cada canal madure 48 h.

---

## 7. Checklist de ejecución

- [ ] `gh auth login` (una vez; guarda el token en el Credential Manager).
- [ ] `tools/publicar.ps1 -DryRun` y, si todo cuadra, `tools/publicar.ps1`.
- [ ] GitHub → Settings → Social preview → subir `docs/social-preview.png`.
- [ ] GitHub → Settings → Pages → `main` / `/docs` (el script también lo intenta).
- [ ] Release `v1.3.0` con ZIP y `SHA256SUMS` adjuntos.
- [ ] Pegar el SHA256 en la nota de release.
- [ ] Crear el issue «Roadmap abierto».
- [ ] Publicar Show HN (martes/miércoles).
- [ ] Publicar r/PowerShell el mismo día, 2 h después.
- [ ] Publicar r/formula1 al día siguiente, con capturas.
- [ ] Publicar hilo de X + LinkedIn.
- [ ] Publicar Mastodon + Bluesky + foro en español.
- [ ] Responder todos los comentarios de las primeras 48 h.
- [ ] Revisar métricas a los 7 días y abrir 3 issues con ideas.

---

## 8. Qué necesita el usuario (credenciales)

El agente puede dejar el repo, el commit local, el ZIP y los textos listos, pero **no puede
autenticarse como tú**. Hacen falta estas cuentas:

1. **GitHub** (`necu` o el usuario real). `gh auth login` → GitHub.com → HTTPS → navegador.
   Eso configura también el credential helper de Git para el `push`.
2. **Hacker News**, **Reddit**, **X**, **LinkedIn**, **Mastodon**, **Bluesky**: cuenta y
   sesión en el navegador. El agente no publica en redes sociales.
3. **Email** para los creadores de contenido, si se hace el envío personalizado.

Si tu usuario de GitHub no es `necu`, dilo antes de ejecutar el script: cambia el `Owner`,
las URLs de `README`, `docs/index.html`, `config.json` y `releases/README.md`.

---

## 9. Después del lanzamiento

- No mezcles 2.0 (mpv/aria2) con el cierre de 1.3.0. Primero deja que la gente lo pruebe.
- Etiqueta las issues como `bug` / `enhancement` y responde en 48 h.
- Si alguien manda una fuente nueva, usa `tools/add-source.ps1` y `check_sources.ps1`.
- Publica una nota corta «cómo se hizo» a las 2 semanas: es el contenido que más tráfico
  recurrente trae a un proyecto de escritorio.
