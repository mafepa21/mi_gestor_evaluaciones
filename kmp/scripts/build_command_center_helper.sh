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

HELPER_APP="$ROOT_DIR/commandCenterHelper/build/compose/binaries/main/app/MiGestorCommandCenter.app"
HELPER_BIN="$ROOT_DIR/commandCenterHelper/build/compose/binaries/main/app/MiGestorCommandCenter.app/Contents/MacOS/MiGestorCommandCenter"
LOCAL_GRADLE_BIN="$(find "$GRADLE_USER_HOME/wrapper/dists/gradle-8.6-all" -path '*/gradle-8.6/bin/gradle' -type f 2>/dev/null | head -n 1 || true)"
BUILD_FAILED=0

echo "Building macOS command center helper..."
if [ -d "$HELPER_APP" ] && [ ! -x "$HELPER_BIN" ]; then
    STALE_APP="${HELPER_APP}.stale"
    rm -rf "$STALE_APP" 2>/dev/null || true
    mv "$HELPER_APP" "$STALE_APP"
fi
if [ -x "$LOCAL_GRADLE_BIN" ]; then
    if ! "$LOCAL_GRADLE_BIN" --no-daemon ":commandCenterHelper:createDistributable"; then
        BUILD_FAILED=1
    fi
else
    if ! ./gradlew --no-daemon ":commandCenterHelper:createDistributable"; then
        BUILD_FAILED=1
    fi
fi

if [ "$BUILD_FAILED" -ne 0 ]; then
    if [ -x "$HELPER_BIN" ]; then
        echo "WARNING: Gradle build failed inside Xcode; reusing prebuilt helper at $HELPER_BIN"
    else
        echo "ERROR: Gradle build failed and no prebuilt helper is available."
        exit 1
    fi
fi

echo "SUCCESS: Command center helper disponible en $HELPER_BIN"
