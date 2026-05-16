#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."
ENV_FILE="${REPO_ROOT}/.env"
export SCRIPT_DIR REPO_ROOT

# Sensible defaults
export DEFAULT_MODE="auto"
export DEFAULT_SPLIT_MB=90
export DEFAULT_COOKIES=""

# Load .env if exists
if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
fi
export DOWNLOAD_TOKEN="${DOWNLOAD_TOKEN:-}"

# Source helpers (needed by both modes)
source "${SCRIPT_DIR}/lib/helpers.sh"

if [[ $# -eq 0 ]]; then
  source "${SCRIPT_DIR}/lib/interactive.sh"
  run_interactive
else
  source "${SCRIPT_DIR}/lib/noninteractive.sh"
  run_noninteractive "$@"
fi
