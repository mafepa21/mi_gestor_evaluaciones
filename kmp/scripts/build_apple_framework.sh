#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$ROOT_DIR/.gradle}"
mkdir -p "$GRADLE_USER_HOME"

APPLE_PLATFORM="${PLATFORM_NAME:-iphonesimulator}"
APPLE_CONFIG="${CONFIGURATION:-Debug}"
APPLE_ARCHS="${ARCHS:-${NATIVE_ARCH_ACTUAL:-arm64}}"
KMP_MACOS_ARCH_OVERRIDE="${KMP_MACOS_ARCH:-}"
SCRIPT_NAME="$(basename "$0")"

on_exit() {
    local status=$?
    if [ "$status" -ne 0 ]; then
        echo "ERROR: ${SCRIPT_NAME} failed with exit code ${status}." >&2
        echo "ERROR: platform=${APPLE_PLATFORM} configuration=${APPLE_CONFIG} archs=${APPLE_ARCHS}" >&2
        echo "ERROR: JAVA_HOME=${JAVA_HOME:-<unset>} GRADLE_USER_HOME=${GRADLE_USER_HOME}" >&2
        echo "ERROR: Gradle task=${GRADLE_TASK:-<not resolved>}" >&2
    fi
    exit "$status"
}
trap on_exit EXIT

select_java_home() {
    if [ -n "${MIGESTOR_JAVA_HOME:-}" ]; then
        printf '%s\n' "$MIGESTOR_JAVA_HOME"
        return
    fi

    if [ -x "/usr/libexec/java_home" ]; then
        local java17
        java17="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
        if [ -n "$java17" ] && [ -x "$java17/bin/java" ]; then
            printf '%s\n' "$java17"
            return
        fi
    fi

    if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
        printf '%s\n' "$JAVA_HOME"
        return
    fi

    if [ -x "/usr/libexec/java_home" ]; then
        /usr/libexec/java_home 2>/dev/null || true
    fi
}

SELECTED_JAVA_HOME="$(select_java_home)"
if [ -n "$SELECTED_JAVA_HOME" ]; then
    export JAVA_HOME="$SELECTED_JAVA_HOME"
fi
if [ -n "${JAVA_HOME:-}" ] && [ ! -x "$JAVA_HOME/bin/java" ]; then
    echo "error: JAVA_HOME does not point to an executable JDK: $JAVA_HOME" >&2
    exit 1
fi

GRADLE_ARGS=(--no-daemon)
if [ -n "${JAVA_HOME:-}" ]; then
    GRADLE_ARGS+=("-Dorg.gradle.java.home=$JAVA_HOME")
fi

GRADLE_TASK=""
SRC_ARCH=""
GRADLE_TARGET=""

if [[ -n "$KMP_MACOS_ARCH_OVERRIDE" && "$KMP_MACOS_ARCH_OVERRIDE" != "arm64" && "$KMP_MACOS_ARCH_OVERRIDE" != "x64" ]]; then
    echo "Unsupported KMP_MACOS_ARCH: $KMP_MACOS_ARCH_OVERRIDE. Use arm64 or x64."
    exit 1
fi

case "$APPLE_PLATFORM" in
    iphoneos)
        GRADLE_TARGET="IosArm64"
        SRC_ARCH="iosArm64"
        ;;
    iphonesimulator)
        if [[ " $APPLE_ARCHS " == *" arm64 "* ]]; then
            GRADLE_TARGET="IosSimulatorArm64"
            SRC_ARCH="iosSimulatorArm64"
        elif [[ " $APPLE_ARCHS " == *" x86_64 "* ]]; then
            GRADLE_TARGET="IosX64"
            SRC_ARCH="iosX64"
        else
            echo "Unsupported iOS Simulator architecture: $APPLE_ARCHS. Expected arm64 or x86_64."
            exit 1
        fi
        ;;
    macosx)
        if [[ "$KMP_MACOS_ARCH_OVERRIDE" == "x64" ]]; then
            GRADLE_TARGET="MacosX64"
            SRC_ARCH="macosX64"
        elif [[ "$KMP_MACOS_ARCH_OVERRIDE" == "arm64" ]]; then
            GRADLE_TARGET="MacosArm64"
            SRC_ARCH="macosArm64"
        elif [[ " $APPLE_ARCHS " == *" arm64 "* ]]; then
            GRADLE_TARGET="MacosArm64"
            SRC_ARCH="macosArm64"
        elif [[ " $APPLE_ARCHS " == *" x86_64 "* ]]; then
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

JAVA_VERSION="<unset>"
if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
    JAVA_VERSION="$("$JAVA_HOME/bin/java" -version 2>&1 | /usr/bin/sed -n '1p')"
fi
echo "Building KMP Framework for $APPLE_PLATFORM ($APPLE_ARCHS) in $APPLE_CONFIG mode..."
echo "Using Gradle task :data:$GRADLE_TASK with JAVA_HOME=${JAVA_HOME:-<unset>} (${JAVA_VERSION})"
LOCAL_GRADLE_BIN="$(find "$GRADLE_USER_HOME/wrapper/dists/gradle-8.6-all" -path '*/gradle-8.6/bin/gradle' -type f -print -quit 2>/dev/null || true)"
if [ -x "$LOCAL_GRADLE_BIN" ]; then
    "$LOCAL_GRADLE_BIN" "${GRADLE_ARGS[@]}" ":data:$GRADLE_TASK"
else
    ./gradlew "${GRADLE_ARGS[@]}" ":data:$GRADLE_TASK"
fi

if [ ! -d "$FRAMEWORK_SRC" ] || [ ! -f "$FRAMEWORK_SRC/MiGestorKit" ]; then
    echo "error: Gradle completed but the expected framework was not generated: $FRAMEWORK_SRC" >&2
    exit 1
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

if [ ! -f "$OUT_DIR/MiGestorKit.framework/MiGestorKit" ]; then
    echo "error: copied framework is missing its executable: $OUT_DIR/MiGestorKit.framework/MiGestorKit" >&2
    exit 1
fi

echo "SUCCESS: Framework actualizado en $OUT_DIR"
