# Ticket L · Portal del alumnado, fase 1: cuenta propia y tablón «Para hacer»

Estado: **borrador, pendiente de APROBADO**. No se toca código hasta entonces.
Maqueta: `docs/maquetas/portal_alumnado_fase1_2026-11-18.html` (estados A a R). Si algo de este ticket contradice la maqueta, manda el ticket.
Revisión de la maqueta (`ui-reviewer`, 2026-11-18): «Aprobable con cambios». Los 12 cambios ya están aplicados.

## 1. Objetivo y contexto

Hoy cada formulario web (autoevaluación, coevaluación, pasaporte, inscripción a torneo) genera un enlace nuevo por alumno que el docente manda por correo. Las entregas ya vuelven solas por el buzón cifrado (ADR-2026-10-24), pero la ida sigue siendo un correo por formulario.

Objetivo: cada alumno tiene **una cuenta propia** (usuario y contraseña) en la web del alumnado y, al entrar, ve un **tablón** con todo lo que tiene pendiente. Publicar un formulario en la app lo añade solo a su tablón. El correo se usa una vez, para mandar el código de alta.

Principio que no se negocia: **el servidor no puede saber quién es cada alumno ni leer su tablón**. Ni nombres, ni clase, ni centro, ni la contraseña.

## 2. Alcance

Dos repositorios:

- **`entregas-alumnado`** (PWA + PHP en alwaysdata):
  - `src/portal/*.mjs` nuevo: pantallas activar, entrar, tablón, menú de cuenta, salir.
  - `src/cripto.mjs`: funciones nuevas de derivación y envoltura de clave (lo existente no cambia).
  - `buzon/portal.php` nuevo, junto a `buzon.php`, mismos datos fuera de la web pública (`~/buzon-datos/portal/`, 700/600).
  - `buzon/purgar.php`: limpiar invitaciones caducadas.
  - `public/sw.js`: añadir los ficheros nuevos a la caché.
  - `src/vista/textos.mjs`: textos del portal en es y en.
- **`mi_gestor_evaluaciones`** (solo Apple):
  - `kmp/iosApp/AppleShared/WebPortal*.swift` nuevo: cliente del portal, almacén local, publicación del tablón.
  - `kmp/iosApp/AppleShared/WebPortalSheet.swift` nuevo: hoja «Portal del alumnado» (estados L a R).
  - `kmp/iosApp/AppleShared/WebSubmissionsWorkspaceView.swift`: punto de entrada «Portal del alumnado».
  - `kmp/iosApp/App/Bridge/KmpBridge+WebForms.swift`: tras publicar un formulario y tras importar entregas, avisar al portal para republicar los tablones afectados (una llamada, sin lógica nueva dentro).
  - `kmp/iosApp/AppleShared/WebSubmissionBulkMailer.swift`: reutilizar para los correos de invitación.

## 3. Fuera de alcance

- «Mis notas» (fase 2, ver sección 11). Materiales y tareas extra (fases 3 y 4).
- Entrar con la cuenta del centro (Google o Microsoft).
- Cambios en KMP (`kmp/shared/`), SQLDelight (`kmp/data/`), `KmpBridge.swift`, `EvaluationDesign.swift` y `kmp/desktopApp/`.
- Cambios en el contrato del manifiesto, el sobre de entrega o `buzon.php`.
- Recuperar contraseña por correo automático. Se recupera con un código nuevo que da el docente.
- Notificaciones push.

## 4. Modelo de datos

### 4.1 Claves (todas creadas en la app)

| Clave | Qué es | Dónde vive | Quién la ve |
|---|---|---|---|
| `portalId` | 128 bits al azar, uno por alumno | app (local) y servidor | servidor: no sabe de quién es |
| `K_tablon` | 256 bits, cifra el tablón del alumno | app (llavero) y, envuelta, en el servidor | solo la app y el navegador del alumno |
| código de alta | 10 caracteres base32 sin ambiguos (`K7M2-XQ9P…`), un uso, 7 días | correo o papel; en el enlace va tras `#` | nadie más |
| contraseña | la elige el alumno | solo en su cabeza | nadie |

