#!/bin/bash
# Checks that Git is not about to track local databases, builds, logs, secrets or real backup artifacts.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

failures=()

is_allowed_fixture_exception() {
  local path="$1"
  local name
  name="$(basename "$path")"

  case "$path" in
    tests/fixtures/anonymous_*|tests/fixtures/demo_*)
      case "$name" in
        anonymous_*|demo_*) return 0 ;;
      esac
      ;;
  esac

  return 1
}

is_sensitive_path() {
  local path="$1"
  local name
  name="$(basename "$path")"

  if is_allowed_fixture_exception "$path"; then
    return 1
  fi

  case "$name" in
    .env|.env.*)
      case "$name" in
        .env.example|.env.sample|.env.template) return 1 ;;
      esac
      return 0
      ;;
  esac

  case "$path" in
    *.db|*.db-*|*.sqlite|*.sqlite-*|*.sqlite3|*.sqlite3-*|*.dmg|*.app|*.ipa|*.xcarchive|*.log|*.bak|*.backup|*.key|*.pem|*.p12|*.mobileprovision)
      return 0
      ;;
    *"/build/"*|*"DerivedData"*|*"Backups/"*|*"backups/"*|*"backup/"*|*"Logs/"*|*"logs/"*)
      return 0
      ;;
  esac

  return 1
}

while IFS= read -r -d '' path; do
  if is_sensitive_path "$path"; then
    failures+=("$path")
  fi
done < <(git ls-files --cached --others --exclude-standard -z)

if [ "${#failures[@]}" -gt 0 ]; then
  echo "Sensitive or generated files detected. Do not commit these paths:"
  for path in "${failures[@]}"; do
    echo " - ${path}"
  done
  echo
  echo "Allowed future exceptions are limited to tests/fixtures/anonymous_* or tests/fixtures/demo_*."
  exit 1
fi

echo "No sensitive or generated files detected in tracked/unignored paths."
