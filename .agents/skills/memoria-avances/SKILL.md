---
name: memoria-avances
description: Añade avances significativos al archivo raíz `memoria` de Mi Gestor Evaluaciones cuando una conversación produzca cambios, decisiones o aprendizajes que deban recordarse entre sesiones.
version: 1.0.0
---

# memoria-avances

## Rol

Eres el encargado de mantener la memoria viva del proyecto. Tu tarea es actualizar el archivo raíz `memoria` cuando una conversación deje un avance significativo que merezca conservarse para futuras sesiones.

## Cuándo usar este skill

Úsalo al final de una conversación o tarea cuando ocurra al menos uno de estos casos:

- Se implementa una feature nueva.
- Se corrige un bug relevante o difícil de diagnosticar.
- Se cambia persistencia, esquema SQLDelight/Drift, migraciones o repositorios.
- Se toma una decisión de arquitectura o producto.
- Se modifica un flujo importante de SwiftUI, KMP, Flutter, Compose Desktop o Android.
- Se añade o cambia cobertura de tests significativa.
- Se descubre una causa raíz que conviene recordar.
- Se crea una restricción, patrón o regla de trabajo para evitar regresiones.

No lo uses para cambios triviales, retoques cosméticos menores, exploraciones sin conclusión o tareas que no dejen conocimiento reutilizable.

## Archivo objetivo

Actualiza siempre:

`/Users/mariofernandez/Projects/mi_gestor_evaluaciones/memoria`

Si el archivo no existe, créalo con:

- Título.
- Fecha de creación.
- Resumen ejecutivo breve.
- Sección `Bitácora de avances significativos`.

## Formato de entrada en la memoria

Añade cada avance al principio de la sección `## 10. Bitácora de avances significativos`, justo debajo del encabezado.

Usa este formato:

```markdown
### YYYY-MM-DD - Título corto del avance

Resumen:
- Qué cambio se hizo.
- Por qué importa.
- Dónde vive el cambio, con rutas si son útiles.
- Validación realizada, o razón por la que no se pudo validar.

Notas para futuras conversaciones:
- Riesgos, decisiones o follow-ups que conviene recordar.
```

Si el avance es pequeño, puedes usar un párrafo en vez de bullets, pero mantén siempre fecha, título y una frase sobre validación.

## Criterios de calidad

- Escribe en español claro y ejecutivo.
- Registra hechos, no intenciones vagas.
- Incluye rutas concretas cuando ayuden a recuperar contexto.
- Distingue implementado, validado, pendiente y descubierto.
- No pegues diffs ni logs largos.
- No dupliques todo el resumen final de la conversación: sintetiza lo que será útil dentro de semanas.
- Si hubo tests, nombra comandos y resultado.
- Si no hubo tests, di explícitamente `No validado` y el motivo.

## Cuidado con la persistencia

Como el proyecto prioriza "Mejora persistencia", cualquier cambio en datos debe registrar:

- Tabla/modelo/repositorio afectado.
- Si hubo migración.
- Si hubo test de repositorio o dominio.
- Riesgo de compatibilidad con datos existentes.

## Proceso recomendado

1. Relee el resultado real de la tarea actual.
2. Decide si cumple los criterios de avance significativo.
3. Abre `memoria` y localiza la bitácora.
4. Inserta una entrada fechada arriba de las anteriores.
5. Mantén intacto el resumen ejecutivo salvo que el cambio altere la visión general del proyecto.
6. Verifica que la entrada quedó en el sitio correcto.

## Salida esperada

Al responder al usuario, menciona brevemente que la memoria fue actualizada y cita el título de la entrada añadida.

