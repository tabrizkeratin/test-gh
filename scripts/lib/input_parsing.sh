#!/usr/bin/env bash
# Functions: collect URLs, deduplicate, and optionally validate
set -euo pipefail

# Convert a newline‑separated string into a comma‑separated string, deduplicating
# while preserving order.
dedupe_and_join() {
  local input="$1"
  awk '!seen[$0]++' <<<"$input" | paste -sd ',' -
}

# Collect URLs from interactive text input (gum or plain read)
# Returns comma‑separated, deduplicated string.
collect_urls_interactive() {
  local raw
  if $GUM_AVAILABLE; then
    raw=$(gum write --header "Paste URLs (one per line, Ctrl+D when done)" \
      --width 80 --height 10 --placeholder "https://...")
  else
    echo "Paste your URLs, one per line. Press Ctrl+D when finished:"
    raw=$(cat)
  fi
  # Trim & filter empty lines
  local cleaned
  cleaned=$(echo "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')
  if [[ -z "$cleaned" ]]; then
    print_error "No URLs provided."
    exit 1
  fi
  dedupe_and_join "$cleaned"
}

# Read URLs from a file (one per line), deduplicate, join with commas
collect_urls_from_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    print_error "File not found: $file"
    exit 1
  fi
  local cleaned
  cleaned=$(sed 's/^[[:space:]]*//;s/[[:space:]]*$//' "$file" | grep -v '^$')
  if [[ -z "$cleaned" ]]; then
    print_error "No URLs found in $file"
    exit 1
  fi
  dedupe_and_join "$cleaned"
}

# Basic classification: does a URL look like a YouTube link?
is_youtube_url() {
  local url="$1"
  [[ "$url" =~ ^(https?://)?(www\.)?(youtube\.com|youtu\.be)/ ]]
}

# Return comma‑separated YouTube URLs only (deduplicated)
extract_youtube_urls() {
  local joined_csv="$1"
  local -a yt=()
  IFS=',' read -ra urls <<<"$joined_csv"
  for url in "${urls[@]}"; do
    if is_youtube_url "$url"; then
      yt+=("$url")
    fi
  done
  (
    IFS=','
    echo "${yt[*]}"
  )
}

# Optional reachability check (only if --check flag is active)
check_url_reachable() {
  local url="$1"
  curl -sIL --max-time 5 "$url" &>/dev/null
}
