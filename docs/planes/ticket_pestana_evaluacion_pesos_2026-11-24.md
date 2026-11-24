# Ticket L: Pestaña de evaluación con pesos por bloque y valoración en grupo

Estado: aprobado por el docente el 2026-11-24, con permiso explícito para tocar `kmp/shared/domain/` y `kmp/data/src/commonMain/sqldelight/`. Maqueta: `docs/maquetas/pestana-evaluacion/mockup/index.html`.
Rama: `codex/pestana-evaluacion-pesos` (desde `main` en `80a495aa`).

## 1. Objetivo y contexto

Hoy cada pestaña del Cuaderno tiene su propia Media, y el «Comentario de evaluación» vive en una pestaña. El docente organiza el trimestre por situaciones de aprendizaje (una pestaña por SA: Hockey, Ultimate), así que no hay ningún sitio que reúna la evaluación entera.

Además, valorar alumno por alumno es lento.

Objetivo:
1. Una **pestaña de evaluación** (1.ª, 2.ª y 3.ª) que reúna sus bloques (las pestañas de cada SA), con una nota de evaluación con dos niveles de peso, más el comentario.
2. **Valorar más rápido**: por ficha para muchos alumnos a la vez, copiar del trimestre anterior y fichas propias.

Regla de la nota que ha pedido el docente: cada nota tiene su peso dentro de su bloque (lo que ya existe: 33/33/33 o 30/30/30/10), y cada bloque tiene su peso en la evaluación (Hockey 60 %, Ultimate 40 %).

**Nota de evaluación** = Σ (peso del bloque × media del bloque) / Σ pesos de los bloques que tienen nota.

## 2. Alcance

**A. Pestaña de evaluación**
1. Usa la jerarquía que ya existe en datos (`NotebookTab.parentTabId`, sincronizada por SyncLAN): la pestaña raíz «1.ª Evaluación» es la evaluación y sus hijas son los bloques. Hoy la app solo muestra las pestañas raíz y nunca crea hijas.
2. Barra de pestañas a dos niveles: arriba evaluaciones y pestañas sueltas; debajo «Resumen» y los bloques de la evaluación elegida, cada uno con su peso.
3. **Resumen**: las columnas que cuentan de cada bloque, agrupadas por bloque y plegables (plegado solo enseña la media del bloque), la media de cada bloque, la «Nota evaluación» y el «Comentario de evaluación». Son las mismas celdas, no copias: se pueden editar.
4. **Peso de bloque** (nuevo dato, ver sección 4) y hoja «Pesos» con el total y la opción «Igualar». Si no suman 100, se reparte en proporción. El peso de cada nota usa el editor que ya existe.
5. Un bloque sin notas no cuenta como 0: la nota sale con los demás y se avisa.
6. «Cómo sale la nota»: una explicación por bloque (media, peso, aporta).
7. **Nueva pestaña**: se elige la evaluación (por defecto la del trimestre actual, por fecha) y el peso. La evaluación se crea sola la primera vez. Una «pestaña suelta» no entra en ninguna evaluación.
8. **Organizar pestañas…**: mete las pestañas que ya existen en una evaluación (propuesta por la fecha de sus notas). No toca ninguna nota.
9. **Borrar una evaluación** nunca borra sus bloques: antes de borrar se sueltan (`parentTabId = null`). Hoy la base de datos borra las hijas en cascada (`ON DELETE CASCADE`).
10. **Integración**:
    - «Cerrar evaluación» trabaja sobre la evaluación (si se abre desde un bloque, usa su evaluación).
    - El comentario se guarda en la evaluación.
    - «Generar lote» propone la evaluación.
    - «Exportar a Educamos»: la nota final es la nota de evaluación y cada columna «Media de SA» toma la media de su bloque (hoy toman todas la Media de la pestaña activa, ver sección 7).

**B. Valorar más rápido**
1. **Valorar por ficha** (desde Cerrar evaluación › Comentarios): se elige grupo y ficha, se marcan alumnos, con «Marcar a todos», «Marcar los que tienen el sello» y «Quitar todos». Añade la ficha a «Tu valoración» de cada alumno sin borrar lo que ya tenía (`QuickNoteComposer`).
2. **Copiar del trimestre anterior**: copia «Tu valoración» y, si se elige, el comentario de evaluación como borrador. Por defecto no pisa a quien ya tiene texto. Se puede deshacer.
3. **Fichas propias**: «＋ Nueva ficha» en cada grupo; editar y borrar. Se guardan en la base de datos y se sincronizan entre iPad y Mac.

