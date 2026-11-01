# Ticket M · Voz de Pista entiende evaluaciones dictadas alumno a alumno

Base: audio real de 9 min (evaluación de lanzamientos a portería), transcrito solo en el Mac con el motor de voz del sistema y **anonimizado** (15 nombres inventados). El texto real no se guarda en el repo.

## Objetivo / contexto

Hoy ese audio produce 48 acciones, todas «Observación», y 6 fragmentos sin alumno. Debería producir unas 30 evaluaciones (15 alumnas × 1-2 lanzamientos), cada una con su texto completo y sus criterios sugeridos.

## Lo que falla (medido con el motor de reglas)

1. **Nombre como encabezado.** El docente dice el nombre y luego describe («Noemí. Buen pie de apoyo…»). El nombre queda como acción vacía y la descripción va aparte, sin alumno o con un alumno falso.
2. **Alumnos inventados.** Cualquier palabra en mayúscula al inicio se toma como nombre: «Buen», «Hace», «Pide», «Ahora», «Damas». También hay un parecido falso: «Tiene» ≈ Irene.
3. **Inicial del apellido.** «Marta V.», «Marta S.», «Marta B.» quedan como ambiguas aunque la inicial lo resuelve.
4. **Errores típicos del dictado en EF.** «empeño» por empeine, «pie de polio / piedra pollo / pide apoyo / te da apoyo» por pie de apoyo, «posición incorporal / incorporada» por posición corporal, «golpeó / golpeón» por golpeo, «texto / gestor» por gesto, «un peine» por empeine.
5. **Mismo alumno repetido seguido.** «Rocío. Posición… Rocío. posición…» genera dos acciones en vez de una.
6. **Texto largo para Apple Intelligence.** Unos 4.700 caracteres más instrucciones y lista de clase superan el límite del modelo del dispositivo, así que este audio siempre cae a reglas. Es otra causa del «Fallback por reglas».
7. **Intentos.** «primer / segundo lanzamiento», «repite igual que el primero», «igual que Irene».

## Alcance

- Segmentación: un nombre solo (o con inicial) abre un bloque; las frases siguientes sin nombre pertenecen a ese alumno hasta el siguiente nombre. Bloques consecutivos del mismo alumno se unen.
- Resolución: inicial del apellido («Marta V.») desambigua. No crear acciones con palabras que no sean alumnos de la lista; sin alumno claro → «Fragmentos sin alumno».
- Diccionario de correcciones de dictado para EF, aplicado solo al emparejar (el texto mostrado no cambia) y añadido como vocabulario al reconocedor junto con los criterios de las rúbricas cargadas.
- Clasificación: una descripción técnica larga de un alumno es evaluación si hay un instrumento con criterios que encaja; si no, observación con la sugerencia «Evaluar con rúbrica» (PR #340).
- «segundo lanzamiento» crea una acción nueva del mismo alumno; «igual que X» / «igual que el primero» copia los niveles sugeridos de esa acción.
- Apple Intelligence: trocear la transcripción por bloques de alumno para no pasar del límite, y unir los resultados.

## Fuera de alcance

- Entrenar un modelo propio o enviar audio fuera del dispositivo.
- Cambios en KMP, SQLDelight o `KmpBridge.swift`.

## Modelo de datos

Sin cambios de esquema. Solo lógica en `AppleFoundationCourtVoiceService.swift` y `CourtVoiceCriteria.swift`.

## Plan

1. Fixture de regresión con la transcripción anonimizada y una rúbrica inventada de lanzamiento (aproximación, pie de apoyo, posición corporal, gesto, superficie de golpeo, dirección).
2. Segmentación por bloques de alumno + unión de repetidos.
3. Inicial del apellido y bloqueo de alumnos falsos.
4. Diccionario de correcciones de EF + vocabulario del reconocedor.
5. Intentos e «igual que».
6. Troceado del texto para Apple Intelligence.

## Criterios de aceptación (sobre el fixture)

- 0 acciones con alumno inventado («Buen», «Hace»…).
- Cada alumna del dictado tiene sus acciones con todo su texto; 0 o casi 0 fragmentos sin alumno.
- «Marta V.», «Marta S.», «Marta B.» se resuelven a la alumna correcta.
- Las acciones de lanzamiento sugieren los criterios de la rúbrica (pie de apoyo, posición corporal, golpeo…) con nivel coherente.
- Los 29 tests actuales siguen en verde.

## Validación

- `xcodebuild test` de `CourtVoiceCaptureTests`, `CourtVoiceCriteriaTests` y el nuevo test del fixture.
- Build `MiGestorKMPiOS` (simulador).
- Prueba manual: subir el mismo audio en la app (solo en tu dispositivo).

## Agentes

Trabajo en esta sesión; `reviewer` al final.

## Riesgos

- Reglas demasiado ajustadas a un audio: se mitiga manteniendo los tests anteriores y probando frases de otros estilos.
