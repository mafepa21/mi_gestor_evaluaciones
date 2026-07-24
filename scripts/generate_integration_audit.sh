#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-v0.3.0-traceability-baseline}"

# Asegurar que el directorio de salida existe
mkdir -p docs/audit

{
  echo "# Integraciones desde ${BASE}"
  echo
  echo "| Commit | Fecha | Asunto |"
  echo "|---|---|---|"
  git log "${BASE}..HEAD" \
    --first-parent \
    --merges \
    --date=short \
    --pretty=format:'| [%h](../../commit/%H) | %ad | %s |'
} > docs/audit/integraciones-desde-baseline.md

echo "Inventario de integraciones generado con éxito en docs/audit/integraciones-desde-baseline.md"