## 3. Fuera de alcance

- Pestañas a más de dos niveles (evaluación › bloque › sub-bloque).
- Peso de las categorías dentro de un bloque.
- Fórmulas que mezclen bloques.
- Nota final de curso que combine las tres evaluaciones.
- Cambiar cómo redacta la IA.
- Compose Desktop (`kmp/desktopApp/`).

## 4. Modelo de datos

Migración `50.sqm` (aditiva y sin pérdida):
- `ALTER TABLE notebook_tabs ADD COLUMN weight REAL;` → `NULL` = peso igual que los demás bloques.
- `CREATE TABLE quick_note_phrases (id TEXT PRIMARY KEY, group_key TEXT NOT NULL, text TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, is_deleted INTEGER NOT NULL DEFAULT 0, updated_at_epoch_ms INTEGER NOT NULL DEFAULT 0, device_id TEXT, sync_version INTEGER NOT NULL DEFAULT 0);` → fichas propias del docente, con borrado lógico para que el borrado se sincronice.

Cambios de dominio:
- `NotebookTab.weight: Double? = null` (en `kmp/shared/domain/`, protegido).
- `QuickNotePhrase(id, group, text, order)`.

KMP (lógica):
- `NotebookEvaluationAverage`: media por bloque (motor actual `computeAverageExplanation` con las columnas del bloque) y combinación por peso de bloque, con su explicación (`NotebookEvaluationExplanation`: bloques, media, peso, aporta, bloques sin nota).
- `withActiveTabAverages`: si la pestaña activa es una evaluación, `weightedAverage` = nota de evaluación; si es un bloque o una suelta, igual que hoy.

SyncLAN: añadir `weight` al payload de pestañas y una entidad nueva `quick_note_phrase`, con fusión por última modificación (como el resto).

No cambia: notas, celdas, columnas ni su `tabIds` (una columna de Hockey sigue siendo de Hockey; el Resumen la muestra por ser hija).

## 5. Plan

1. **Datos**: migración 50, consultas, repositorio de pestañas (peso, soltar hijas antes de borrar) y repositorio de fichas. Pruebas `:data:desktopTest`.
2. **KMP**: `NotebookTab.weight`, cálculo de la nota de evaluación y su explicación, columnas visibles en el Resumen y `withActiveTabAverages`. Pruebas `:shared` con ejemplos 60/40 y 33/33/33 y 30/30/30/10, bloque vacío, pesos que no suman 100 y celdas vacías que cuentan 0.
3. **SyncLAN**: peso de pestaña y fichas propias. Prueba de ida y vuelta.
4. **Swift, barra y Resumen**: barra a dos niveles, Resumen con bloques plegables, «Nota evaluación» y explicación.
5. **Swift, hojas**: Pesos, Nueva pestaña con evaluación, Organizar pestañas y alerta de borrado.
6. **Swift, integración**: Cerrar evaluación, Generar lote y Exportar a Educamos (media por bloque y nota final).
7. **Swift, valoración**: Valorar por ficha, Copiar del trimestre anterior y Fichas propias.
8. Compilar Mac e iPad, suite completa, revisión HIG del código y registro.

## 6. Agentes

- `architect` (Opus): revisa el plan de datos y SyncLAN antes del paso 1.
- Implementación: agente principal (Opus), un paso cada vez.
- `tests`: pruebas KMP, data y XCTest.
- `ui-reviewer`: maqueta (hecho) y código final.
- `janitor` y `reviewer`: antes de la PR.

## 7. Riesgos y puertas humanas

