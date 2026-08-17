# ADR 2026-08-17 - Captura contextual de pruebas físicas en el Cuaderno

## Estado

Aceptada.

## Contexto

Los manifiestos de pruebas físicas importados en modo diagnóstico (`recordScore=false`)
crean columnas de marca bruta en el Cuaderno. El editor numérico genérico no podía
capturar correctamente tiempos ni ofrecer una entrada adecuada para distancia y
repeticiones. Además, una escala presente en el manifiesto podía calcular una
referencia útil aunque no existiera una columna de nota evaluable.

## Decisión

- El `inputKind` de la columna determina el editor contextual: cronómetro y entrada
  manual para `TIME`, teclado decimal para `DISTANCE` y teclado entero para
  `REPETITIONS`.
- Los tiempos se persisten como segundos y se presentan como `MM:SS,CC` para que la
  representación de captura no se confunda con una nota decimal.
- La nota derivada de una escala se calcula al vuelo desde la asignación importada,
  edad y sexo del alumno, y se muestra como "nota de referencia" dentro de la misma
  celda. No se persiste como `PhysicalTestResult`, no crea una columna adicional y no
  participa en media, ranking ni ponderación cuando el manifiesto es diagnóstico.
- Si no existe un rango válido (por ejemplo, el 4×10 m sin baremo trasladable), la
  celda comunica que no hay baremo aplicable.

## Consecuencias

- La captura mantiene una sola columna de dato bruto y respeta el contrato diagnóstico
  de los manifiestos existentes.
- La nota de referencia se recalcula tras guardar y al recargar el Cuaderno, por lo
  que no introduce estado duplicado ni migraciones de base de datos.
- La resolución de escalas se realiza desde el puente Apple cuando la celda necesita
  mostrarla; si el número de columnas físicas crece mucho, podrá añadirse una caché
  de asignaciones como optimización independiente.
