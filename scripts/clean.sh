#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [--dry-run] [--confirm] [--local-only] [--purge-runs]

Options:
  --dry-run      Trigger a dry-run workflow (default)
  --confirm      Actually rewrite remote history (requires confirmation)
  --local-only   Only reset local repo (no remote workflow)
  --purge-runs   After a successful remote clean, delete all completed workflow runs
  -h, --help     Show this help
EOF
}

DRY_RUN=true
CONFIRM=false
LOCAL_ONLY=false
PURGE_RUNS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run)
    DRY_RUN=true
    CONFIRM=false
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
  --purge-runs)
    PURGE_RUNS=true
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
    echo "Dispatching clean workflow (confirm)..."
    gh workflow run clean-downloads.yml -f dry_run=false -f confirm="YES" --ref main
  else
    echo "Dispatching dry-run clean workflow..."
    gh workflow run clean-downloads.yml -f dry_run=true --ref main
    echo ""
    echo "Dry-run dispatched. Check workflow logs for what would be removed."
    echo "To actually clean, run: ./scripts/clean.sh --confirm"
    exit 0
  fi
fi

# --- Wait for the remote workflow to finish (if confirm) ---------------------
if [ "$CONFIRM" = true ]; then
  echo ""
  echo "Waiting for the clean workflow to complete..."
  # The run we just dispatched is the most recent one for this workflow
  RUN_ID=$(gh run list --workflow=clean-downloads.yml --limit 1 --json databaseId -q '.[0].databaseId')
  if [ -z "$RUN_ID" ]; then
    echo "Could not find a recent run. It may have finished already."
  else
    echo "Watching run $RUN_ID..."
    gh run watch "$RUN_ID" || {
      echo "Clean workflow failed. Aborting local reset."
      exit 1
    }
  fi
  echo "Clean workflow finished successfully."
fi

# --- Local reset (only after a successful confirmed clean or local-only) ------
if [ "$LOCAL_ONLY" = true ] || [ "$CONFIRM" = true ]; then
  echo ""
  echo "Resetting local branches to match remote..."
  git fetch --prune
  git fetch origin --tags

  DEFAULT_BRANCH=$(git remote show origin | grep 'HEAD branch' | awk '{print $NF}')
  git checkout "$DEFAULT_BRANCH" 2>/dev/null || git checkout main 2>/dev/null || true

  # Reset all local branches that have a remote counterpart
  for branch in $(git branch | sed 's/[* ]//'); do
    if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      echo "  Resetting $branch..."
      git branch -D "$branch" 2>/dev/null || true
      git checkout -b "$branch" "origin/$branch" 2>/dev/null || true
    fi
  done

  # Return to default branch
  git checkout "$DEFAULT_BRANCH" 2>/dev/null || true
  # Clean untracked/ignored files but keep .env
  git clean -fdx -e .env
  git reflog expire --expire=now --all
  git gc --prune=now --aggressive
  echo "Local repository cleaned."
fi

# --- Purge workflow runs (after everything else) ------------------------------
if [ "$PURGE_RUNS" = true ]; then
  if [ "$CONFIRM" != true ] && [ "$LOCAL_ONLY" != true ]; then
    echo "Warning: --purge-runs without a successful clean may leave inconsistent state."
  fi
  echo ""
  echo "Purging all completed Actions runs..."
  if [ -x "./scripts/clean-runs.sh" ]; then
    ./scripts/clean-runs.sh
  else
    echo "Error: scripts/clean-runs.sh not found or not executable."
    exit 1
  fi
fi
