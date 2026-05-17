---
name: memoria-avances
description: Añade avances significativos al archivo raiz `memoria` de Mi Gestor Evaluaciones cuando una conversacion produzca cambios, decisiones o aprendizajes que deban recordarse entre sesiones.
version: 1.0.0
---

# memoria-avances

## Rol

Eres el encargado de mantener la memoria viva del proyecto. Tu tarea es actualizar el archivo raiz `memoria` cuando una conversacion deje un avance significativo que merezca conservarse para futuras sesiones.

## Cuando usar este skill

Usalo al final de una conversacion o tarea cuando ocurra al menos uno de estos casos:

- Se implementa una feature nueva.
- Se corrige un bug relevante o dificil de diagnosticar.
- Se cambia persistencia, esquema SQLDelight/Drift, migraciones o repositorios.
- Se toma una decision de arquitectura o producto.
- Se modifica un flujo importante de SwiftUI, KMP, Flutter, Compose Desktop o Android.
- Se anade o cambia cobertura de tests significativa.
- Se descubre una causa raiz que conviene recordar.
- Se crea una restriccion, patron o regla de trabajo para evitar regresiones.

No lo uses para cambios triviales, retoques cosmeticos menores, exploraciones sin conclusion o tareas que no dejen conocimiento reutilizable.

## Archivo objetivo

Actualiza siempre:

`/Users/mariofernandez/Projects/mi_gestor_evaluaciones/memoria`

Si el archivo no existe, crealo con:

- Titulo.
- Fecha de creacion.
- Resumen ejecutivo breve.
- Seccion `Bitacora de avances significativos`.

## Formato de entrada en la memoria

Anade cada avance al principio de la seccion `## 10. Bitácora de avances significativos`, justo debajo del encabezado.

Usa este formato:

```markdown
### YYYY-MM-DD - Titulo corto del avance

Resumen:
- Que cambio se hizo.
- Por que importa.
- Donde vive el cambio, con rutas si son utiles.
- Validacion realizada, o razon por la que no se pudo validar.

Notas para futuras conversaciones:
- Riesgos, decisiones o follow-ups que conviene recordar.
```

Si el avance es pequeno, puedes usar un parrafo en vez de bullets, pero manten siempre fecha, titulo y una frase sobre validacion.

## Criterios de calidad

- Escribe en espanol claro y ejecutivo.
- Registra hechos, no intenciones vagas.
- Incluye rutas concretas cuando ayuden a recuperar contexto.
- Distingue implementado, validado, pendiente y descubierto.
- No pegues diffs ni logs largos.
- No dupliques todo el resumen final de la conversacion: sintetiza lo que sera util dentro de semanas.
- Si hubo tests, nombra comandos y resultado.
- Si no hubo tests, di explicitamente `No validado` y el motivo.

## Cuidado con persistencia

Como el proyecto prioriza "Mejora persistencia", cualquier cambio en datos debe registrar:

- Tabla/modelo/repositorio afectado.
- Si hubo migracion.
- Si hubo test de repositorio o dominio.
- Riesgo de compatibilidad con datos existentes.

## Proceso recomendado

1. Relee el resultado real de la tarea actual.
2. Decide si cumple los criterios de avance significativo.
3. Abre `memoria` y localiza la bitacora.
4. Inserta una entrada fechada arriba de las anteriores.
5. Mantén intacto el resumen ejecutivo salvo que el cambio altere la vision general del proyecto.
6. Verifica con `rg` o `sed` que la entrada quedo en el sitio correcto.

## Salida esperada

Al responder al usuario, menciona brevemente que la memoria fue actualizada y cita el titulo de la entrada añadida.

