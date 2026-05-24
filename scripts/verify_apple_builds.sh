#!/bin/bash
# scripts/verify_apple_builds.sh
#
# Automatización de regeneración de proyecto Xcode y comprobación de build para macOS e iOS.
# Útil para evitar regresiones antes de finalizar cualquier tarea que involucre SwiftUI o el bridge KMP.

set -e

# Configuración de colores
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0;m' # No Color

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_APP_DIR="${PROJECT_ROOT}/kmp/iosApp"

echo -e "${BLUE}===> Iniciando verificación de builds de Apple <===${NC}"
echo -e "Directorio raíz del proyecto: ${PROJECT_ROOT}"

# 1. Regenerar el proyecto con XcodeGen
echo -e "\n${BLUE}[1/3] Regenerando proyecto Xcode con XcodeGen...${NC}"
if [ -d "${IOS_APP_DIR}" ]; then
  cd "${IOS_APP_DIR}"
  if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate
    echo -e "${GREEN}✓ XcodeGen ejecutado correctamente.${NC}"
  else
    echo -e "${YELLOW}⚠ xcodegen no está instalado en la máquina o no está en el PATH.${NC}"
    echo -e "Intentando compilar con el proyecto existente..."
  fi
else
  echo -e "${RED}✗ Error: No se encontró la carpeta kmp/iosApp en ${IOS_APP_DIR}${NC}"
  exit 1
fi

# 2. Compilar Target macOS (Catalyst/Nativo)
echo -e "\n${BLUE}[2/3] Compilando target macOS (MiGestorKMPMac)...${NC}"
cd "${PROJECT_ROOT}"

# Usamos xcodebuild con derivedData en tmp para no ensuciar y evitar conflictos de caché
DERIVED_DATA_MAC="/tmp/MiGestorMacBuildVerify"
rm -rf "${DERIVED_DATA_MAC}"

echo -e "Ejecutando xcodebuild para macOS..."
if xcodebuild -project "${IOS_APP_DIR}/MiGestorKMPiOS.xcodeproj" \
             -scheme MiGestorKMPMac \
             -sdk macosx \
             -configuration Debug \
             -derivedDataPath "${DERIVED_DATA_MAC}" \
             CODE_SIGNING_ALLOWED=NO \
             build > /tmp/mac_build.log 2>&1; then
  echo -e "${GREEN}✓ Compilación de macOS SUCCEEDED.${NC}"
  MAC_STATUS="OK"
else
  echo -e "${RED}✗ Compilación de macOS FAILED. Revisa el log en /tmp/mac_build.log${NC}"
  MAC_STATUS="FAIL"
fi

# 3. Compilar Target iOS Simulator
echo -e "\n${BLUE}[3/3] Compilando target iOS Simulator (MiGestorKMPiOS)...${NC}"
DERIVED_DATA_IOS="/tmp/MiGestorIOSBuildVerify"
rm -rf "${DERIVED_DATA_IOS}"

echo -e "Ejecutando xcodebuild para iOS Simulator..."
if xcodebuild -project "${IOS_APP_DIR}/MiGestorKMPiOS.xcodeproj" \
             -scheme MiGestorKMPiOS \
             -sdk iphonesimulator \
             -destination 'generic/platform=iOS Simulator' \
             -configuration Debug \
             -derivedDataPath "${DERIVED_DATA_IOS}" \
             CODE_SIGNING_ALLOWED=NO \
             build > /tmp/ios_build.log 2>&1; then
  echo -e "${GREEN}✓ Compilación de iOS Simulator SUCCEEDED.${NC}"
  IOS_STATUS="OK"
else
  echo -e "${RED}✗ Compilación de iOS Simulator FAILED. Revisa el log en /tmp/ios_build.log${NC}"
  IOS_STATUS="FAIL"
fi

# Resumen de resultados
echo -e "\n${BLUE}=======================================${NC}"
echo -e "${BLUE}        RESUMEN DE VERIFICACIÓN        ${NC}"
echo -e "${BLUE}=======================================${NC}"

if [ "${MAC_STATUS}" = "OK" ]; then
  echo -e "macOS Native / Catalyst:  ${GREEN}✓ COMPILADO CORRECTAMENTE${NC}"
else
  echo -e "macOS Native / Catalyst:  ${RED}✗ ERROR EN COMPILACIÓN${NC} (Log: /tmp/mac_build.log)"
fi

if [ "${IOS_STATUS}" = "OK" ]; then
  echo -e "iOS Simulator:            ${GREEN}✓ COMPILADO CORRECTAMENTE${NC}"
else
  echo -e "iOS Simulator:            ${RED}✗ ERROR EN COMPILACIÓN${NC} (Log: /tmp/ios_build.log)"
fi

echo -e "${BLUE}=======================================${NC}"

# Retornar código de salida adecuado
if [ "${MAC_STATUS}" = "OK" ] && [ "${IOS_STATUS}" = "OK" ]; then
  echo -e "${GREEN}¡Verificación completada con éxito!${NC}"
  exit 0
else
  echo -e "${RED}Hubo errores en la compilación de alguna plataforma.${NC}"
  exit 1
fi
