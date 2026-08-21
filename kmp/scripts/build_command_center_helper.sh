#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$ROOT_DIR/.gradle}"
mkdir -p "$GRADLE_USER_HOME"

SCRIPT_NAME="$(basename "$0")"
GRADLE_TASK=":commandCenterHelper:createDistributable"

on_exit() {
    local status=$?
    if [ "$status" -ne 0 ]; then
        echo "ERROR: ${SCRIPT_NAME} failed with exit code ${status}." >&2
        echo "ERROR: JAVA_HOME=${JAVA_HOME:-<unset>} GRADLE_USER_HOME=${GRADLE_USER_HOME}" >&2
        echo "ERROR: Gradle task=${GRADLE_TASK}" >&2
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

HELPER_APP="$ROOT_DIR/commandCenterHelper/build/compose/binaries/main/app/MiGestorCommandCenter.app"
HELPER_BIN="$HELPER_APP/Contents/MacOS/MiGestorCommandCenter"
LOCAL_GRADLE_BIN="$(find "$GRADLE_USER_HOME/wrapper/dists/gradle-8.6-all" -path '*/gradle-8.6/bin/gradle' -type f -print -quit 2>/dev/null || true)"
BUILD_LOG="$(mktemp "${TMPDIR:-/tmp}/migestor-command-center-helper.XXXXXX")"
STALE_APP=""

echo "Building macOS command center helper..."
echo "Using Gradle task $GRADLE_TASK with JAVA_HOME=${JAVA_HOME:-<unset>}"
if [ -e "$HELPER_APP" ]; then
    STALE_APP="${HELPER_APP}.stale"
    rm -rf "$STALE_APP" 2>/dev/null || true
    mv "$HELPER_APP" "$STALE_APP"
fi

set +e
if [ -x "$LOCAL_GRADLE_BIN" ]; then
    "$LOCAL_GRADLE_BIN" "${GRADLE_ARGS[@]}" "$GRADLE_TASK" 2>&1 | tee "$BUILD_LOG"
else
    ./gradlew "${GRADLE_ARGS[@]}" "$GRADLE_TASK" 2>&1 | tee "$BUILD_LOG"
fi
BUILD_STATUS=${PIPESTATUS[0]}
set -e

if [ "$BUILD_STATUS" -ne 0 ]; then
    # jpackage may finish the app image and then fail its ad-hoc codesign step
    # when macOS has attached Finder/File Provider metadata to the .app folder.
    # Only this known metadata failure is recoverable: other Gradle failures
    # must remain visible instead of silently reusing an old helper.
    if grep -Eiq "FinderInfo|Finder information|resource fork|similar detritus not allowed" "$BUILD_LOG" \
        && [ -d "$HELPER_APP" ] && [ -x "$HELPER_BIN" ] \
        && command -v xattr >/dev/null 2>&1 && command -v codesign >/dev/null 2>&1; then
        echo "WARNING: jpackage created the helper but codesign rejected bundle metadata; repairing the app image..."
        xattr -cr "$HELPER_APP" 2>/dev/null || true
        sign_output=""
        verify_output=""
        if sign_output="$(codesign --deep --force --sign - "$HELPER_APP" 2>&1)" \
            && verify_output="$(codesign --verify --deep --strict "$HELPER_APP" 2>&1)"; then
            xattr -cr "$HELPER_APP" 2>/dev/null || true
            echo "SUCCESS: Repaired helper app image after jpackage codesign metadata failure."
            BUILD_STATUS=0
        else
            echo "error: codesign repair or verification failed." >&2
            printf '%s\n' "$sign_output" "$verify_output" >&2
        fi
    fi
fi

if [ "$BUILD_STATUS" -ne 0 ]; then
    echo "error: Gradle task $GRADLE_TASK failed. Full output was saved to $BUILD_LOG" >&2
    exit "$BUILD_STATUS"
fi

if [ ! -d "$HELPER_APP" ] || [ ! -x "$HELPER_BIN" ]; then
    echo "error: Gradle completed but the expected helper was not generated: $HELPER_BIN" >&2
    echo "error: Full Gradle output was saved to $BUILD_LOG" >&2
    exit 1
fi

if command -v codesign >/dev/null 2>&1; then
    if ! codesign --verify --deep --strict "$HELPER_APP"; then
        echo "error: generated helper failed codesign verification: $HELPER_APP" >&2
        exit 1
    fi
fi

if [ -n "$STALE_APP" ]; then
    rm -rf "$STALE_APP" 2>/dev/null || true
fi

echo "SUCCESS: Command center helper disponible en $HELPER_BIN"
