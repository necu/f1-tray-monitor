# Paquetes publicados

ZIP portables de cada versión. Todos usan la carpeta `f1-tray-monitor/` como raíz y se
descomprimen sobre cualquier carpeta: no hay instalador ni permisos de administrador.

La descarga oficial es **GitHub Releases**; la copia local de cada ZIP vive en esta carpeta
pero no se versiona para no engordar el repositorio.

| Versión | Fecha | Novedades principales |
|---|---|---|
| [1.3.0](https://github.com/necu/f1-tray-monitor/releases/download/v1.3.0/F1-Tray-Monitor-1.3.0.zip) | 15/11/2026 | Favoritos, historial de búsquedas, ajustes portables, visor de registro, comprobación de versiones, prioridad/caducidad del catálogo, accesibilidad del reproductor y empaquetado reproducible. |
| [1.2.0](https://github.com/necu/f1-tray-monitor/releases/download/v1.2.0/F1-Tray-Monitor-1.2.0.zip) | 14/11/2026 | Catálogo remoto de fuentes, selector agrupado con teclado, bloqueador más estricto, aviso animado de bandeja, icono oficial y capas de ventana. |
| [1.1.0](https://github.com/necu/f1-tray-monitor/releases/download/v1.1.0/F1-Tray-Monitor-1.1.0.zip) | 12/11/2026 | Panel de bandeja propio, ajustes por iconos, neón por equipos y modo solo vídeo. |
| [1.0.0](https://github.com/necu/f1-tray-monitor/releases/download/v1.0.0/F1-Tray-Monitor-1.0.0.zip) | 12/11/2026 | Primera versión: bandeja, vigilancia automática, buscador, paginación y reproductor incrustado. |

Cada ZIP tiene su hash SHA256 en [`SHA256SUMS`](SHA256SUMS); tras descargarlo, compruébalo con
`Get-FileHash .\F1-Tray-Monitor-1.3.0.zip -Algorithm SHA256`.

Los paquetes no incluyen datos de ejecución: `f1_posts.json`, `f1_state.json`,
`f1_loadall_progress.json`, `sources.cache.json` ni `monitor.log`. Se generan solos al
arrancar. El detalle de cada cambio está en [`../CHANGELOG.md`](../CHANGELOG.md) y las
mejoras previstas en [`../docs/ideas.md`](../docs/ideas.md).

> El catálogo (`sources.json`) solo contiene URLs y metadatos: el proyecto no aloja ni
> redistribuye vídeo.
