# ADR-2026-08-09: Copias Apple portables cifradas

## Estado

Aprobado.

## Contexto

Las copias Apple históricas son directorios `.migestorbackup` verificables y
restaurables, pero su exportación deja base de datos y adjuntos sin cifrar. Una copia
portable debe poder viajar entre dispositivos sin depender del Keychain del equipo de
origen, detectar contraseña incorrecta o manipulación y conservar la lectura de copias
anteriores.

El paquete puede alcanzar varios gigabytes. Una solución que lea todo el ZIP o todo el
texto cifrado en memoria no es aceptable para iPhone/iPad, y un KDF rápido como un hash
SHA simple tampoco protege correctamente contraseñas humanas.

## Decisión

- El nuevo formato usa la extensión `.migestorbackupx` y la magia `MGEBKP01`.
- La cabecera binaria canónica v1 declara versión, algoritmos, iteraciones, tamaño de
  bloque, tamaño exacto del ZIP, salt de 16 bytes y prefijo de nonce de 8 bytes. Los
  enteros se codifican en big endian; el byte reservado debe ser cero.
- La clave AES de 256 bits se deriva con PBKDF2-HMAC-SHA256, salt aleatorio y 600.000
  iteraciones. La importación acota las iteraciones aceptadas entre 100.000 y 2.000.000
  para impedir parámetros débiles y trabajo abusivo controlado por el archivo.
- El ZIP se cifra en bloques de 1 MiB con AES-256-GCM. Cada nonce combina un prefijo
  aleatorio de 8 bytes con el índice UInt32 del bloque. El AAD incluye la cabecera
  completa, índice y longitud en claro; cada bloque conserva su tag de 16 bytes.
- Se exige el tamaño total declarado y EOF exacto. Contraseña incorrecta o fallo de tag
  presentan el mismo error y cualquier salida parcial se elimina.
- ZIPFoundation procesa ficheros por buffer. Se rechazan rutas absolutas, `..`, barras
  invertidas, duplicados, enlaces simbólicos y tipos especiales. Se limitan el ZIP en
  claro a 2 GiB, el contenido extraído a 4 GiB, cada entrada a 1 GiB y el paquete a
  10.000 entradas; los tamaños se comprueban antes y después de extraer.
- La importación trabaja en staging, aplica la verificación existente de checksum y
  SQLite y solo entonces mueve el paquete al historial local. Los directorios legacy
  `.migestorbackup` continúan admitidos sin contraseña y pasan por la misma validación.
- La contraseña se solicita al exportar (con confirmación) o importar y se descarta al
  terminar. No se guarda en preferencias ni Keychain. Perderla hace irrecuperable la
  exportación, y la interfaz lo explica antes de crearla.

## Consecuencias

- Las exportaciones nuevas son portables, confidenciales y autenticadas sin una cuenta
  ni secreto ligado a un dispositivo.
- El procesamiento mantiene memoria acotada por el tamaño de bloque, además del coste
  interno del compresor.
- El formato puede evolucionar mediante versión e identificadores de algoritmo, pero
  cambiar KDF, cifrado o layout exige un lector nuevo y otra decisión documentada.
- No existe recuperación de contraseña. La app tampoco puede distinguir de forma
  criptográfica entre contraseña incorrecta y contenido alterado, lo que evita dar un
  oráculo más específico.
- La compatibilidad es de lectura para `.migestorbackup`; la acción normal de exportar
  produce únicamente el formato cifrado nuevo.
