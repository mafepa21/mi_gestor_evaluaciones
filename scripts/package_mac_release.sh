#!/bin/bash
# scripts/package_mac_release.sh
#
# Compila «Cuaderno Vivo» para Mac (Release, Apple Silicon), la firma en modo
# ad hoc (sin cuenta de pago de Apple), crea el instalador .pkg y lo mete en un
# .dmg listo para subir a GitHub.
#
# Uso: scripts/package_mac_release.sh
# Resultado: build/release-mac/CuadernoVivo-<versión>.dmg y su .sha256
#
# El .pkg abre el asistente de instalación de macOS (scripts/mac-installer/):
# cierra la app y su ayudante si están abiertos, borra la versión instalada y
# deja la nueva en /Applications. No toca los datos ni las copias.
#
# Ni la app ni el .pkg están notarizados: la primera vez macOS lo bloquea y hay
# que abrirlo desde Ajustes > Privacidad y seguridad > «Abrir igualmente».

set -euo pipefail

APP_NAME="Cuaderno Vivo"
DMG_BASENAME="CuadernoVivo"
SCHEME="MiGestorKMPMac"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_APP_DIR="${PROJECT_ROOT}/kmp/iosApp"
OUT_DIR="${PROJECT_ROOT}/build/release-mac"
DERIVED_DATA="${OUT_DIR}/DerivedData"
STAGING="${OUT_DIR}/dmg-staging"
PKG_WORK="${OUT_DIR}/pkg-work"
INSTALLER_DIR="${PROJECT_ROOT}/scripts/mac-installer"
BUNDLE_ID="com.migestor.mac"
BUILD_LOG="${OUT_DIR}/xcodebuild.log"

VERSION="$(awk '/MiGestorKMPMac:/{t=1} t && /MARKETING_VERSION:/{gsub(/"/,"",$2); print $2; exit}' "${IOS_APP_DIR}/project.yml")"
if [ -z "${VERSION}" ]; then
  echo "✗ No se encontró MARKETING_VERSION del target ${SCHEME} en project.yml" >&2
  exit 1
fi

DMG_PATH="${OUT_DIR}/${DMG_BASENAME}-${VERSION}.dmg"
PKG_NAME="Instalar ${APP_NAME}.pkg"
APP_PATH="${DERIVED_DATA}/Build/Products/Release/${APP_NAME}.app"

echo "===> Empaquetando ${APP_NAME} ${VERSION}"
rm -rf "${STAGING}" "${PKG_WORK}" "${DMG_PATH}" "${DMG_PATH}.sha256"
mkdir -p "${OUT_DIR}"

# 1. Compilar en Release solo para arm64: MiGestorKit.framework no trae x86_64.
#    Firma ad hoc («-») sin equipo para no depender de perfiles de aprovisionamiento.
echo "[1/5] Compilando (log: ${BUILD_LOG})..."
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
echo "[2/5] Firmando en modo ad hoc..."
HELPER_PATH="${APP_PATH}/Contents/Resources/MiGestorCommandCenter.app"
if [ -d "${HELPER_PATH}" ]; then
  codesign --force --deep --sign - "${HELPER_PATH}"
fi
codesign --force --sign - "${APP_PATH}"
codesign --verify --deep --strict "${APP_PATH}"

# 3. Instalador .pkg: un componente con la app en /Applications y el
#    script de preinstalación, envuelto en un producto con asistente en español.
echo "[3/5] Creando el instalador .pkg..."
mkdir -p "${PKG_WORK}/root/Applications" "${PKG_WORK}/resources"
ditto --norsrc --noextattr --noqtn "${APP_PATH}" "${PKG_WORK}/root/Applications/${APP_NAME}.app"
# Fuera los atributos extendidos que se puedan quitar (cuarentena, etc.).
# pkgbuild guarda los que quedan (com.apple.provenance, protegido por el
# sistema) como entradas «._*», pero Installer los repone como atributos, no
# como archivos sueltos: comprobado al instalar un .pkg de prueba.
xattr -cr "${PKG_WORK}/root" 2>/dev/null || true

# - No reubicable: si el usuario movió la app, Installer la buscaría allí y
#   dejaría dos copias. Siempre va a /Applications.
# - Sin comprobar versión: la preinstalación ya ha borrado la app; si Installer
#   se saltara la copia por haber una versión igual o más nueva, el Mac se
#   quedaría sin app. Este instalador siempre deja su versión.
pkgbuild --analyze --root "${PKG_WORK}/root" "${PKG_WORK}/component.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "${PKG_WORK}/component.plist"
plutil -replace 0.BundleIsVersionChecked -bool NO "${PKG_WORK}/component.plist"
plutil -replace 0.BundleOverwriteAction -string upgrade "${PKG_WORK}/component.plist"

COPYFILE_DISABLE=1 pkgbuild \
  --root "${PKG_WORK}/root" \
  --component-plist "${PKG_WORK}/component.plist" \
  --scripts "${INSTALLER_DIR}/scripts" \
  --identifier "${BUNDLE_ID}" \
  --version "${VERSION}" \
  --install-location / \
  "${PKG_WORK}/CuadernoVivo-app.pkg" >/dev/null

# Icono de la app abajo a la izquierda del asistente, como en los instaladores
# de Apple. Sale del propio .icns compilado, así siempre coincide.
sips -s format png -Z 256 "${APP_PATH}/Contents/Resources/AppIcon.icns" \
  --out "${PKG_WORK}/resources/background.png" >/dev/null

for page in welcome conclusion; do
  sed "s/@VERSION@/${VERSION}/g" "${INSTALLER_DIR}/resources/${page}.html" > "${PKG_WORK}/resources/${page}.html"
done
sed -e "s/@VERSION@/${VERSION}/g" -e "s/@PKG@/CuadernoVivo-app.pkg/g" \
  "${INSTALLER_DIR}/distribution.xml" > "${PKG_WORK}/distribution.xml"

mkdir -p "${STAGING}"
productbuild \
  --distribution "${PKG_WORK}/distribution.xml" \
  --resources "${PKG_WORK}/resources" \
  --package-path "${PKG_WORK}" \
  "${STAGING}/${PKG_NAME}" >/dev/null

# 4. El .dmg lleva solo el instalador: ni la app suelta ni el acceso a
#    Aplicaciones, para que nadie la arrastre y cree una segunda copia.
echo "[4/5] Comprobando el instalador..."
PAYLOAD="$(pkgutil --payload-files "${PKG_WORK}/CuadernoVivo-app.pkg")"
grep -q "Applications/${APP_NAME}.app/Contents/MacOS/" <<< "${PAYLOAD}" \
  || { echo "✗ El .pkg no contiene la app" >&2; exit 1; }

pkgutil --expand "${STAGING}/${PKG_NAME}" "${PKG_WORK}/expanded"
[ -x "${PKG_WORK}/expanded/CuadernoVivo-app.pkg/Scripts/preinstall" ] \
  || { echo "✗ El .pkg no lleva el script de preinstalación" >&2; exit 1; }

# 5. Crear el .dmg comprimido y su huella SHA-256 para comprobar la descarga.
echo "[5/5] Creando ${DMG_PATH}..."
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGING}" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "${DMG_PATH}" >/dev/null
(cd "${OUT_DIR}" && shasum -a 256 "$(basename "${DMG_PATH}")" > "$(basename "${DMG_PATH}").sha256")
rm -rf "${STAGING}" "${PKG_WORK}"

echo "✓ Listo: ${DMG_PATH} ($(du -h "${DMG_PATH}" | cut -f1))"
