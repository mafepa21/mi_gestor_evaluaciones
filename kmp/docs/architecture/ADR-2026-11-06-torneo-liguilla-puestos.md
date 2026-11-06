# ADR-2026-11-06: Torneo «Liguilla + puestos»

## Estado

Aprobado

## Contexto

En Educación Física hacen falta torneos donde toda la clase juegue lo máximo posible en un tiempo dado y nadie quede eliminado (por ejemplo, bádminton de dobles con 8 pistas y 24 parejas). El número de parejas puede ser impar, porque depende de la inscripción. Los formatos existentes eliminan a quien pierde o reparten por grupos.

## Decisión

- Formato nuevo `leaguePlacement`, en el motor Swift (`PlacementTournament.swift`). Sin cambios en KMP ni SQLDelight: tres campos opcionales en `config_json` (`totalTimeMinutes`, `placementRounds`, `leagueClosedEarly`).
- El docente da parejas, minutos por partido y tiempo total. La app reserva primero el cuadro y da a la liguilla las tandas que queden. Mínimo: 2 partidos de liguilla por pareja. Si no cabe, no crea calendario y sugiere cambios; cada sugerencia se comprueba antes de ofrecerla. Nunca propone cambiar las parejas.
- Liguilla con calendario fijo: descansa quien menos ha descansado y se evita repetir rival. Partidos y descansos difieren como mucho en 1 entre parejas.
- Orden por porcentaje de victorias (empate = media victoria), diferencia de puntos y puntos a favor. Así, descansar más no resta.
- Cuadro fijo calculado al crear el calendario, con huecos «Clasificado N», «Ganador Pn» y «Perdedor Pn». Mejor contra peor, ganadores por arriba y perdedores por abajo. En un grupo impar pasa directo un hueco por el que no pueda llegar una pareja que ya pasó directa, si lo hay.
- Con cuadro corto, la liguilla decide el orden dentro de cada grupo final.
- Se puede pasar al cuadro con partidos de liguilla sin jugar: no cuentan y esa liguilla ya no admite resultados. Se puede deshacer mientras el cuadro no tenga resultados.

## Alternativas descartadas

- Reordenar por liguilla tras cada ronda: necesita calendario dinámico y un resultado corregido movería cruces ya jugados.
- Con 17 parejas, un partido previo entre las dos últimas: quien lo pierde jugaría un solo partido, justo lo que esta modalidad quiere evitar.
- Tiempo solo para la liguilla: el docente quiere decidir el tiempo total del torneo.

## Consecuencias

- La numeración P-n depende de `venueCount` y `placementRounds`. Si cambian, hay que regenerar el calendario: la hoja de inscripción trabaja con un borrador y solo guarda al crear los equipos.
- Una versión anterior de la app no reconoce este formato. iPad y Mac deben actualizarse a la vez.
- Una pareja que abandona con el torneo empezado no tiene tratamiento propio todavía.