### 4.2 Lo que guarda el servidor (`~/buzon-datos/portal/`)

- `invitaciones/<inviteIdHash>.json`: `{ portalId, sobreAlta, caduca, intentos }`.
  `sobreAlta` = `K_tablon` cifrada con una llave derivada del código (Argon2id). El servidor no conoce el código.
- `cuentas/<usuarioHash>.json`: `{ portalId, sal, verificador, sobreCuenta, intentos, bloqueadoHasta }`.
  - `usuarioHash` = SHA-256(usuario en minúsculas). El servidor no guarda el usuario en claro.
  - `verificador` = `password_hash()` de PHP sobre `claveAuth` (ver 4.3). No es la contraseña.
  - `sobreCuenta` = `K_tablon` cifrada con `claveEnvoltura`.
- `tablones/<portalId>.json`: `{ version, sobre }`. Sobre ChaCha20-Poly1305 con `K_tablon`, `portalId` como dato autenticado.
- `sesiones/<tokenHash>.json`: `{ portalId, caduca }`. 12 horas, o 30 días si «Este móvil es mío».

### 4.3 Derivación de la contraseña (en el navegador)

`Argon2id(contraseña, sal)` con `@noble/hashes` (ya es dependencia, no se añade ninguna) → HKDF → dos llaves:
- `claveAuth`: se manda al servidor para entrar. El servidor la comprueba con `password_verify()`.
- `claveEnvoltura`: nunca sale del navegador. Abre `sobreCuenta`.

Para un usuario que no existe, el servidor devuelve una sal falsa estable (HMAC del usuario con un secreto del servidor), así no se puede saber qué usuarios existen.

### 4.4 Contenido del tablón (cifrado)

```json
{
  "schemaVersion": 1,
  "alias": "tigre_azul",
  "actualizado": "2026-11-18T18:40:00Z",
  "pendientes": [
    { "titulo": "Autoevaluación · Bádminton", "contexto": "Educación Física · 2º ESO B",
      "tipo": "autoevaluacion", "plazo": "2026-11-19T23:59:59Z", "url": "https://…/#f=…&a=…&b=…" }
  ],
  "hechos": [ { "titulo": "Inscripción torneo de bádminton" } ]
}
```

- `url` es el enlace personal de siempre, con su alias propio por formulario. El tablón no crea un identificador nuevo dentro de los formularios.
- «Hecho» lo decide la app al importar la entrega. El móvil no marca nada.
- `contexto` lleva materia y grupo: van cifrados, el servidor no los ve.

### 4.5 Lo que guarda la app (local, no viaja por Sync LAN)

- `Documentos/EntregasWeb/portal/alumnos.json`: `studentId → { portalId, estadoConocido, invitadoEl }`. Mismo criterio que `coevaluaciones.json`.
- Llavero: `K_tablon` por alumno y la clave de cuenta del buzón que ya existe.
- Sin tablas nuevas ni migración.

## 5. Plan

1. **Servidor** (`portal.php`): acciones `invitar`, `canjear`, `sal`, `entrar`, `tablon`, `publicar`, `estado`, `cerrar`, `salir`. `invitar`, `publicar`, `estado` y `cerrar` exigen la clave de cuenta del docente (la misma de `buzon.php`). Límite de 5 intentos por invitación. Para entrar, espera creciente (1, 2 y 5 minutos) por usuario y por dispositivo (identificador al azar guardado en el navegador), con la misma respuesta exista o no el usuario: así un compañero no puede dejar a otro fuera mucho rato ni averiguar qué usuarios existen. Sin registros ni IPs. Pruebas en `probar-portal.sh`.
2. **Cripto web**: derivación, envolturas y sobre del tablón en `src/cripto.mjs`, con vectores de prueba compartidos con Swift (como `interop_entregas_web`).
3. **Web**: pantallas A a K de la maqueta. Rutas por fragmento: `#portal/alta=<código>`, `#portal/entrar`, `#portal`. Copia local del tablón solo si «Este móvil es mío».
4. **App · cliente y almacén**: `WebPortalClient` (HTTP), `WebPortalStore` (JSON + llavero), `WebPortalPublisher` (construye y cifra cada tablón con CryptoKit).
5. **App · hoja**: estados L a R. Invitar = crear `portalId`, `K_tablon`, código e invitación en el servidor, y después preparar los correos. Si el servidor falla, no se prepara ningún correo.
6. **App · enganche**: al publicar un formulario y al importar entregas, republicar el tablón de cada alumno afectado que tenga cuenta. En segundo plano y sin bloquear la publicación.
7. **QA** en iPad y Mac con datos inventados, de punta a punta.

