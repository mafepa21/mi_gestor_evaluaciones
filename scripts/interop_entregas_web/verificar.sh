#!/usr/bin/env bash
# Verifica que CryptoKit descifra exactamente lo que cifra la PWA.
#
#   scripts/interop_entregas_web/verificar.sh
#
# Compila el servicio real (`WebSubmissionImportService.swift`, el mismo fichero
# que usa la app, sin copias) junto con el comprobador, y lo ejecuta contra el
# fixture que genera el repo `entregas-alumnado` con `npm run fixture`.
#
# Si esto falla, la app no podrá abrir las entregas del alumnado. Ejecútalo
# siempre que se toque el formato del sobre, la derivación de clave o la
# canonicalización del manifiesto.
set -euo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
servicio="$raiz/kmp/iosApp/AppleShared/WebSubmissionImportService.swift"
publicador="$raiz/kmp/iosApp/AppleShared/WebSubmissionPublisher.swift"
comprobador="$raiz/scripts/interop_entregas_web/main.swift"
binario="${TMPDIR:-/tmp}/interop_entregas_web"

if [[ ! -f "$servicio" ]]; then
  echo "No encuentro $servicio" >&2
  exit 1
fi

echo "Compilando…"
swiftc -O "$servicio" "$publicador" "$comprobador" -o "$binario"

echo "Ejecutando…"
"$binario"
