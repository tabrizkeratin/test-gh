#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [--dry-run] [--confirm] [--local-only]

Options:
  --dry-run     Trigger a dry-run workflow (default)
  --confirm     Actually rewrite remote history (requires confirmation)
  --local-only  Only reset local repo (no remote workflow)
  -h, --help    Show this help
EOF
}

DRY_RUN=true
CONFIRM=false
LOCAL_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run)
    DRY_RUN=true
    shift
    ;;
  --confirm)
    CONFIRM=true
    DRY_RUN=false
    shift
    ;;
  --local-only)
    LOCAL_ONLY=true
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown option: $1"
    usage
    exit 1
    ;;
  esac
done

# --- Remote part --------------------------------------------------------------
if [ "$LOCAL_ONLY" = false ]; then
  if [ "$CONFIRM" = true ]; then
    read -rp "This will irrevocably rewrite remote history. Type 'YES' to continue: " answer
    if [ "$answer" != "YES" ]; then
      echo "Aborted."
      exit 0
    fi
    gh workflow run clean-downloads.yml -f dry_run=false -f confirm="YES" --ref main
    echo ""
    echo "Clean workflow dispatched. Wait for it to finish, then run:"
    echo "  ./scripts/clean.sh --local-only"
  else
    gh workflow run clean-downloads.yml -f dry_run=true --ref main
    echo ""
    echo "Dry-run dispatched. Check workflow logs for what would be removed."
    echo "To actually clean, run: ./scripts/clean.sh --confirm"
  fi
fi

# --- Local reset --------------------------------------------------------------
if [ "$LOCAL_ONLY" = true ] || [ "$CONFIRM" = true ]; then
  echo ""
  echo "Resetting local branches to match remote..."
  git fetch --prune
  git fetch origin --tags
  git checkout main 2>/dev/null || git checkout master 2>/dev/null || true

  # Reset all local branches that have a remote counterpart
  for branch in $(git branch | sed 's/[* ]//'); do
    if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      echo "  Resetting $branch..."
      git branch -D "$branch" 2>/dev/null || true
      git checkout -b "$branch" "origin/$branch" 2>/dev/null || true
    fi
  done

  # Return to default branch and clean untracked files
  DEFAULT_BRANCH=$(git remote show origin | grep 'HEAD branch' | awk '{print $NF}')
  git checkout "$DEFAULT_BRANCH" 2>/dev/null || git checkout main 2>/dev/null || true
  git clean -fdx
  echo ""
  echo "Local repository cleaned."
fi
