#!/usr/bin/env bash
set -euo pipefail

if [ -z "${JAVA_HOME:-}" ]; then
    if [ -x "/usr/libexec/java_home" ]; then
        export JAVA_HOME=$(/usr/libexec/java_home -v 17 2>/dev/null || /usr/libexec/java_home)
    fi
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$ROOT_DIR/.gradle}"
mkdir -p "$GRADLE_USER_HOME"

APPLE_PLATFORM="${PLATFORM_NAME:-iphonesimulator}"
APPLE_CONFIG="${CONFIGURATION:-Debug}"
APPLE_ARCHS="${ARCHS:-${NATIVE_ARCH_ACTUAL:-arm64}}"

case "$APPLE_PLATFORM" in
    iphoneos)
        GRADLE_TARGET="IosArm64"
        SRC_ARCH="iosArm64"
        ;;
    iphonesimulator)
        GRADLE_TARGET="IosSimulatorArm64"
        SRC_ARCH="iosSimulatorArm64"
        ;;
    macosx)
        if [[ "$APPLE_ARCHS" == *"x86_64"* ]]; then
            GRADLE_TARGET="MacosX64"
            SRC_ARCH="macosX64"
        else
            GRADLE_TARGET="MacosArm64"
            SRC_ARCH="macosArm64"
        fi
        ;;
    *)
        echo "Unsupported Apple platform: $APPLE_PLATFORM"
        exit 1
        ;;
esac

CONF_LOWER=$(echo "$APPLE_CONFIG" | tr '[:upper:]' '[:lower:]')
GRADLE_TASK="link${APPLE_CONFIG}Framework${GRADLE_TARGET}"
if [ "$APPLE_PLATFORM" = "macosx" ]; then
    OUT_DIR="$ROOT_DIR/iosApp/Frameworks/macos"
else
    OUT_DIR="$ROOT_DIR/iosApp/Frameworks/ios"
fi
FRAMEWORK_SRC="$ROOT_DIR/data/build/bin/$SRC_ARCH/${CONF_LOWER}Framework/MiGestorKit.framework"

echo "Building KMP Framework for $APPLE_PLATFORM ($APPLE_ARCHS) in $APPLE_CONFIG mode..."
LOCAL_GRADLE_BIN="$(find "$GRADLE_USER_HOME/wrapper/dists/gradle-8.6-all" -path '*/gradle-8.6/bin/gradle' -type f 2>/dev/null | head -n 1 || true)"
if [ -x "$LOCAL_GRADLE_BIN" ]; then
    "$LOCAL_GRADLE_BIN" --no-daemon ":data:$GRADLE_TASK"
else
    ./gradlew --no-daemon ":data:$GRADLE_TASK"
fi

rm -rf "$OUT_DIR/MiGestorKit.framework"
mkdir -p "$OUT_DIR"
cp -R "$FRAMEWORK_SRC" "$OUT_DIR/"

if [ "$APPLE_PLATFORM" = "macosx" ]; then
    echo "Reemplazando enlaces simbólicos de Headers y Modules en el framework de macOS para compatibilidad con Swift Explicit Modules..."
    FW_DIR="$OUT_DIR/MiGestorKit.framework"
    if [ -d "$FW_DIR/Versions/A" ]; then
        # Reemplazamos Headers y Modules en la raíz por directorios físicos reales copiados de Versions/A
        rm -f "$FW_DIR/Headers" "$FW_DIR/Modules"
        cp -R "$FW_DIR/Versions/A/Headers" "$FW_DIR/Headers"
        cp -R "$FW_DIR/Versions/A/Modules" "$FW_DIR/Modules"
    fi
fi

echo "SUCCESS: Framework actualizado en $OUT_DIR"

