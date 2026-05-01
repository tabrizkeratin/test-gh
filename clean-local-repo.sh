#!/bin/bash
# clean-local-repo.sh
# Resets all local branches to match the remote after a history rewrite,
# then aggressively garbage collects to reclaim disk space.

set -euo pipefail

echo "⚠️  This will reset ALL local branches to match the remote (origin)."
echo "   Any local commits not on the remote will be lost."
echo "   Make sure you have no uncommitted changes or stashes you want to keep."
echo ""
read -rp "Are you sure you want to continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

# --- 1. Fetch everything ---
echo "⚡ Fetching all branches and tags (force)..."
git fetch --all --prune
git fetch --force --tags

# --- 2. Remember the current branch ---
current_branch=$(git rev-parse --abbrev-ref HEAD)

# --- 3. Reset every local branch to match origin ---
echo "🔄 Resetting local branches to match origin..."
git branch -r | grep -v '\->' | sed 's/origin\///' | while read branch; do
  # -B creates the branch if it doesn’t exist, and resets it to the remote state
  git checkout -B "$branch" "origin/$branch"
done

# --- 4. Switch back to the original branch (or a fallback) ---
if git show-ref --verify --quiet "refs/heads/$current_branch"; then
  git checkout "$current_branch"
else
  # the original branch might have been deleted on the remote
  if git show-ref --verify --quiet "refs/heads/main"; then
    git checkout main
  elif git show-ref --verify --quiet "refs/heads/master"; then
    git checkout master
  else
    echo "ℹ️  Could not find a default branch, staying at current HEAD."
  fi
fi

# --- 5. Squash reflogs and garbage collect ---
echo "🧹 Cleaning unreachable objects and reflogs..."
git reflog expire --expire=now --all
git gc --prune=now --aggressive

echo "✅ All done. Your local repo now matches the cleaned remote."
