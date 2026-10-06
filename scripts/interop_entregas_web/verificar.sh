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

# Prueba cruzada con la web: la función JS que decodifica `m` tiene que leer los
# enlaces que acaba de generar Swift y la firma tiene que verificar con la
# implementación de la PWA. Hace falta el repo `entregas-alumnado` con
# `src/enlace.mjs`; se puede indicar con ENTREGAS_WEB_REPO.
web="${ENTREGAS_WEB_REPO:-$raiz/../entregas-alumnado}"
if command -v node >/dev/null 2>&1 && [[ -f "$web/src/enlace.mjs" ]]; then
  echo
  echo "Prueba cruzada con la web ($web)…"
  ENLACES_SWIFT="/tmp/enlaces-publicados-por-swift.txt" ENLACE_PEER_SWIFT="/tmp/enlace-peer-publicado-por-swift.txt" \
  node --input-type=module -e '
    import { readFileSync } from "node:fs";
    import { pathToFileURL } from "node:url";
    const web = process.argv[1];
    const { decodificarManifiestoM } = await import(pathToFileURL(`${web}/src/enlace.mjs`));
    const { verificarManifiesto } = await import(pathToFileURL(`${web}/src/cripto.mjs`));
    let fallos = 0;
    const enlaces = [
      ...readFileSync(process.env.ENLACES_SWIFT, "utf8").split("\n"),
      ...readFileSync(process.env.ENLACE_PEER_SWIFT, "utf8").split("\n"),
    ].filter(Boolean);
    for (const url of enlaces) {
      const p = new URLSearchParams(new URL(url).hash.slice(1));
      const m = await decodificarManifiestoM(p.get("m"));
      const ok = m.formInstanceId === p.get("f") && verificarManifiesto(m).ok;
      console.log(`  ${ok ? "ok   " : "FALLA"} la web decodifica y verifica el enlace (${url.length} caracteres)`);
      if (!ok) fallos++;
    }
    process.exit(fallos ? 1 : 0);
  ' "$web"
else
  echo
  echo "Prueba cruzada con la web OMITIDA: falta node o $web/src/enlace.mjs (usa ENTREGAS_WEB_REPO)."
fi
