# Privacy Notice Draft

Este documento es un borrador operativo para preparar Mi Gestor Evaluaciones
antes de una distribucion comercial o piloto real. Debe revisarse juridicamente
antes de publicarse como politica definitiva.

## Principio de producto

La app debe ser local-first: los datos docentes se guardan en el dispositivo o
en ubicaciones que controle el usuario, salvo que una futura funcion de sync o
backup declare lo contrario de forma explicita.

## Roles pendientes de cerrar

| Rol | Criterio inicial |
|---|---|
| Responsable del tratamiento | El centro, docente o entidad que decide usar la app y determina finalidad y medios. Pendiente de cierre contractual. |
| Encargado del tratamiento | El proveedor de la app solo si presta servicios con acceso a datos personales. Pendiente de contrato. |
| Usuario final | Docente o persona autorizada por el centro. |
| Personas afectadas | Alumnado, tutores legales cuando aplique y profesorado si se registran datos propios. |

## Datos tratados

| Categoria | Ejemplos | Finalidad |
|---|---|---|
| Identificacion de alumnado | Nombre, grupo, numero, observaciones docentes. | Gestion diaria de cuaderno, asistencia e informes. |
| Evaluacion | Calificaciones, rubricas, evidencias, medias, comentarios. | Seguimiento academico y generacion de informes. |
| Asistencia | Faltas, retrasos, sesiones y calendario. | Control docente y seguimiento del grupo. |
| Planificacion | Situaciones, sesiones, tareas, programacion. | Organizacion docente. |
| Educacion Fisica | Pruebas fisicas, escalas, marcas y perfiles. | Evaluacion especifica de EF. |
| Exportaciones y backups | PDF, Excel, copias locales, paquetes de restauracion. | Portabilidad, respaldo y entrega de informacion. |
| IA local o contextual | Prompts, resumenes y evidencias seleccionadas por la app. | Apoyo a informes, radar docente y analisis contextual. |

## Datos que no deben versionarse

No deben subirse al repositorio ni adjuntarse a PRs:

- Bases SQLite, `.db`, `.sqlite`, `.sqlite3`.
- Backups reales, exportaciones con datos reales o capturas identificables.
- Apps empaquetadas, DMG o artefactos con datos embebidos.
- Logs con nombres, calificaciones, observaciones o identificadores de alumnado.

## Almacenamiento y salida de datos

| Flujo | Estado esperado |
|---|---|
| Persistencia local | SQLDelight o almacenamiento local de plataforma. Verificar ruta y protecciones antes de release. |
| Exportacion | Debe requerir accion explicita del usuario y producir archivos revisables. |
| Backup | Debe separar datos reales de fixtures y documentar restauracion y borrado. |
| Sync | Pendiente de politica formal. No asumir nube hasta que exista decision documentada. |
| IA | Priorizar procesamiento local o contextual minimo. Cualquier salida a servicios externos debe quedar bloqueada hasta revisar base legal, contrato y transparencia. |

## Derechos y operaciones necesarias

Antes de piloto o venta, la app debe poder explicar o facilitar:

- Acceso a los datos de un alumno o grupo.
- Rectificacion de errores.
- Supresion cuando corresponda.
- Exportacion o portabilidad razonable.
- Limitacion de uso en backups y artefactos historicos.
- Borrado seguro de datos de ejemplo y datos reales.

## Checklist antes de uso real

- Definir responsable, encargado y contrato aplicable.
- Crear registro de actividades de tratamiento o plantilla para centros.
- Validar base juridica y deber de informacion.
- Confirmar medidas de seguridad por plataforma.
- Verificar exportaciones, backups, restauracion y borrado con fixtures anonimos.
- Preparar protocolo de brechas y canal privado de reporte.
- Revisar transferencias internacionales si se activa cualquier servicio externo.

Fuentes de referencia:

- RGPD, principios de tratamiento y derechos: https://eur-lex.europa.eu/eli/reg/2016/679/oj
- AEPD, Guia para centros educativos: https://www.aepd.es/es/documento/guia-centros-educativos.pdf
- AEPD, brechas de datos personales: https://www.aepd.es/derechos-y-deberes/cumple-tus-deberes/medidas-de-cumplimiento/brechas-de-datos-personales-notificacion
