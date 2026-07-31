# Probar las entregas web en Xcode

Guía para ver funcionando el importador de entregas del alumnado sin esperar a que
exista la parte que publica formularios.

**Todo lo que se describe aquí es `#if DEBUG`.** No existe en una compilación de
release, y se borra en cuanto la app sepa publicar formularios de verdad.

## Por qué hace falta un banco de pruebas

El circuito real tiene dos mitades:

1. **Publicar** un formulario: generar el par de claves, registrar el formulario,
   crear un alias por alumno y exportar el manifiesto. **Esto todavía no existe.**
2. **Importar** las entregas: descifrar, validar, previsualizar y escribir. **Esto
   es lo que está hecho.**

Sin la primera mitad no hay ningún formulario registrado, ninguna clave en el
llavero ni ninguna fila de alias, así que la segunda no se puede ejercitar. El
banco de pruebas monta ese estado a mano.

## Aviso importante antes de empezar

**Todas las compilaciones de macOS comparten la misma base de datos**, en
`~/Library/Application Support/MiGestor/desktop_mi_gestor_kmp.db`. No hay una base
por rama.

Esta rama añade las migraciones 39 y 40, así que la primera vez que ejecutes esta
compilación **tu base real sube a la versión 41**. A partir de ahí, una compilación
de `main` o de `develop` (que van por la 39) **ya no puede abrirla** y arranca con
una base vacía, avisando con este diálogo:

> No se pudo abrir la base de datos
> Motivo: Database version 41 newer than config version 39

No se pierde nada: la app guarda la anterior como
`desktop_mi_gestor_kmp.db.backup_<timestamp>`. Pero mientras esta rama no esté
fusionada, **usa solo la compilación de esta rama** para el trabajo diario, o
prueba en un usuario o simulador aparte.

Para saber en qué versión está cada fichero:

```bash
cd ~/Library/Application\ Support/MiGestor/
for f in desktop_mi_gestor_kmp.db*; do
  echo "$f -> $(sqlite3 "$f" 'PRAGMA user_version;' 2>/dev/null)"
done
```

## Abre el proyecto correcto

El error de arriba también aparece si abres el proyecto del checkout principal en
vez del de esta rama. Comprueba que abres **el del worktree**, no
`~/Projects/mi_gestor_evaluaciones/kmp/iosApp/`:

```bash
open <ruta-del-worktree>/kmp/iosApp/MiGestorKMPiOS.xcodeproj
```

Si abres el equivocado, no verás "Entregas web" en la barra lateral por una razón
simple: **ese código no está en esa rama**.

## Antes de empezar

Necesitas **un grupo con al menos un alumno o alumna**. Si la base está vacía, la
preparación te lo dirá en vez de fallar en silencio.

## Pasos

1. Abre el proyecto:

```bash
cd kmp/iosApp && xcodegen generate && open MiGestorKMPiOS.xcodeproj
```

2. Compila y ejecuta el esquema **MiGestorKMPMac** (o el de iOS, funciona igual).

3. Ve a **Ajustes → Diagnóstico**. Arriba verás "Entregas del alumnado (banco de
   pruebas)".

4. Pulsa **1. Preparar la prueba**. Deja escrito en pantalla lo que ha hecho:

   - Crea una columna "Entregas web (prueba)" en el primer grupo, con una plantilla
     de cinco ítems, uno de cada tipo real (`CHECK`, `TEXT`, `NUMBER`, `SCALE_1_4`,
     `CHOICE`).
   - Registra el formulario del fixture apuntando a esa columna.
   - Guarda la clave privada del fixture en el llavero.
   - Mapea los `webItemId` a los ítems recién creados.
   - Asigna el código del fixture al primer alumno del grupo.
   - Escribe el sobre de prueba como `prueba-entrega.mgsub` y **te dice la ruta**.

   Se puede pulsar varias veces sin ensuciar el Cuaderno: la columna tiene un
   identificador estable por formulario.

5. Pulsa **Importar entregas del alumnado** y elige el `prueba-entrega.mgsub` de
   la ruta que te dio el paso anterior.

6. Revisa la hoja de previsualización. Deberías ver:

   - Una entrega en **Listas para importar**, con el nombre del alumno resuelto y
     **5/5** apartados.
   - La tarjeta "Qué se va a escribir", avisando de que la nota la calcula la app.

7. Pulsa **Importar**. Abajo aparece "Se ha importado 1 entrega".

8. Ve al **Cuaderno** de ese grupo y busca la columna "Entregas web (prueba)". La
   celda de ese alumno debe mostrar su estado de completado.

## Lo que conviene comprobar

| Qué probar | Cómo | Qué debe pasar |
|---|---|---|
| Idempotencia | Importa **el mismo fichero otra vez** | Sale en **Ya importadas**, no duplica |
| Fichero manipulado | Abre el `.mgsub` en un editor y cambia una letra de `encryptedPayload` | Sale en **No se pueden importar**, con el motivo del descifrado |
| Entrega de otro formulario | Cambia `formInstanceId` dentro del `.mgsub` | Rechazada, diciendo que es de otro formulario |
| Código sin asignar | Cambia `participantAlias` por 22 caracteres cualesquiera | **No se descarta**: aparece con un selector para asignarla a mano |
| Asignación manual | Asigna esa entrega a otro alumno y pulsa Importar | Se escribe en la celda de quien elijas |
| Nada seleccionado | Cancela el selector de ficheros | No pasa nada, sin error |

El selector oculta a quien ya esté asignado a otra entrega del mismo lote: la base
de datos no admite dos entregas de la misma persona en un formulario.

## Si algo va mal

- **"Crea primero un grupo con alumnado"**: la base está vacía. Crea un grupo y
  algún alumno.
- **"No se pudo guardar la clave en el llavero"**: en macOS puede pedir permiso la
  primera vez. Acepta y vuelve a preparar.
- **El formulario no se pudo volver a leer**: la migración 39 no se ha aplicado.
  Borra la app del simulador o el contenedor de datos y vuelve a ejecutar.
- **El selector no deja elegir el fichero**: comprueba que la extensión es
  `.mgsub`. El importador solo acepta ese tipo, a propósito, para no ofrecer
  cualquier `.json` del dispositivo.

## Probar también con una entrega real del alumnado

El fixture tiene cinco ítems. Para probar con el pasaporte completo de SA 2 (53
respuestas), en el repo `entregas-alumnado`:

```bash
npm run claves && npm run manifiesto:sa2 && npm run dev
```

Abre el enlace personal que da `scripts/generar-enlaces.mjs`, rellena y entrega. El
`.mgsub` que descarga el navegador lo abre `scripts/abrir-entrega.mjs`. Para que lo
acepte la app haría falta registrar ese formulario, que es justo lo que hará la
parte de publicación.

## Verificación automática

Esto no necesita Xcode y conviene ejecutarlo si se toca el formato del sobre, la
derivación de clave o la canonicalización del manifiesto:

```bash
scripts/interop_entregas_web/verificar.sh
```

Compila el servicio real y comprueba contra el fixture que CryptoKit descifra
exactamente lo que cifra el navegador. 50 comprobaciones.
