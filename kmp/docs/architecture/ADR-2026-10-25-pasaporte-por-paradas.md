# ADR-2026-10-25: Pasaporte por paradas en Entregas web

## Estado

Aprobado

## Contexto

Los pasaportes de las SA (por ejemplo, el de SA 2 Smash Together) son cuadernillos formativos que el alumnado rellena en varias sesiones. Entregas web solo sabía recibir un formulario de una vez: autoevaluación o coevaluación. Hacía falta que el mismo enlace sirviera todo el trimestre y que cada parte llegara sola a la app.

## Decisión

- Nuevo modo `passport` en el manifiesto (contrato compartido con `marfepa/entregas-alumnado`). Cada sección es una parada; todas abiertas desde el primer día y nada obligatorio.
- Las paradas salen del título de los apartados del instrumento: «Parada 1 · Mi mejor reto». Apartados seguidos con el mismo prefijo forman una parada. Si algún apartado no lleva prefijo, todo va en una sola parada (`WebPassportSections`). La hoja de publicar enseña las paradas antes de publicar.
- La web envía **todo** lo que el alumno tiene en su móvil en cada envío, no solo la parada pulsada: el buzón guarda un sobre por alias y el nuevo sustituye al anterior.
- La app junta los envíos en `Documentos/EntregasWeb/<formulario>/pasaporte.json` (`WebPassportStore`): por ítem gana la respuesta del envío más reciente y nunca se borra lo ya recibido. La celda del Cuaderno se guarda con TODAS las respuestas juntas, para que su resumen cuente todas las paradas.
- El estado «Nueva» compara la marca del envío con la última que vio el docente, no con la hora del Mac.
- La entrega no cambia de formato: sigue siendo una carga útil con `answers`.

## Alternativas descartadas

- Un formulario por parada: cuatro enlaces por alumno y cuatro columnas en el Cuaderno.
- Enviar solo la parada pulsada: un sobre sin recoger se perdería al llegar el siguiente.
- Secciones nuevas en la plantilla del instrumento: tocaría `kmp/shared/domain` y SQLDelight, archivos protegidos, para algo que el título ya resuelve.

## Consecuencias

- Sin cambios en KMP ni SQLDelight. El modo se guarda en la columna `mode` que ya existe.
- `pasaporte.json`, como `coevaluaciones.json`, es local y no viaja por Sync LAN: el progreso del pasaporte solo se ve en el Mac que lo publicó.
- Si el alumno borra una respuesta en la web después de enviarla, la app conserva la anterior.
- Si cambia de móvil y envía desde el nuevo antes de que el docente recoja el sobre del antiguo, ese sobre antiguo se pierde (el buzón guarda uno por alias).
