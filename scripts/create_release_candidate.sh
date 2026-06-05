#!/bin/bash
# Prepares a release-candidate branch and prints the required checklist.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

usage() {
  cat <<'EOF'
Usage:
  scripts/create_release_candidate.sh 0.3.0-alpha.1

Creates or switches to codex/release-0-3-0-alpha-1 and runs release safety checks.
It does not create tags, GitHub Releases or version bumps automatically.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "${1:-}" = "" ]; then
  usage
  exit 0
fi

VERSION="$1"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9]+(\.[0-9]+)?)?$ ]]; then
  echo "Invalid version: ${VERSION}"
  echo "Expected examples: 0.3.0, 0.3.0-alpha.1, 0.4.0-beta.1"
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "Working tree is not clean. Commit or stash current changes before preparing a release candidate."
  git status --short
  exit 1
fi

BRANCH="codex/release-${VERSION//./-}"
BRANCH="${BRANCH//_/-}"

CURRENT_BRANCH="$(git branch --show-current)"

if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
  git switch "$BRANCH"
else
  git switch -c "$BRANCH"
fi

scripts/verify_no_sensitive_files.sh

cat <<EOF

Release candidate branch ready.

Version: ${VERSION}
Branch:  ${BRANCH}
Started from: ${CURRENT_BRANCH}

Next steps:
1. Align active manifests if this is a real release.
2. Move relevant changelog lines from Unreleased to v${VERSION}.
3. Run KMP/data checks when relevant.
4. Run Apple build checks when relevant.
5. Open or update the release PR against main.
6. Create tag v${VERSION} only after merge and green evidence.
EOF
