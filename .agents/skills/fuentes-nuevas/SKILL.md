---
name: fuentes-nuevas
description: Busca o recibe enlaces de reproducción y los convierte en reglas del catálogo (sources.json) con validación, prioridad y caducidad. Úsala cuando el usuario pida añadir fuentes, pase un enlace nuevo o quiera buscar reproductores para un GP.
license: MIT
metadata:
  category: content
---

# Añadir fuentes al catálogo

## Antes de tocar nada

1. Lee `sources.json` y `sources.schema.json`.
2. Comprueba que el servicio existe en `services` (si no, propón añadirlo con `label`,
   `short` y `color` `#RRGGBB`).
3. Pregunta solo si falta el GP o la sesión; para el resto, deduce del título.

## Con un enlace que pega el usuario

1. Identifica `service` por el dominio (voe.sx → `voe`, streamtape → `streamtape`,
   ok.ru → `okru`, etc.).
2. Valida que la URL sea `http(s)` y que no exista ya en el catálogo.
3. Añade la regla con la herramienta del proyecto:

```powershell
.\tools\add-source.ps1 -Url "https://..." -Name "VOE · Castellano" -Service voe `
    -Quality 1080p -Lang ES -Priority 20 -Year 2026 -Gp brasil -Session Carrera
```

4. Sin `-DryRun` la herramienta valida el catálogo y guarda copia en `sources.json.bak`.
5. Revisa el resultado con `.\check_sources.ps1` y resume la regla creada.

## Buscar fuentes nuevas en la web

1. Usa `web_search` con el GP, el año y el tipo de sesión; prioriza páginas de índices
   deportivos, no enlaces sueltos de foros.
2. Verifica que el enlace responde (cabecera HTTP 200) y que es un reproductor embebible
   (`/embed/`, `/e/`, iframe permitido). Descarta páginas que exijan descargar un cliente.
3. Propón **como máximo 3 opciones por servicio** y explica calidad/idioma detectados.
4. No inventes URLs ni calidades: si no puedes verificar, dilo y no añadas la regla.
5. Añade las confirmadas con `tools/add-source.ps1`, con `-Expires` si el enlace es temporal
   (por ejemplo, la fecha del GP + 30 días).

## Reglas y prioridad

- `priority` alto gana: usa 30 para la fuente principal, 10 para alternativas.
- `starts`/`expires` en ISO 8601; caducar es mejor que borrar.
- Prefiere `gp` + `session` normalizados (`brasil`, `Carrera`) sobre `id`, que cambia con el
  reescrapeo.
- No dupliques URLs: la herramienta lo impide.

## Límites

- Solo enlaces que el usuario pueda usar legalmente; no busques ni publiques índices de
  piratería ni contenido con derechos de terceros.
- No incluyas credenciales, tokens ni cookies en `sources.json`.
