# ADR 2026-08-17 - Baremos graduales para pruebas físicas

## Estado

Aceptada.

## Contexto

Los primeros manifiestos de pruebas físicas describían cinco rangos con una nota fija
por rango. Ese contrato produce saltos visibles, por ejemplo de 7,5 a 10, aunque la
marca solo cambie ligeramente. Las situaciones de aprendizaje necesitan conservar las
referencias diagnósticas existentes, pero también poder declarar una calibración más
fina para tiempos, distancias y repeticiones.

## Decisión

- La versión 2 del manifiesto puede declarar, por escala, `scoring.mode = LINEAR`,
  `roundTo` y una lista ordenada de `points` con `value`, `score`, etiqueta opcional e
  identificador estable.
- La app valida que los puntos sean finitos, estén estrictamente ordenados y tengan
  notas entre 0 y 10. Interpola linealmente entre puntos y satura por los extremos.
- El resultado se redondea al incremento declarado (`roundTo`), por ejemplo `0.1`.
- La base de datos guarda `scoring_mode` y `score_round_to` en la escala. Los puntos se
  reutilizan en la tabla existente de rangos, usando `min_value` como valor de control,
  para no duplicar tablas ni romper copias y repositorios existentes.
- Las escalas v1 y las escalas sin `LINEAR` siguen resolviéndose por tramos (`STEP`).
- En modo diagnóstico la nota interpolada sigue siendo solo una referencia visual: no
  se guarda como nota evaluable, no participa en media ni ranking.

## Consecuencias

- El agente que genera Programaciones debe emitir el nuevo bloque `scoring` y colocar
  suficientes puntos para que la curva represente la calibración pedagógica deseada;
  repetir únicamente los cinco rangos antiguos no aporta más gradualidad.
- Las instalaciones existentes migran de forma aditiva y mantienen su resultado.
- La captura del Cuaderno, la captura específica de pruebas físicas y la resolución del
  puente Apple comparten el mismo método KMP, evitando que cada pantalla produzca una
  nota distinta.
