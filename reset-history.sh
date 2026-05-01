#!/bin/bash
set -e # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🚀 This script will:${NC}"
echo "   1. Delete ALL commit history (orphan branch + force push)"
echo "   2. Delete ALL GitHub Actions workflow runs for this repo"
echo ""
read -p "⚠️  Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

# -------------------------------------------------------------------
# 1. Detect current default branch (main or master)
# -------------------------------------------------------------------
DEFAULT_BRANCH=$(git remote show origin | grep 'HEAD branch' | cut -d' ' -f5)
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH="main"
fi
echo -e "${GREEN}✓ Default branch detected: $DEFAULT_BRANCH${NC}"

# -------------------------------------------------------------------
# 2. Delete ALL GitHub Actions workflow runs (using gh CLI)
# -------------------------------------------------------------------
if command -v gh &>/dev/null; then
  echo -e "${YELLOW}📦 Deleting all workflow runs for this repository...${NC}"

  # Get current repo from git remote
  REPO_URL=$(git config --get remote.origin.url)
  # Convert git@github.com:owner/repo.git or https://github.com/owner/repo.git to owner/repo
  REPO_NAME=$(echo "$REPO_URL" | sed -E 's/.*[:/]([^/]+\/[^/.]+)(\.git)?$/\1/')

  # Fetch all run IDs (paginated, up to 1000)
  RUN_IDS=$(gh run list --repo "$REPO_NAME" --limit 1000 --json databaseId --jq '.[].databaseId')

  if [ -n "$RUN_IDS" ]; then
    echo "$RUN_IDS" | while read -r run_id; do
      echo "  Deleting run $run_id"
      gh run delete --repo "$REPO_NAME" "$run_id"
    done
    echo -e "${GREEN}✓ All workflow runs deleted.${NC}"
  else
    echo -e "${GREEN}✓ No workflow runs found.${NC}"
  fi
else
  echo -e "${RED}⚠️  GitHub CLI (gh) not found. Skipping workflow run deletion.${NC}"
  echo "   Install from: https://cli.github.com/"
fi

# -------------------------------------------------------------------
# 3. Reset Git history (orphan branch method)
# -------------------------------------------------------------------
echo -e "${YELLOW}🔄 Resetting Git history...${NC}"

git checkout --orphan latest-branch
git add -A
git commit -m "Initial commit with cleaned history"

git branch -D "$DEFAULT_BRANCH"
git branch -m "$DEFAULT_BRANCH"

# Push with upstream tracking
git push -f --set-upstream origin "$DEFAULT_BRANCH"

# -------------------------------------------------------------------
# 4. Final instructions
# -------------------------------------------------------------------
echo -e "${GREEN}✅ Done!${NC}"
echo ""
echo "History completely reset and force-pushed."
echo "All workflow runs have been deleted."
echo ""
echo "Collaborators must re-clone or run:"
echo "  git fetch --all"
echo "  git reset --hard origin/$DEFAULT_BRANCH"