- **Archivos protegidos**: requiere permiso explícito para tocar `kmp/shared/domain/` (`NotebookTab.weight`, `QuickNotePhrase`) y `kmp/data/src/commonMain/sqldelight/` (migración 50). Motivo: el peso de bloque y las fichas propias tienen que guardarse y sincronizarse; no hay un campo que se pueda reutilizar sin trucos.
- **Borrado en cascada**: hoy borrar una pestaña padre borra las hijas. Se corrige soltando las hijas antes de borrar, con prueba.
- **SyncLAN**: un dispositivo con la versión antigua no conoce `weight` ni las fichas. Debe ignorarlos sin perder datos (prueba de compatibilidad).
- **Educamos hoy (fallo encontrado)**: «Media de SA» y «Nota final» toman las dos la Media de la pestaña activa, así que con varias SA todas salen iguales. Se arregla en el paso 6.
- **Cuaderno es pantalla crítica**: la barra y el Resumen tocan `NotebookModuleView.swift` y la barra de pestañas solo en su sección. Hay que medir que cambiar de pestaña no sea más lento.
- **Puertas humanas**: aprobación de maqueta y ticket, permiso para archivos protegidos, QA manual en iPad y Mac con datos inventados, y fusión de la PR.

## 8. Criterios de aceptación

- Con Hockey (60 %; 8, 7 y 7,5 a 33 % cada una) y Ultimate (40 %; 6, 6, 5 y 9 a 30/30/30/10), la nota de evaluación es 6,9 y la explicación lo muestra.
- Si Ultimate no tiene notas, la nota es la de Hockey y se avisa.
- Cambiar una nota en el Resumen la cambia en su bloque y al revés.
- Borrar «1.ª Evaluación» deja Hockey y Ultimate como pestañas sueltas con todas sus notas.
- Las pestañas antiguas siguen funcionando igual mientras no se organicen.
- Exportar a Educamos desde la evaluación: cada «Media de SA» es la media de su bloque y la nota final es la nota de evaluación redondeada.
- Valorar por ficha añade la ficha a todos los marcados sin borrar lo anterior.
- Copiar del trimestre anterior no pisa a nadie por defecto y se puede deshacer.
- Una ficha propia creada en el Mac aparece en el iPad tras sincronizar.
- Cumple HIG en iPad y Mac: VoiceOver, letra grande, 44 pt y modo oscuro.

## 8 bis. Normas HIG que se aplican en código (revisión de la maqueta)

- **Barra de dos niveles**: cada nivel como contenedor con su etiqueta, pestaña activa con el rasgo «seleccionada», 44 pt en iPad, y paso a desplazamiento horizontal o menú con letra muy grande.
- **Cabecera de bloque**: botón con «Hockey, 60 por ciento», valor «desplegado/plegado» y pista.
- **Fila de alumno en el Resumen**: se lee entera («Ana, Hockey 7,5, Ultimate 6,0, nota de evaluación 6,9»).
- **Nota parcial** (bloque sin notas): se marca con «*» además del aviso, y VoiceOver dice «calculada solo con Hockey».
- **Hojas**: `TextField` con etiqueta y teclado decimal para el %, validación de 0 a 100, total leído como un solo elemento y aviso cuando se reparte en proporción. «Igualar» como fila-botón. Nombres completos en los menús («2.ª Evaluación»).
- **Valorar por ficha**: grupo con `Picker` segmentado, fichas en diseño en flujo con rasgo «seleccionada», y la fila entera de cada alumno como interruptor.
- **Fichas propias**: Editar y Borrar también como acciones de VoiceOver, no solo con pulsación larga.
- **Borrar evaluación**: `confirmationDialog` con rol destructivo.
- **Cargando**: el esqueleto se oculta a VoiceOver y se anuncia «Calculando…».
- **Colores**: los del sistema (`.secondary`, `.tint`) y letra nunca menor que `.footnote`. La nota de evaluación se marca con negrita, no solo con color.

## 9. Validación

- `./gradlew :shared:desktopTest` (nota de evaluación, explicación, columnas del Resumen).
- `./gradlew :data:desktopTest` (migración 50 sobre una base con datos, soltar hijas al borrar, fichas).
- XCTest: SyncLAN (peso y fichas), Educamos (media por bloque), Valorar por ficha y Copiar.
- `xcodebuild` Mac e iPad y suite completa de `MiGestorPlannerTests` comparada con el fallo conocido.
- Revisión HIG del código por `ui-reviewer`.

## 10. Entregables

- Código, migración y pruebas en `codex/pestana-evaluacion-pesos`.
- Maqueta aprobada y este ticket en `docs/`.
- CHANGELOG, `docs/ambitos/cuaderno.md` e `informes.md`, y un ADR por el cambio de esquema y la jerarquía de pestañas.
- Ruta del `.xcodeproj` de la carpeta de trabajo para probarlo.
