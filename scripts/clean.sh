#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Defaults
DRY_RUN=true
PURGE_RUNS=false
LOCAL_GC=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  --confirm)
    DRY_RUN=false
    shift
    ;;
  --dry-run)
    DRY_RUN=true
    shift
    ;;
  --purge-runs)
    PURGE_RUNS=true
    shift
    ;;
  --local-gc)
    LOCAL_GC=true
    shift
    ;;
  --help)
    cat <<EOF
Usage: $0 [options]

Options:
  --confirm       Actually perform destructive cleanup (rewrite history, force push)
  --dry-run       Show what would be done (default)
  --purge-runs    After successful cleanup, delete completed workflow runs
  --local-gc      Also run local git garbage collection to shrink repository size
  --help          Show this help

This tool removes the entire 'downloads/' folder from the repository history
using git-filter-repo. It then force-pushes the rewritten history.

WARNING: This rewrites commit history. All collaborators must reclone or reset.
EOF
    exit 0
    ;;
  *)
    echo "Unknown option: $1"
    exit 1
    ;;
  esac
done

# Check prerequisites
if ! command -v git-filter-repo &>/dev/null; then
  echo "Error: git-filter-repo not installed."
  echo "Install with: pip install git-filter-repo (or apt install git-filter-repo)"
  exit 1
fi

# Get current branch name
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
REMOTE=$(git remote get-url origin 2>/dev/null || echo "origin")

echo "========================================="
echo "  Downloads History Cleaner"
echo "========================================="
echo "Repository: $(basename "$(git rev-parse --show-toplevel)")"
echo "Current branch: $CURRENT_BRANCH"
echo "Remote: $REMOTE"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
  echo "⚠️  DRY RUN MODE – no changes will be made."
  echo ""
  echo "Would remove 'downloads/' from entire git history."
  if [[ "$PURGE_RUNS" == "true" ]]; then
    echo "Would also purge completed workflow runs."
  fi
  if [[ "$LOCAL_GC" == "true" ]]; then
    echo "Would also run local git GC after cleanup."
  fi
  echo ""
  echo "To perform actual cleanup, run: $0 --confirm"
  exit 0
fi

echo "⚠️  CONFIRMED – this will REWRITE HISTORY and FORCE PUSH."
read -rp "Type 'yes' to continue: " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

# 1. Run git-filter-repo to remove downloads/ folder
echo ""
echo "Removing 'downloads/' from history..."
git-filter-repo --path downloads/ --invert-paths --force

# 2. Force push the rewritten history
echo ""
echo "Force pushing to $REMOTE $CURRENT_BRANCH..."
git push --force "$REMOTE" "$CURRENT_BRANCH"
# git-filter-repo removes the 'origin' remote; re-add it
git remote add origin "$REMOTE" 2>/dev/null || git remote set-url origin "$REMOTE"

# 3. Purge workflow runs if requested
if [[ "$PURGE_RUNS" == "true" ]]; then
  echo ""
  echo "Purging completed workflow runs..."
  if [[ -f "$SCRIPT_DIR/clean-runs.sh" ]]; then
    "$SCRIPT_DIR/clean-runs.sh"
  else
    echo "Warning: clean-runs.sh not found. Skipping."
  fi
fi

# 4. Local garbage collection (optional)
if [[ "$LOCAL_GC" == "true" ]]; then
  echo ""
  echo "Performing local git garbage collection to shrink repository..."
  # Fetch latest from remote (which is now rewritten)
  git fetch --all --prune
  git reset --hard "origin/$CURRENT_BRANCH"
  git reflog expire --expire=now --all
  git gc --aggressive --prune=now
  echo "Local repository cleaned. Current size:"
  du -sh .git 2>/dev/null || du -sh .
else
  echo ""
  echo "Local repository may still contain old objects."
  echo "To shrink local repo, run: git reflog expire --expire=now --all && git gc --aggressive --prune=now"
  echo "Or re-clone the repository."
fi

echo ""
echo "✅ Cleanup complete."
