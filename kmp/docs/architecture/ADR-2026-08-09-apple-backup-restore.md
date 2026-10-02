# ADR-2026-08-09: Validación y restore seguro de backups Apple

## Estado

Aprobado

## Contexto

El checksum y la cabecera SQLite detectan ficheros ausentes o alterados, pero no
demuestran que la base sea internamente consistente ni que sus claves foráneas sean
válidas. La restauración anterior reemplazaba la base y después reconstruía los dos
árboles de documentos; un error intermedio podía dejar datos de generaciones
distintas. Copiar sidecars WAL antiguos junto a la base activa también añade riesgo.

El formato `.migestorbackup` ya contiene copias reales que deben seguir siendo
restaurables. Añadir ahora una contraseña o cifrado obligatorio rompería ese contrato
y exigiría diseñar recuperación y custodia de claves.

## Decisión

- Conservar el formato actual y exigir que el checksum de `database.sqlite` coincida
  también con el manifest, además de validar todas las entradas de `checksums.json`.
- Rechazar rutas que escapen del paquete y enlaces simbólicos no admitidos.
- Abrir SQLite en solo lectura y ejecutar `PRAGMA integrity_check` y
  `PRAGMA foreign_key_check` antes de restaurar.
- Materializar mediante `sqlite3_backup` una base autocontenida en staging. Así se
  integra el estado lógico del WAL del paquete sin instalar sidecars antiguos.
- Preparar también en staging los directorios de evidencias y situaciones. Instalar
  base, retirada de WAL/SHM activos y ambos árboles mediante reemplazos por ruta,
  conservando una copia de rollback. Si cualquier operación falla, revertir en orden
  inverso y no activar `needsRestart`.
- Mantener la copia de emergencia previa como best effort para no impedir recuperar
  una instalación cuya base activa ya sea ilegible.
- Posponer el cifrado de exportaciones hasta disponer de un contenedor autenticado,
  versionado, compatible hacia atrás y con una UX explícita de clave y recuperación.

## Consecuencias

- Una copia con checksum correcto pero corrupción interna o referencias rotas queda
  rechazada antes de tocar los datos activos.
- El conjunto restaurado es coherente frente a fallos de filesystem probados: si el
  último árbol no se instala, se recuperan base y documentos anteriores.
- La operación ocupa temporalmente espacio para una base y dos árboles completos.
- La transacción coordina rutas de filesystem, no el driver SQLDelight ya abierto;
  la app sigue requiriendo reinicio tras el commit, como antes.
- Los backups antiguos compatibles con el manifest/checksums existente conservan su
  formato. Una copia históricamente corrupta puede empezar a rechazarse, que es el
  comportamiento seguro.
- Las exportaciones actuales no están cifradas. Hasta implementar el contenedor
  pendiente, deben guardarse y compartirse mediante almacenamiento protegido.
