# Security Policy

Mi Gestor Evaluaciones trata informacion docente sensible. Cualquier cambio de
seguridad debe priorizar datos locales, backups, exportaciones y evidencias de
calidad antes de distribucion.

## Versiones soportadas

| Version | Estado |
|---|---|
| `0.3.0-dev` | Desarrollo interno. Sin soporte publico. |
| Releases publicas | Pendiente de definir antes de distribucion. |

## Reportar vulnerabilidades

Hasta que exista un canal publico definitivo, reportar incidencias de seguridad
al propietario del repositorio por un canal privado acordado. No abrir issues
publicas con datos reales de alumnado, bases de datos, backups, capturas con
datos identificables o detalles explotables.

El reporte debe incluir:

- Version, plataforma y rama afectada.
- Descripcion del riesgo y pasos de reproduccion.
- Tipo de datos potencialmente afectados.
- Evidencia anonima o generada con fixtures.
- Si hay exposicion, perdida, alteracion o acceso no autorizado a datos.

## Criterio de severidad

| Severidad | Ejemplos |
|---|---|
| Critica | Acceso no autorizado a datos de alumnado, fuga de backups, exportaciones con datos de otro grupo, bypass de cifrado o borrado destructivo. |
| Alta | Persistencia incorrecta de calificaciones/asistencia, restauracion de backups corrupta, IA usando datos fuera del contexto previsto. |
| Media | Logs con datos personales, permisos de archivo demasiado amplios, errores de validacion que exponen datos parciales. |
| Baja | Metadatos internos, mensajes de error no sensibles o documentacion incompleta. |

## Respuesta a incidentes

1. Aislar la rama, build o artefacto afectado.
2. Preservar evidencia tecnica sin copiar datos personales reales al repo.
3. Clasificar datos, personas afectadas, plataformas y alcance.
4. Evaluar si existe brecha de datos personales.
5. Si hay riesgo para derechos y libertades, preparar notificacion a la autoridad competente dentro del plazo aplicable.
6. Si el riesgo es alto, preparar comunicacion clara a las personas afectadas.
7. Registrar medidas correctoras, pruebas y decision final.

La AEPD indica que las brechas con riesgo deben notificarse sin dilacion indebida
y, cuando proceda, dentro de las 72 horas desde que se tenga constancia. La
decision debe documentarse incluso cuando no se notifique.

## Controles minimos antes de release

- Builds Apple y KMP en verde.
- Pruebas de repositorios y casos de uso criticos.
- Revision de `.gitignore` contra `.db`, `.sqlite`, backups, apps, DMG y datos reales.
- Evidencia de exportacion, borrado y restauracion con datos anonimos.
- Revision de privacidad para alumnado, profesorado, IA local, backups y sync.

Fuentes operativas:

- AEPD, notificacion de brechas: https://www.aepd.es/derechos-y-deberes/cumple-tus-deberes/medidas-de-cumplimiento/brechas-de-datos-personales-notificacion
- RGPD, Reglamento (UE) 2016/679: https://eur-lex.europa.eu/eli/reg/2016/679/oj
