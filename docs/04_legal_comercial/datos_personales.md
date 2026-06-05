# Datos Personales y Alumnado

Este documento define el mapa operativo de datos personales de Mi Gestor
Evaluaciones. Debe mantenerse actualizado cuando cambien cuaderno, alumnado,
asistencia, informes, backups, sync o IA.

## Principios

- Minimizar datos: guardar solo lo necesario para la finalidad docente.
- Separar datos reales de fixtures y evidencias.
- No versionar informacion identificable.
- Dar control al docente o centro sobre exportacion, backup y borrado.
- Documentar cualquier salida del dispositivo antes de implementarla.

## Mapa de datos

| Modulo | Datos posibles | Fuente de verdad | Riesgo principal |
|---|---|---|---|
| Alumnado | Nombre, grupo, identificadores internos, observaciones. | KMP shared y repositorios/data. | Identificacion indebida o duplicados. |
| Cuaderno | Notas, columnas, categorias, formulas, medias, comentarios. | KMP shared, SwiftUI Apple y persistencia local. | Calculo o exportacion incorrecta. |
| Rubricas | Criterios, niveles, evidencias, evaluaciones. | KMP shared y SwiftUI Apple. | Evaluacion sensible fuera de contexto. |
| Asistencia | Faltas, retrasos, sesiones, fechas. | SwiftUI Apple y dominio KMP segun flujo. | Registro incorrecto o acceso indebido. |
| Planificacion | Sesiones, unidades, situaciones de aprendizaje. | Planner KMP/SwiftUI. | Menor riesgo personal salvo notas libres. |
| Informes | PDF, Excel, resumenes, comentarios, IA. | Servicios Apple/KMP/exportadores. | Fuga por archivo compartido. |
| Backups | Copia completa o parcial de base local. | Backups locales. | Exposicion masiva o restauracion erronea. |
| Sync | Paquetes LAN/local o futuro servicio. | Pendiente de decision. | Transferencia no documentada. |
| IA contextual | Prompts, evidencias, resumenes y diagnosticos. | Servicios Apple locales/contextuales. | Uso excesivo de datos o salida externa. |

## Operaciones que debe soportar el producto

| Operacion | Requisito |
|---|---|
| Alta | Evitar campos obligatorios innecesarios. |
| Edicion | Permitir corregir errores sin tocar historial no relacionado. |
| Borrado | Eliminar o anonimizar datos del alumno cuando corresponda. |
| Exportacion | Requerir accion explicita y dejar claro el alcance. |
| Backup | Proteger copias y separar pruebas de datos reales. |
| Restauracion | Validar integridad antes de sobrescribir datos utiles. |
| Logs | No incluir nombres, notas, observaciones ni identificadores personales. |

## IA local y contextual

Regla inicial: no enviar datos personales a servicios externos sin ADR, base
juridica, contrato, transparencia y control de usuario.

Cada funcion de IA debe documentar:

- Datos de entrada.
- Si opera localmente o sale del dispositivo.
- Resultado generado y donde se guarda.
- Si el docente puede revisar antes de exportar o compartir.
- Como se evita incluir datos no necesarios.

## Backups y exportaciones

Checklist minimo:

- Nombre de archivo sin datos sensibles cuando sea posible.
- Advertencia si el archivo contiene datos personales.
- Ubicacion controlada por el usuario.
- Prueba de apertura y restauracion con fixtures anonimos.
- Borrado documentado de copias temporales.

## Brechas

Una brecha puede incluir perdida, destruccion, alteracion, comunicacion o acceso
no autorizado a datos personales. Si existe riesgo para derechos y libertades,
debe valorarse la notificacion a la autoridad competente. Si el riesgo es alto,
tambien debe valorarse la comunicacion a las personas afectadas.

Fuentes de referencia:

- AEPD, Guia para centros educativos: https://www.aepd.es/es/documento/guia-centros-educativos.pdf
- AEPD, notificacion de brechas: https://www.aepd.es/derechos-y-deberes/cumple-tus-deberes/medidas-de-cumplimiento/brechas-de-datos-personales-notificacion
- RGPD: https://eur-lex.europa.eu/eli/reg/2016/679/oj
