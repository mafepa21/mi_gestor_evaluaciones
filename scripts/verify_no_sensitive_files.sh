#!/bin/bash
# Checks that Git is not about to track local databases, builds, logs, secrets or real backup artifacts.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

failures=()

is_sensitive_path() {
  local path="$1"
  local name
  name="$(basename "$path")"

  case "$name" in
    .env|.env.*)
      case "$name" in
        .env.example|.env.sample|.env.template) return 1 ;;
      esac
      return 0
      ;;
  esac

  case "$path" in
    *.db|*.sqlite|*.sqlite3|*.dmg|*.app|*.ipa|*.xcarchive|*.log|*.bak|*.backup|*.key|*.pem|*.p12|*.mobileprovision)
      return 0
      ;;
    *"/build/"*|*"DerivedData"*|*"Backups/"*|*"backups/"*)
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
  exit 1
fi

echo "No sensitive or generated files detected in tracked/unignored paths."
