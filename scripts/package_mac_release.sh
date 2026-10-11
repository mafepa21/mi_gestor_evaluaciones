#!/bin/bash
# scripts/package_mac_release.sh
#
# Compila «Cuaderno Vivo» para Mac (Release, Apple Silicon), la firma en modo
# ad hoc (sin cuenta de pago de Apple) y crea el .dmg listo para subir a GitHub.
#
# Uso: scripts/package_mac_release.sh
# Resultado: build/release-mac/CuadernoVivo-<versión>.dmg y su .sha256
#
# La firma ad hoc permite que la app arranque en Macs con chip Apple, pero no
# está notarizada: la primera vez hay que abrirla desde
# Ajustes > Privacidad y seguridad > «Abrir igualmente».

set -euo pipefail

APP_NAME="Cuaderno Vivo"
DMG_BASENAME="CuadernoVivo"
SCHEME="MiGestorKMPMac"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_APP_DIR="${PROJECT_ROOT}/kmp/iosApp"
OUT_DIR="${PROJECT_ROOT}/build/release-mac"
DERIVED_DATA="${OUT_DIR}/DerivedData"
STAGING="${OUT_DIR}/dmg-staging"
BUILD_LOG="${OUT_DIR}/xcodebuild.log"

VERSION="$(awk '/MiGestorKMPMac:/{t=1} t && /MARKETING_VERSION:/{gsub(/"/,"",$2); print $2; exit}' "${IOS_APP_DIR}/project.yml")"
if [ -z "${VERSION}" ]; then
  echo "✗ No se encontró MARKETING_VERSION del target ${SCHEME} en project.yml" >&2
  exit 1
fi

DMG_PATH="${OUT_DIR}/${DMG_BASENAME}-${VERSION}.dmg"
APP_PATH="${DERIVED_DATA}/Build/Products/Release/${APP_NAME}.app"

echo "===> Empaquetando ${APP_NAME} ${VERSION}"
rm -rf "${STAGING}" "${DMG_PATH}" "${DMG_PATH}.sha256"
mkdir -p "${OUT_DIR}"

# 1. Compilar en Release solo para arm64: MiGestorKit.framework no trae x86_64.
#    Firma ad hoc («-») sin equipo para no depender de perfiles de aprovisionamiento.
echo "[1/4] Compilando (log: ${BUILD_LOG})..."
if ! xcodebuild build \
  -project "${IOS_APP_DIR}/MiGestorKMPiOS.xcodeproj" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "${DERIVED_DATA}" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  > "${BUILD_LOG}" 2>&1; then
  grep -E " error:" "${BUILD_LOG}" | sort -u | head -20 >&2 || true
  echo "✗ La compilación falló. Revisa ${BUILD_LOG}" >&2
  exit 1
fi

# 2. Firmar de dentro hacia fuera: primero el ayudante Command Center embebido
#    (Compose Desktop, con su propio runtime de Java) y después la app principal.
echo "[2/4] Firmando en modo ad hoc..."
HELPER_PATH="${APP_PATH}/Contents/Resources/MiGestorCommandCenter.app"
if [ -d "${HELPER_PATH}" ]; then
  codesign --force --deep --sign - "${HELPER_PATH}"
fi
codesign --force --sign - "${APP_PATH}"
codesign --verify --deep --strict "${APP_PATH}"

# 3. Carpeta del .dmg: la app y un acceso a Aplicaciones para arrastrarla.
echo "[3/4] Preparando el contenido del .dmg..."
mkdir -p "${STAGING}"
ditto "${APP_PATH}" "${STAGING}/${APP_NAME}.app"
ln -s /Applications "${STAGING}/Aplicaciones"

# 4. Crear el .dmg comprimido y su huella SHA-256 para comprobar la descarga.
echo "[4/4] Creando ${DMG_PATH}..."
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGING}" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "${DMG_PATH}" >/dev/null
(cd "${OUT_DIR}" && shasum -a 256 "$(basename "${DMG_PATH}")" > "$(basename "${DMG_PATH}").sha256")
rm -rf "${STAGING}"

echo "✓ Listo: ${DMG_PATH} ($(du -h "${DMG_PATH}" | cut -f1))"