## 6. Agentes

| Paso | Agente | Modelo |
|---|---|---|
| Revisión del diseño criptográfico antes de programar | `architect` + `security` | Opus |
| 1, 2, 3 (servidor y web) | `worker` en `entregas-alumnado` | Sonnet |
| 4, 5, 6 (app) | `worker` en `mi_gestor_evaluaciones` | Sonnet |
| Revisión final | `reviewer` y `security` | Sonnet / Opus |
| Antes de fusionar | `janitor` | Sonnet |

Ramas: `codex/portal-alumnado-fase1` en los dos repos.

## 7. Criterios de aceptación

- [ ] Un alumno con el enlace del correo crea cuenta sin escribir el código.
- [ ] El mismo código no sirve una segunda vez, ni pasados 7 días. El mensaje es el mismo para mal escrito, caducado y usado, sin detalle técnico (estado B).
- [ ] Con usuario y contraseña entra desde otro dispositivo y ve el mismo tablón.
- [ ] Tras 5 fallos, la espera crece (estado D). El error no dice si falló el usuario o la contraseña, y es igual para un usuario que no existe.
- [ ] Ningún mensaje al alumnado confirma a un extraño que una cuenta existe o fue cerrada (estado K).
- [ ] Contraseñas con botón «Mostrar», errores ligados al campo (`aria-describedby`, `aria-invalid`).
- [ ] Publicar un formulario en la app lo hace aparecer en el tablón de los alumnos de ese grupo en menos de 1 minuto.
- [ ] Importar una entrega la pasa a «Hecho» en el siguiente refresco del tablón.
- [ ] Cerrar la cuenta desde la app impide entrar y borra la copia local del tablón al detectarlo (estado K).
- [ ] Un código nuevo para un alumno con cuenta le deja crear otra contraseña y conserva su `portalId` y su tablón.
- [ ] La hoja de la app muestra Activada, Pendiente, Código caducado y Sin correo bien en todos los casos, con `Table` y `.contextMenu`, colores semánticos del sistema y un solo botón principal. En «Cerrar cuenta…», Cancelar es la acción por defecto.
- [ ] Sin servidor, la app no prepara correos (estado Q).
- [ ] Privacidad: en `~/buzon-datos/portal/` no aparece ningún nombre, usuario en claro, correo, contraseña, materia ni grupo. Se comprueba con un `grep` de los datos de prueba.
- [ ] El código de alta nunca aparece en una URL antes de `#` ni en el cuerpo de una petición.
- [ ] Accesibilidad de la web: táctiles ≥ 48 px, contraste ≥ 4.5:1, modales con `<dialog>` y `showModal()`, foco visible, `prefers-reduced-motion`.
- [ ] Textos en es y en.
- [ ] Los formularios y entregas que ya funcionan siguen funcionando igual.

## 8. Validación

- `entregas-alumnado`: `npm test` (contrato, vista, buzón) + `probar-portal.sh` nuevo + vectores de interop.
- `mi_gestor_evaluaciones`: `scripts/interop_entregas_web/verificar.sh` ampliado con el tablón; build del esquema iOS y del esquema Mac con `xcodebuild`; tests nuevos de `WebPortalStore` y `WebPortalPublisher` en `PlannerTests`.
- QA manual en iPad y Mac con alumnado inventado: alta, entrada, bloqueo, tablón, sin red, cerrar cuenta, código nuevo.
- Registrar qué se ejecutó y qué no, con el motivo.

