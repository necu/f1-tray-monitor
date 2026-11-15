# Contribuir a F1 Tray Monitor

¡Gracias por querer mejorar el proyecto! Cualquier ayuda cuenta: reglas de bloqueo,
correcciones del scraper, mejoras de interfaz, traducciones o documentación.

## Antes de empezar

- Busca en los [issues](../../issues) si el tema ya está abierto.
- Para cambios grandes, abre primero un issue para acordar el enfoque.
- Para dudas de uso, usa las discusiones o el issue de preguntas.

## Entorno de desarrollo

No hay compilación ni dependencias que instalar:

- Windows 10 u 11.
- PowerShell 5.1 (el incluido en Windows).
- Un editor de texto y, opcionalmente, Opera para probar el reproductor.

Clona el repositorio y ejecuta el monitor en modo visible:

```powershell
git clone https://github.com/necu/f1-tray-monitor.git
cd f1-tray-monitor
powershell -ExecutionPolicy Bypass -File monitor.ps1 -SelfTest
```

## Estilo de código

- PowerShell 5.1 compatible: nada de operadores exclusivos de PowerShell 7.
- Indentación de 4 espacios en `.ps1`; 2 espacios en HTML, CSS, JS y JSON.
- Nombres de función con verbo aprobado (`Get-`, `Set-`, `Start-`, `Build-`, `Update-`…).
- Comentarios y textos de interfaz en español, sin tildes en identificadores.
- Sin dependencias externas ni módulos que haya que instalar.
- Mantén los cambios pequeños y enfocados; evita reformatear archivos enteros.

## Pruebas

Antes de abrir un pull request:

```powershell
# 1. Sintaxis
$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path .\monitor.ps1), [ref]$null, [ref]$errs)
if ($errs) { $errs; exit 1 }

# 2. JSON validos
Get-Content .\config.json -Raw | ConvertFrom-Json | Out-Null
Get-Content .\opera-extension\manifest.json -Raw | ConvertFrom-Json | Out-Null
Get-Content .\opera-extension\rules.json -Raw | ConvertFrom-Json | Out-Null

# 3. Autopruebas de interfaz
powershell -ExecutionPolicy Bypass -File monitor.ps1 -SelfTest -SelfTestAction search
powershell -ExecutionPolicy Bypass -File monitor.ps1 -SelfTest -SelfTestAction accordion
powershell -ExecutionPolicy Bypass -File monitor.ps1 -SelfTest -SelfTestAction page
```

Revisa `monitor.log` y las capturas en `%TEMP%` después de cada autoprueba.

## Añadir reglas de bloqueo

La extensión vive en `opera-extension/`:

- `rules.json`: reglas `declarativeNetRequest`. Usa un `id` numérico único, `priority: 1`,
  `action.type: "block"` y `urlFilter` con el formato `||dominio.com^`.
- `cleaner.css`: selectores CSS de respaldo para ocultar contenedores conocidos.
- `cleaner.js`: listas `AD_HOSTS` y `AD_SELECTOR` para overlays dinámicos.

Comprueba que el JSON sigue siendo válido y que el reproductor no se rompe (el botón
*Abrir en el navegador* debe seguir funcionando gracias a `data-f1-allow`).

## Commits y pull requests

- Mensajes de commit claros, en imperativo y con prefijo opcional:
  `feat:`, `fix:`, `docs:`, `style:`, `refactor:`, `test:`, `chore:`.
- Un pull request = un cambio lógico. Explica el problema y la solución.
- Enlaza el issue relacionado cuando exista.
- Rellena la plantilla del pull request y marca la lista de comprobación.
- La integración continua debe pasar antes de la revisión.

## Traducciones

Los textos de interfaz están en español. Si añades un idioma:

1. Extrae los textos a un archivo de recursos o a una tabla de cadenas.
2. Mantén el español como idioma por defecto.
3. Actualiza `README.md` y `README.en.md` si cambia el comportamiento.

## Código de conducta

Al participar aceptas el [Código de conducta](CODE_OF_CONDUCT.md). Sé respetuoso y
constructivo.

---

## English summary

Contributions are welcome. Use Windows 10/11 and PowerShell 5.1. Keep the style (4-space
indentation in `.ps1`, Spanish UI text, no external dependencies), run the syntax/JSON
checks and the self-tests, and open small focused pull requests with clear commit
messages. See the sections above for details. By participating you agree to the
[Code of Conduct](CODE_OF_CONDUCT.md).
