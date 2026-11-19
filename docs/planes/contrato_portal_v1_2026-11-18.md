# Contrato del portal del alumnado · v1 (2026-11-18)

Cierra las secciones 4 y 5 del ticket `ticket_portal_alumnado_fase1_2026-11-18.md`. Revisado por `architect`. Si choca con el ticket, manda este contrato.

## Decisiones

- El código de alta usa **PBKDF2-HMAC-SHA256, 600 000 iteraciones** (CommonCrypto en Swift, WebCrypto en la web). Argon2id solo para la contraseña, solo en el navegador.
- Justificación: 50 bits de entropía. Por red, mil millones de intentos en 7 días aciertan con probabilidad < 10⁻⁴. Con una copia robada del servidor, un código concreto pide ~1 200 años de GPU.
- **Reinvitar rota `K_tablon`** (riesgo detectado por `architect`): la app crea una llave nueva, la mete en el `sobreAlta` nuevo y republica el tablón con ella. Se conserva `portalId`. La cuenta anterior sigue entrando hasta que se canjea el código nuevo; al canjear, se sustituye.
- El alta avisa: «No uses tu nombre real». Un usuario con nombre real se puede adivinar con un diccionario contra `usuarioHash`.

## 1. Formatos

- **Código**: 10 caracteres de `23456789ABCDEFGHJKLMNPQRSTUVWXYZ` (sin 0/1/I/O). Cada carácter = `byte & 0x1F` de un byte de `SecRandomCopyBytes`. Se muestra `XXXXX-XXXXX`. Al leer: mayúsculas, quitar `-` y espacios; si no son 10 válidos, error genérico sin llamar al servidor.
- **Enlace**: `https://…/#portal/alta=K7M2XQ9PAB`. La web lo lee y hace `history.replaceState(…, "#portal/alta")`. El código solo vive en memoria.
- **raíz** = PBKDF2-HMAC-SHA256(código ASCII, sal = `entregas-alumnado/v1/portal/alta`, 600000, 32 B).
- HKDF-SHA256 (sal vacía) sobre raíz, info `entregas-alumnado/v1/portal/alta/` + sufijo:
  - `id` → 16 B → `inviteId` (b64u)
  - `prueba` → 32 B → `pruebaAlta` (b64u)
  - `llave` → 32 B → `kAlta`
- `inviteIdHash`, `pruebaHash` = SHA-256 hex del texto b64u (como `fingerprint()` de hoy).
- **Contraseña**: NFKC, mínimo 10 caracteres, lista de prohibidas. raw = Argon2id(m=19456 KiB, t=2, p=1, 32 B, `argon2idAsync`), `sal` 16 B al azar creada por el navegador al canjear.
  - HKDF sobre raw: info `entregas-alumnado/v1/portal/cuenta/auth` → `claveAuth` (b64u, viaja); `…/cuenta/envoltura` → `claveEnvoltura` (no sale). Marca `kdf:1`.
- **usuario**: trim, NFKC, minúsculas, `^[a-z0-9._-]{3,32}$`. `usuarioHash` = SHA-256 hex de `entregas-alumnado/v1/portal/usuario|` + usuario. Solo lo calcula la web.
- **Sal falsa**: primeros 16 B de HMAC-SHA256(`secreto-sal`, usuarioHash). `~/buzon-datos/portal/secreto-sal`: 32 B, permisos 600, se crea la primera vez.
- **Sobre** ChaCha20-Poly1305, nonce al azar 12 B: `{"v":1,"nonce":b64u,"ct":b64u(cifrado‖etiqueta)}`. AAD UTF-8:
  - sobreAlta: `portal-v1|alta|<portalId>`, contiene K_tablon (32 B), cifrado con kAlta.
  - sobreCuenta: `portal-v1|cuenta|<portalId>`, contiene K_tablon, cifrado con claveEnvoltura.
  - tablón: `portal-v1|tablon|<portalId>|<version>`, contiene el JSON del tablón, cifrado con K_tablon.
- **Ids**: `portalId` 16 B b64u (22 car.). `version` = ms epoch, siempre sube. Token de sesión 32 B b64u. Dispositivo 16 B b64u en `localStorage`.
- **Tablón v1**: JSON de la sección 4.4 del ticket. La web ignora claves desconocidas (cabe `notas` de la fase 2). Si `schemaVersion` > 1: «Actualiza». `url` debe ser https y del mismo origen.
- **Sesión en el navegador**: `{token, portalId, kTablon, caduca}`. En `localStorage` solo con «Recordarme en este móvil»; si no, `sessionStorage`. Un 401 lo borra todo.

## 2. API `buzon/portal.php`

Todo POST, JSON, `?accion=`, HTTPS, mismas cabeceras y tope de 1 MiB que `buzon.php`, sin registros. Cerrojo global `portal.lock` para escribir. (D) = acción del docente: `Authorization: Bearer <cuenta>` contra `cuenta.hash`; si falla, 401.

