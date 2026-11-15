# Política de seguridad

## Versiones soportadas

| Versión | Soportada |
|---|---|
| 1.x | Sí |
| < 1.0 | No |

## Cómo reportar una vulnerabilidad

**No abras un issue público** para problemas de seguridad. Usa uno de estos canales:

1. La pestaña **Security → Advisories → Report a vulnerability** del repositorio de GitHub
   (recomendado).
2. Si no está disponible, contacta con los responsables del proyecto a través de su perfil
   de GitHub indicando `SECURITY` en el asunto.

Incluye, si es posible:

- Versión del proyecto y de Windows.
- Pasos para reproducir el problema.
- Impacto esperado (por ejemplo, ejecución de código, fuga de datos, escape del sandbox).
- Cualquier prueba de concepto o registro relevante.

## Qué puedes esperar

- Acuse de recibo en un plazo orientativo de **72 horas**.
- Evaluación inicial y plan de corrección en un plazo orientativo de **7 días**.
- Coordinación contigo antes de publicar detalles y crédito, si lo deseas.
- Divulgación responsable: no publicaremos el fallo hasta que exista una corrección o haya
  pasado un plazo razonable acordado contigo.

## Alcance

Este proyecto es un conjunto de scripts de PowerShell y una extensión de navegador local.
Nos interesan especialmente:

- Ejecución de comandos o scripts a partir de datos scrapeados.
- Inyección de HTML/JavaScript en `player.html`.
- Rutas de archivo construidas con datos no confiables.
- Permisos excesivos o reglas peligrosas en la extensión.
- Cualquier mecanismo que permita saltarse el bloqueo de anuncios y abrir ventanas o
  diálogos no deseados.

## Fuera de alcance

- Vulnerabilidades del sitio web de terceros o de los reproductores enlazados.
- Problemas derivados de ejecutar el proyecto con permisos de administrador o desde rutas
  no confiables.
- Bloqueos de DNS o restricciones de red del proveedor de internet.
- Ataques que requieran acceso físico o una cuenta de usuario ya comprometida.

## Buenas prácticas para usuarios

- Descarga el proyecto solo desde el repositorio oficial.
- Revisa los scripts antes de ejecutarlos; son texto plano.
- Mantén Windows, PowerShell y tu navegador actualizados.
- No ejecutes el monitor desde carpetas compartidas o de red.

## Créditos

Agradecemos a quienes reportan problemas de forma privada y responsable. Si lo deseas,
incluiremos tu nombre o alias en las notas de la versión que corrija el fallo.
