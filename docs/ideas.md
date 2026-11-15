# Ideas para próximas versiones

Lista viva de mejoras posibles. La columna de estado refleja la evaluación hecha para 1.3.0:
✅ implementada, ⏳ pendiente con encaje, ❌ descartada y por qué.

## Producto

1. ✅ **Comprobación de actualizaciones** — manual desde Ajustes y silenciosa cada 24 h contra
   GitHub Releases, sin descarga automática. Desactivable con `updateCheck`.
2. ✅ **Favoritos y seguimiento** — estrella por entrada, clave estable por carrera o post y
   filtro «solo favoritos» compartido por ventana y bandeja.
3. ❌ **Cuenta atrás del próximo GP** — el blog no publica fechas de sesión, solo el orden de
   rondas; inventar el calendario rompería la app en cuanto cambie.
4. ✅ **Historial de búsquedas** — últimas 8 consultas, sugerencias al enfocar, borrado
   individual y total.
5. ✅ **Importar/exportar ajustes** — un JSON con configuración, favoritos, búsquedas y catálogo.
6. ❌ **Vista compacta** — duplicaría el diseño de tarjetas y el panel de bandeja ya resuelve
   el caso de pantallas pequeñas.
7. ✅ **Visor de registro** — 800 líneas, recargar, copiar y `Esc`, integrado en Ajustes.

## Reproductor

8. ✅ **Memoria por servicio** — recuerda calidad e idioma por plataforma (12 servicios) y
   preselecciona la fuente equivalente.
9. ❌ **Comprobación de salud de fuentes** — exigiría cargar el iframe en segundo plano; con
   contenido cross-origin no hay forma fiable ni barata de medir el estado.
10. ❌ **Miniaturas de vídeo** — mismo límite: no se puede capturar el fotograma de un iframe
    de otro origen.
11. ❌ **Controles de bandeja** (play/pausa/fuente) — el vídeo no es accesible desde
    `player.html` por la política de origen, así que no hay nada que controlar.
12. ❌ **Modo PiP** — requiere control del elemento `<video>`, imposible dentro del iframe.
13. ❌ **Estadísticas ligeras** — dependerían de métricas del reproductor ajeno; sin datos
    reales serían inventadas.

## Catálogo de fuentes

14. ❌ **Editor visual de reglas** — mucho formulario para un archivo que se edita mejor en
    GitHub, y el esquema ya da autocompletado y validación.
15. ⏳ **Importar reglas desde portapapeles** — sencillo de añadir sobre `Import-Settings`,
    pero conviene esperar a que el esquema esté asentado.
16. ✅ **Reglas por prioridad y caducidad** — `priority`, `starts` y `expires` (ISO 8601).
17. ❌ **Catálogos múltiples** — multiplica la resolución de conflictos y las descargas; una
    sola URL editable cubre el caso real.
18. ✅ **Validación en CI del esquema** — `sources.schema.json`, `sources.example.json` y
    `check_sources.ps1` en cada push.

## Accesibilidad y experiencia

19. ⏳ **Navegación completa por teclado en tarjetas** — el buscador y el selector ya van por
    teclado; falta Tab/Enter/flechas entre tarjetas.
20. ❌ **Alto contraste y escala de texto** — el tema oscuro/neón es la identidad de la app y
    una escala global exigiría rehacer cada medida fija.
21. ❌ **Textos en inglés** — la app es en español; mantener dos catálogos de cadenas en
    WinForms añade riesgo sin usuarios que lo pidan.
22. ✅ **Anuncios accesibles** — `aria-live`, `role="status"` y `:focus-visible` en el
    reproductor.
23. ✅ **Pruebas de humo del catálogo** — `check_sources.ps1` valida estructura y la autoprueba
    `catalog` comprueba reglas, favoritos e historial sobre la caché.
24. ✅ **Empaquetado reproducible** — `package.ps1` con lista blanca, config por defecto,
    verificación de BOM/sintaxis/hashes.
25. ✅ **Firma y transparencia** — `releases/SHA256SUMS` con el hash de cada ZIP publicado.

## Siguiente ciclo

- Capturas nuevas de Ajustes (628×950) y de la ventana con favoritos.
- Importar reglas desde portapapeles (15) y navegación por teclado en tarjetas (19).
- Firma Authenticode opcional del ZIP y nota de release con el contenido del paquete.
