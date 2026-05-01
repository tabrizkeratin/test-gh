#!/usr/bin/env bash
set -euo pipefail

# Delete all completed runs of the download and clean workflows.
# Requires `gh` CLI authenticated and `jq`.

workflows=("download-url.yml" "clean-downloads.yml")

for wf in "${workflows[@]}"; do
  echo "Deleting runs of workflow: $wf"
  gh run list --workflow "$wf" --limit 500 --status completed --json databaseId -q '.[].databaseId' |
    while read -r run_id; do
      echo "  Deleting run $run_id"
      gh run delete "$run_id" || true
    done
done

echo "All completed runs deleted. Active or queued runs are ignored."
