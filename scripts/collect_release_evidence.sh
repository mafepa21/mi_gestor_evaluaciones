#!/bin/bash
# Prints a compact release evidence report for PRs and manual releases.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

VERSION="${1:-}"

if [ -n "$VERSION" ] && ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$ ]]; then
  echo "Invalid version: ${VERSION}"
  echo "Expected examples: 0.3.0, 0.3.0-alpha.1, 0.4.0-beta.1, 1.0.0-rc.1"
  exit 1
fi

echo "# Release evidence"
echo
echo "- Date UTC: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "- Branch: $(git branch --show-current)"
echo "- Commit: $(git rev-parse --short HEAD)"
if [ -n "$VERSION" ]; then
  echo "- Target version: ${VERSION}"
fi
echo "- Working tree clean: $([ -z "$(git status --porcelain)" ] && echo yes || echo no)"
echo

echo "## Required checks"
echo
echo "| Check | Command | Status source |"
echo "|---|---|---|"
echo "| Sensitive files | scripts/verify_no_sensitive_files.sh | Run locally and in CI |"
echo "| Version consistency | scripts/check_version_consistency.sh ${VERSION:-<version>} | Run locally and in CI |"
echo "| KMP shared | (cd kmp && ./gradlew :shared:test) | Run when KMP changes or for release PR |"
echo "| KMP data | (cd kmp && ./gradlew :data:desktopTest) | Run when data changes or for release PR |"
echo "| Apple builds | scripts/verify_apple_builds.sh | Run when Apple app changes or for release PR |"
echo

echo "## Local safety snapshot"
echo
set +e
scripts/verify_no_sensitive_files.sh
sensitive_status=$?
if [ -n "$VERSION" ]; then
  scripts/check_version_consistency.sh "$VERSION"
  version_status=$?
else
  scripts/check_version_consistency.sh
  version_status=$?
fi
set -e

echo
echo "## Local check status"
echo
echo "- Sensitive files check: $([ "$sensitive_status" -eq 0 ] && echo pass || echo fail)"
echo "- Version consistency check: $([ "$version_status" -eq 0 ] && echo pass || echo fail)"
