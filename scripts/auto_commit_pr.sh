#!/bin/bash
# scripts/auto_commit_pr.sh
# Automates the Git flow: runs safety checks, commits with correct prefix, pushes, and creates/updates a GitHub PR.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

# 1. Check if git status has changes
if [ -z "$(git status --porcelain)" ]; then
  echo "No changes detected in working tree. Nothing to commit."
  exit 0
fi

# 2. Check current branch. Nobody commits directly to main.
CURRENT_BRANCH="$(git branch --show-current)"
if [ "$CURRENT_BRANCH" = "main" ]; then
  echo "ERROR: You are on the 'main' branch. Direct commits to main are prohibited."
  echo "Please create a task branch first: git switch -c codex/feature-name"
  exit 1
fi

# 3. Verify no sensitive files are about to be committed
echo "Running safety scan..."
if ! scripts/verify_no_sensitive_files.sh; then
  echo "ERROR: Sensitive files validation failed. Aborting commit."
  exit 1
fi

# 4. Determine commit type and message
TYPE=""
MSG=""

usage() {
  echo "Usage:"
  echo "  scripts/auto_commit_pr.sh [type] [message]"
  echo "Allowed types: docs, ui, fix, feat, kmp, data, build, test, refactor"
  echo "Example: scripts/auto_commit_pr.sh fix \"prevent notebook cell layout shift\""
}

# If arguments are provided
if [ $# -ge 2 ]; then
  TYPE="$1"
  shift
  MSG="$*"
else
  # Interactive mode
  echo "Select the commit intention type:"
  options=("docs" "ui" "fix" "feat" "kmp" "data" "build" "test" "refactor")
  
  # Custom select fallback for environments with limited shell interactive capabilities
  if [ -t 0 ]; then
    select opt in "${options[@]}"; do
      if [ -n "$opt" ]; then
        TYPE="$opt"
        break
      else
        echo "Invalid selection."
      fi
    done
  else
    # Non-interactive fallback: require first parameter or default to docs
    echo "Non-interactive environment detected."
    TYPE="docs"
  fi

  if [ -t 0 ]; then
    echo "Enter a short descriptive message (e.g., 'prevent orphan columns in notebook'):"
    read -r MSG
  else
    echo "Non-interactive environment detected. Message must be provided as argument."
    usage
    exit 1
  fi
fi

# Validate type
case "$TYPE" in
  docs|ui|fix|feat|kmp|data|build|test|refactor) ;;
  *)
    echo "ERROR: Invalid commit type '$TYPE'."
    usage
    exit 1
    ;;
esac

if [ -z "$MSG" ]; then
  echo "ERROR: Commit message cannot be empty."
  exit 1
fi

# Format commit message
COMMIT_MSG="${TYPE}: ${MSG}"

# 5. Git actions
echo "Staging all changes..."
git add -A

echo "Creating commit: '${COMMIT_MSG}'"
git commit -m "$COMMIT_MSG"

echo "Pushing changes to origin..."
git push -u origin "$CURRENT_BRANCH"

# 6. GitHub PR Automation
if which gh >/dev/null 2>&1; then
  echo "Checking Pull Request status on GitHub..."
  # Check if a PR already exists for the current branch
  PR_EXISTS=$(gh pr list --head "$CURRENT_BRANCH" --json number -q '.[0].number')

  if [ -n "$PR_EXISTS" ]; then
    echo "PR #${PR_EXISTS} already exists. Pushing has updated it."
    # Print the PR URL
    gh pr view --json url -q .url
  else
    echo "No PR found. Creating a new Pull Request on GitHub..."
    
    # Create as draft by default to protect main and require review
    gh pr create \
      --title "$COMMIT_MSG" \
      --body-file .github/pull_request_template.md \
      --draft
    
    echo "Draft PR created successfully!"
  fi
else
  echo "GitHub CLI (gh) not found or not authenticated. Please open a PR manually at https://github.com/mafepa21/mi_gestor_evaluaciones"
fi