| Acción | Cabecera | Cuerpo | 200 | Errores |
|---|---|---|---|---|
| invitar (D) | Bearer | `{invitaciones:[{portalId,inviteIdHash,pruebaHash,sobreAlta}]}` ≤500 | `{caduca}` (ahora + 7 d) | 400 si falla una (no se escribe ninguna) |
| alta | `X-Portal-Prueba` | `{inviteId}` | `{portalId,sobreAlta}` | 404 `codigo` (inexistente, caducado, usado o bloqueado: igual) |
| canjear | `X-Portal-Prueba`, `X-Portal-Dispositivo` | `{inviteId,usuarioHash,sal,kdf:1,claveAuth,sobreCuenta,recordar}` | `{token,caduca,portalId}` | 404 `codigo`; 409 `usuario` (cuenta 1 intento) |
| sal | — | `{usuarioHash}` | `{sal,kdf:1}` (real o falsa) | 400 |
| entrar | `X-Portal-Dispositivo` | `{usuarioHash,claveAuth,recordar}` | `{token,caduca,portalId,sobreCuenta}` | 401 `credenciales`; 429 `{espera}` + `Retry-After` |
| tablon | `X-Portal-Sesion` | `{}` | `{version,sobre}` (o `0,null`) | 401 `sesion` |
| salir | `X-Portal-Sesion` | `{}` | siempre 200 | — |
| publicar (D) | Bearer | `{tablones:[{portalId,version,sobre}]}` ≤256 KB cada uno | `{resultados:[{portalId,ok,motivo?}]}` | por tablón: `desconocido`, `version` |
| estado (D) | Bearer | `{portalIds:[…]}` ≤500 | `{estados:{id:{cuenta:bool,invitacion:"pendiente"|"caducada"|"ninguna"}}}` | 400 |
| cerrar (D) | Bearer | `{portalIds:[…]}` | `{cerradas}` | 400 |

### Ficheros (`~/buzon-datos/portal/`)

- `invitaciones/<inviteIdHash>.json` = `{portalId,pruebaHash,sobreAlta,caduca,intentos}`
- `cuentas/<usuarioHash>.json` = `{portalId,sal,kdf,verificador,sobreCuenta}`, `verificador = password_hash(claveAuth)`
- `tablones/<portalId>.json` = `{version,sobre}`
- `sesiones/<sha256(token)>.json` = `{portalId,caduca}`
- `portales/<portalId>.json` = `{usuarioHash,inviteIdHash,invitacionCaduca,sesiones[]}` (índice inverso)
- `limites/u-<usuarioHash>.json`, `limites/d-<sha256(dispositivo)>.json` = `{fallos,ultimo,esperaHasta}`

### Reglas

- `alta`/`canjear`: prueba fallida o usuario ocupado → `intentos++`; con 5 se borra la invitación.
- `entrar`: si algún límite tiene espera → 429 sin comprobar. Fallo → fallos++ en los dos límites. Desde 5 fallos, espera 60, 120, 300 s (tope 300). Acierto → los dos a cero; 24 h sin fallos también. Usuario inexistente: `password_verify` contra un hash de relleno.
- Sesión: 12 h, o 30 días con `recordar`. `alta`: 20 fallos/hora por dispositivo → 429 (higiene).
- **Canjear**: borra la invitación, la cuenta anterior de ese portalId (si cambia usuarioHash) y sus sesiones; crea cuenta y sesión. Mismo usuario del mismo portalId → se sobrescribe.
- **Reinvitar** (`invitar` con portalId existente): sustituye la invitación. Conserva cuenta, tablón y portalId. La app rota K_tablon y republica.
- **Cerrar**: borra cuenta, sesiones, invitación, tablón e índice. La app descarta K_tablon.
- **purgar.php**: invitaciones caducadas (deja `invitacionCaduca` en el índice), sesiones caducadas y límites de más de 24 h.

## 3. Estado en la app

- `estado` con todos los portalId de una vez, no por grupo.
- `cuenta` → Activada (nota si además hay invitación pendiente). Sin cuenta: `pendiente` → Pendiente; `caducada` → Código caducado; `ninguna` → Sin cuenta.
- «Sin correo» es solo local. El cruce portalId ↔ alumno solo existe en `alumnos.json`.
- `publicar` en lotes que mezclen grupos cuando sea posible.

## 4. Vectores (`npm run fixture` → `fixtures/portal-v1.json`)

- Se copia a `kmp/iosApp/PlannerTests/Recursos/portal-v1.json` y lo comprueba `scripts/interop_entregas_web/portal/main.swift`, compilado con el `WebPortalCrypto.swift` real.
- Entradas: código `K7M2XQ9PAB`; portalId = b64u(0x00…0x0F) = `AAECAwQFBgcICQoLDA0ODw`; K_tablon = 0x20…0x3F; nonce = 0x01…0x0C; version `1763491200000`; tablón = bytes exactos del JSON de ejemplo.
- Esperados:
  - raíz `5341cfb433a99250df6fe0dca7ac8909fadb5fb7ee014315cac2bbebf75d8f23`
  - inviteId `YTOXSxGhb28QvWd_4KCZrQ`
  - pruebaAlta `3SGev2wOvjQby57XgPETsvYLhhuzkyr65NwuHRR_AWk`
  - kAlta `f995fde3d9ba93d812beba36a7e8e18788a0f18941d1e4fa6fd61b4a766aa893`
- Swift comprueba esos valores y sus hashes; mismo `ct` con nonce fijo en sobreAlta y tablón; abre los sobres de la web; falla si cambian AAD, version o portalId.
- Node comprueba el sentido contrario: abre sobreAlta y tablón cifrados por Swift.
- Solo web (contraseña `contraseña-de-prueba`, sal 0x07×16): raw `ec9174a1c333b266687a170708077aade69c84ac65a56c45d5ed4643ec196d20`, claveAuth `l-PqduVd4Eqp9vXLg4usWSEkLwGip8ORLTBCZkKMy9Y`.

## 5. Riesgos abiertos

- `buzon/.htaccess` solo deja pasar `buzon.php`: hay que permitir `portal.php`. Va en la puerta humana de instalación.
- «Recordarme» deja K_tablon 30 días en `localStorage`. Con notas (fase 2), valorar pedir la contraseña.
- El servidor ve qué portalId se publican juntos. Mitigación parcial: `estado` con todos, `publicar` mezclado.
