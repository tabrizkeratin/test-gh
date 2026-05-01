#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  source "$SCRIPT_DIR/.env"
  set +a
elif [ -f ".env" ]; then
  set -a
  source ".env"
  set +a
fi

MODE="${MODE:-}"
SPLIT_SIZE="${SPLIT_SIZE:-90}"
ALLOWED_DOMAINS="${ALLOWED_DOMAINS:-}"
COMMIT_MSG="${COMMIT_MSG:-chore: download files}"
DOWNLOAD_TOKEN="${DOWNLOAD_TOKEN:-}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] URLS...

URLs can be specified in any of these ways:
  ./download.sh https://example.com/a.bin https://example.com/b.bin
  ./download.sh "https://example.com/a.bin https://example.com/b.bin"
  ./download.sh "https://example.com/a.bin, https://example.com/b.bin"
  ./download.sh https://example.com/a.bin,https://example.com/b.bin
  and any combination.

Options:
  --mode            download | download-zip (auto-detected: single → download, multiple → download-zip)
  --split-size-mb   Split files larger than this size (default: ${SPLIT_SIZE})
  --allowed-domains Comma‑separated list of allowed domains (* for all)
  --commit-message  Custom commit message
  --token           Download token (overrides DOWNLOAD_TOKEN in .env)
  -h, --help        Show this help
EOF
}

URL_PARTS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --mode)
    MODE="$2"
    shift 2
    ;;
  --split-size-mb)
    SPLIT_SIZE="$2"
    shift 2
    ;;
  --allowed-domains)
    ALLOWED_DOMAINS="$2"
    shift 2
    ;;
  --commit-message)
    COMMIT_MSG="$2"
    shift 2
    ;;
  --token)
    DOWNLOAD_TOKEN="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --*)
    echo "Unknown option: $1"
    usage
    exit 1
    ;;
  *)
    URL_PARTS+=("$1")
    shift
    ;;
  esac
done

# Parse URLs
raw_input="${URL_PARTS[*]}"
unified=$(echo "$raw_input" | tr ',' ' ')
urls=()
for token in $unified; do
  clean=$(echo "$token" | sed -e 's/^["'"'"']//' -e 's/["'"'"']$//')
  urls+=("$clean")
done
filtered_urls=()
for u in "${urls[@]}"; do [ -n "$u" ] && filtered_urls+=("$u"); done
urls=("${filtered_urls[@]}")

if [ ${#urls[@]} -eq 0 ]; then
  echo "Error: no URLs."
  usage
  exit 1
fi

# Auto mode
if [ -z "$MODE" ]; then
  if [ ${#urls[@]} -gt 1 ]; then MODE="download-zip"; else MODE="download"; fi
  echo "Auto‑detected mode: $MODE"
fi

# Trim allowed domains
ALLOWED_DOMAINS_TRIM=$(echo "$ALLOWED_DOMAINS" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | paste -sd ',' -)

if [ -z "$ALLOWED_DOMAINS_TRIM" ] && [ "$ALLOWED_DOMAINS_TRIM" != "*" ]; then
  echo "Error: no allowed domains."
  exit 1
fi

# Token
if [ -z "$DOWNLOAD_TOKEN" ]; then
  read -rsp "Enter download token: " DOWNLOAD_TOKEN
  echo
fi
if [ -z "$DOWNLOAD_TOKEN" ]; then
  echo "Error: no token."
  exit 1
fi

URL_INPUT=$(
  IFS=$'\n'
  echo "${urls[*]}"
)

echo ""
echo "Dispatching workflow:"
echo "  URLs (${#urls[@]}):"
for u in "${urls[@]}"; do echo "    - $u"; done
echo "  Mode:               $MODE"
echo "  Split size:         ${SPLIT_SIZE}MB"
echo "  Allowed domains:    $ALLOWED_DOMAINS_TRIM"
echo "  Commit message:     $COMMIT_MSG"
echo ""

gh workflow run download-url.yml \
  -f download_token="$DOWNLOAD_TOKEN" \
  -f urls="$URL_INPUT" \
  -f mode="$MODE" \
  -f split_size_mb="$SPLIT_SIZE" \
  -f allowed_domains="$ALLOWED_DOMAINS_TRIM" \
  -f commit_message="$COMMIT_MSG" \
  --ref main

echo "Workflow dispatched. See: https://github.com/$GITHUB_REPOSITORY/actions"
