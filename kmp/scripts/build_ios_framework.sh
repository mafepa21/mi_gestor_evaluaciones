#!/usr/bin/env bash
set -euo pipefail

# 1. Intentar encontrar JAVA_HOME si no está puesto (crítico para Xcode)
if [ -z "${JAVA_HOME:-}" ]; then
    if [ -x "/usr/libexec/java_home" ]; then
        export JAVA_HOME=$(/usr/libexec/java_home -v 17 2>/dev/null || /usr/libexec/java_home)
    fi
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# Mantener el wrapper y sus cachés dentro del proyecto evita bloqueos en ~/.gradle
# y hace el build más predecible dentro de Xcode.
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$ROOT_DIR/.gradle}"
mkdir -p "$GRADLE_USER_HOME"

# 2. Detectar arquitectura y configuración desde Xcode
# Si no viene de Xcode (ej. terminal), usamos valores por defecto
KOTLIN_PLATFORM="${PLATFORM_NAME:-iphonesimulator}"
KOTLIN_CONFIG="${CONFIGURATION:-Debug}"

# Mapear plataforma de Xcode a target de Kotlin
if [ "$KOTLIN_PLATFORM" == "iphoneos" ]; then
    GRADLE_TARGET="IosArm64"
    SRC_ARCH="iosArm64"
else
    GRADLE_TARGET="IosSimulatorArm64"
    SRC_ARCH="iosSimulatorArm64"
fi

# Convertir configuración a CamelCase para la tarea de Gradle (Debug -> Debug, Release -> Release)
# Y a minúsculas para la ruta del binario
CONF_LOWER=$(echo "$KOTLIN_CONFIG" | tr '[:upper:]' '[:lower:]')
GRADLE_TASK="link${KOTLIN_CONFIG}Framework${GRADLE_TARGET}"

echo "Building KMP Framework for $KOTLIN_PLATFORM in $KOTLIN_CONFIG mode..."
LOCAL_GRADLE_BIN="$(find "$GRADLE_USER_HOME/wrapper/dists/gradle-8.6-all" -path '*/gradle-8.6/bin/gradle' -type f 2>/dev/null | head -n 1 || true)"
if [ -x "$LOCAL_GRADLE_BIN" ]; then
    echo "Using local Gradle distribution: $LOCAL_GRADLE_BIN"
    "$LOCAL_GRADLE_BIN" --no-daemon ":data:$GRADLE_TASK"
else
    ./gradlew --no-daemon ":data:$GRADLE_TASK"
fi

# 3. Actualizar el Framework en el proyecto iosApp
OUT_DIR="$ROOT_DIR/iosApp/Frameworks"
FRAMEWORK_SRC="$ROOT_DIR/data/build/bin/$SRC_ARCH/${CONF_LOWER}Framework/MiGestorKit.framework"

rm -rf "$OUT_DIR/MiGestorKit.framework"
mkdir -p "$OUT_DIR"
cp -R "$FRAMEWORK_SRC" "$OUT_DIR/"

echo "SUCCESS: Framework actualizado en $OUT_DIR"
