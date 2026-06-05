#!/bin/bash
# Checks that active app manifests agree on the release version.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

usage() {
  cat <<'EOF'
Usage:
  scripts/check_version_consistency.sh [0.3.0-alpha.1]

Checks active manifests without editing them:
- kmp/iosApp/project.yml MARKETING_VERSION
- kmp/androidApp/build.gradle.kts versionName
- pubspec.yaml version base

Pre-release suffixes are accepted for the target version, but active manifests
are compared against the base SemVer number because Apple/Android manifests may
carry only X.Y.Z while the Git tag carries X.Y.Z-alpha.N.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

TARGET_VERSION="${1:-}"
TARGET_BASE=""

if [ -n "$TARGET_VERSION" ]; then
  if ! [[ "$TARGET_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$ ]]; then
    echo "Invalid target version: ${TARGET_VERSION}"
    echo "Expected examples: 0.3.0, 0.3.0-alpha.1, 0.4.0-beta.1, 1.0.0-rc.1"
    exit 1
  fi
  TARGET_BASE="${TARGET_VERSION%%-*}"
fi

failures=()
versions=()

add_version() {
  local label="$1"
  local version="$2"

  if [ -z "$version" ]; then
    failures+=("${label}: missing version")
    return
  fi

  if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    failures+=("${label}: invalid version '${version}'")
    return
  fi

  versions+=("${label}=${version}")

  if [ -n "$TARGET_BASE" ] && [ "$version" != "$TARGET_BASE" ]; then
    failures+=("${label}: expected ${TARGET_BASE}, found ${version}")
  fi
}

if [ -f kmp/iosApp/project.yml ]; then
  ios_versions="$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' kmp/iosApp/project.yml | sort -u)"
  ios_version_count="$(printf '%s\n' "$ios_versions" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "$ios_version_count" -eq 0 ]; then
    failures+=("kmp/iosApp/project.yml: MARKETING_VERSION not found")
  elif [ "$ios_version_count" -gt 1 ]; then
    failures+=("kmp/iosApp/project.yml: multiple MARKETING_VERSION values: $(printf '%s' "$ios_versions" | tr '\n' ' ')")
  else
    add_version "kmp/iosApp/project.yml" "$(printf '%s\n' "$ios_versions" | sed '/^$/d' | head -n 1)"
  fi
fi

if [ -f kmp/androidApp/build.gradle.kts ]; then
  android_version="$(sed -n 's/^[[:space:]]*versionName[[:space:]]*=[[:space:]]*"\([^"]*\)".*$/\1/p' kmp/androidApp/build.gradle.kts | head -n 1)"
  add_version "kmp/androidApp/build.gradle.kts" "$android_version"
fi

if [ -f pubspec.yaml ]; then
  pubspec_version="$(sed -n 's/^version:[[:space:]]*\([0-9][0-9.]*\)\(+[0-9][0-9]*\)\{0,1\}[[:space:]]*$/\1/p' pubspec.yaml | head -n 1)"
  add_version "pubspec.yaml" "$pubspec_version"
fi

if [ "${#versions[@]}" -eq 0 ]; then
  failures+=("No active version manifests found")
fi

if [ "${#failures[@]}" -gt 0 ]; then
  echo "Version consistency check failed:"
  for failure in "${failures[@]}"; do
    echo " - ${failure}"
  done
  exit 1
fi

echo "Active manifest versions are consistent:"
for entry in "${versions[@]}"; do
  echo " - ${entry}"
done

if [ -n "$TARGET_VERSION" ]; then
  echo "Target release version: ${TARGET_VERSION}"
  echo "Manifest base version: ${TARGET_BASE}"
fi