## 9. Riesgos y puertas humanas

- **Puerta humana: delegado de protección de datos del centro.** Hay que consultarle antes de usarlo con alumnado real. Incluye la duda de los menores de 14 años.
- **Puerta humana: instalar `portal.php` en alwaysdata** y comprobar que el registro de visitas sigue apagado. Lo hace el docente.
- **Contraseñas débiles**: si alguien robara los datos del servidor podría probar contraseñas sin límite. Se mitiga con Argon2id, mínimo de 10 caracteres y lista de contraseñas prohibidas. Afecta solo al tablón (títulos y plazos), no a notas.
- **Argon2id lento en móviles viejos**: medir en un iPad antiguo antes de fijar parámetros. Objetivo: menos de 2 segundos. Si no se llega, bajar la memoria y documentarlo.
- **Correo compartido en casa**: otra persona podría activar la cuenta. Se ve como «Activada» sin que el alumno lo haya hecho; el docente la cierra y manda otro código.
- **Un solo dispositivo publica**: como en el buzón, el tablón solo se publica desde el equipo que tiene `K_tablon` en el llavero. Cambiar de equipo exige volver a invitar.
- **Metadatos**: el servidor ve cuántos tablones hay, su tamaño y cuándo cambian. No ve de quién son.

## 10. Entregables

- PR en `entregas-alumnado` y PR en `mi_gestor_evaluaciones`, enlazados entre sí.
- ADR nuevo: «Portal del alumnado con cuenta propia».
- Maqueta aprobada y capturas de QA en iPad y Mac.
- CHANGELOG de los dos repos y Trampas del ámbito de entregas web.

## 11. Fase 2 (después del tablón): «Mis notas»

No entra en este ticket. Se deja escrita para que la fase 1 no cierre el camino. Tendrá su propio ticket y su maqueta.

### Qué es

- Cada alumno ve en su portal un apartado «Mis notas», por materia, con la fecha y el nombre de cada actividad.
- Cuando el docente pone o corrige una nota en el Cuaderno, la app sube sola el cuaderno de ese alumno a su tablón.

### Reglas

- **Interruptor por columna «Visible para el alumnado», apagado de entrada.** Sin interruptor encendido, no sube nada.
- **Nunca suben**: columnas de observación, comentarios privados, datos de Inclusión, datos brutos ni columnas ocultas.
- **Espera de 10 minutos** desde el último cambio antes de subir, para poder corregir un error. Un botón «Publicar ahora» se salta la espera.
- **La media es opcional**, por grupo: «Mostrar media» apagado de entrada. Si se muestra, es la misma media del Cuaderno; la web no calcula nada.
- Una nota corregida sustituye a la anterior. No se guarda historial en el servidor.
- Solo publica el equipo que tiene `K_tablon` en el llavero (normalmente el Mac). Lo evaluado en el iPad sube cuando llega al Mac por Sync LAN.

### Datos

- Va dentro del mismo sobre cifrado del tablón (sección 4.4), en un bloque nuevo `notas`: `[{ materia, grupo, actividad, fecha, valor, escala }]`. El servidor sigue sin ver nada.
- Tamaño estimado: unos 10 KB por alumno; 150 alumnos, unos 1,5 MB. Cabe en el plan gratuito de alwaysdata (100 MB, confirmar antes de empezar).
- Decisión pendiente para su ticket: dónde vive el interruptor por columna. Si tiene que viajar entre Mac e iPad, necesita persistencia compartida (posible migración SQLDelight, con `sqldelight-migration`). Si basta con el Mac, un JSON local como `portal/alumnos.json`.

### Riesgos y puertas humanas

- Las notas son más delicadas que las tareas: contraseña mínima de 10 caracteres y lista de contraseñas prohibidas ya desde la fase 1.
- Puerta humana: confirmar con el delegado de protección de datos que se pueden publicar notas parciales por esta vía.
- Puerta humana: avisar a las familias antes de activarlo. Ver las notas cada día cambia cómo las vive el alumnado.
