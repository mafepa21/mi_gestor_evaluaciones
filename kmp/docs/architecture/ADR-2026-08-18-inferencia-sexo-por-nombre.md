# ADR 2026-08-18 - Sugerencia conservadora de sexo por nombre

## Estado

Aceptada.

## Contexto

Los baremos de pruebas físicas pueden variar por sexo y el centro puede tener
cientos de alumnos sin ese dato informado. Se necesita reducir el trabajo manual
sin convertir el nombre en una afirmación irreversible ni sobrescribir datos que
ya tengan un origen fiable.

## Decisión

- La app ofrece una acción de grupo para sugerir sexo a partir del nombre de pila.
- El heurístico es local, determinista y conservador: normaliza mayúsculas y
  diacríticos, usa una lista acotada de nombres y solo preselecciona coincidencias
  de confianza alta.
- Los nombres ambiguos, desconocidos o compuestos con señales contradictorias se
  muestran para revisión y permanecen como `UNSPECIFIED` hasta que el docente los
  resuelva por otra vía.
- La aplicación no modifica alumnos con `MANUAL`, `IMPORTED`, `AI_INFERRED` o
  `NAME_INFERRED`. El puente vuelve a comprobar esta condición antes de guardar,
  para protegerse de sugerencias desactualizadas.
- Las asignaciones aceptadas se guardan con `StudentSexSource.NAME_INFERRED` y se
  incluyen en la misma traza de sincronización que el resto de cambios del alumno.
- El origen queda visible en los datos persistidos y la pantalla de sugerencias
  informa de qué registros están protegidos o pendientes de revisión.

## Consecuencias

- El docente puede preparar un grupo grande en una sola operación y revisar las
  excepciones sin editar 300 fichas una a una.
- Un nombre no se considera una identificación segura: la app deja siempre una
  salida neutral y no selecciona un baremo por sexo mientras el dato siga ausente.
- Si el centro necesita precisión normativa, puede corregir cada alumno mediante
  la edición manual o una importación con `IMPORTED`, que prevalecen sobre la
  sugerencia automática.
