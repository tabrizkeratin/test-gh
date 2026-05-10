#!/usr/bin/env bash
set -euo pipefail

# Simply forward all arguments to download_urls.sh (so they are exactly the same flags).
# This script exists to provide an obvious non‑interactive entrypoint.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/download_urls.sh" "$@"