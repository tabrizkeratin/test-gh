#!/usr/bin/env bash
# Non‑interactive dispatch – sourced
set -euo pipefail

source "${SCRIPT_DIR}/lib/helpers.sh"
source "${SCRIPT_DIR}/lib/input_parsing.sh"
source "${SCRIPT_DIR}/lib/quality_map.sh"

run_noninteractive() {
  # Defaults
  local urls="" urls_file="" quality="best"
  local mode="${DEFAULT_MODE:-auto}"
  local split_size="${DEFAULT_SPLIT_MB:-95}"
  local cookies="" dry_run=false enable_check=false

  TEMP=$(getopt -o u:f:q:m:s:c:t:h \
    --long urls:,urls-file:,quality:,mode:,split-size:,cookies:,token:,check,dry-run,help \
    -n 'download.sh' -- "$@")
  eval set -- "$TEMP"
  while true; do
    case "$1" in
    -u | --urls)
      urls="$2"
      shift 2
      ;;
    -f | --urls-file)
      urls_file="$2"
      shift 2
      ;;
    -q | --quality)
      quality="$2"
      shift 2
      ;;
    -m | --mode)
      mode="$2"
      shift 2
      ;;
    -s | --split-size)
      split_size="$2"
      shift 2
      ;;
    -c | --cookies)
      cookies="$2"
      shift 2
      ;;
    -t | --token)
      DOWNLOAD_TOKEN="$2"
      shift 2
      ;;
    --check)
      enable_check=true
      shift
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      print_error "Internal error"
      exit 1
      ;;
    esac
  done

  # Collect URLs
  local final_urls=""
  if [[ -n "$urls_file" ]]; then
    final_urls=$(collect_urls_from_file "$urls_file")
  fi
  if [[ -n "$urls" ]]; then
    # Deduplicate comma-separated argument as well
    local cleaned
    cleaned=$(echo "$urls" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')
    if [[ -n "$cleaned" ]]; then
      cleaned=$(dedupe_and_join "$cleaned")
      if [[ -n "$final_urls" ]]; then
        final_urls="$final_urls,$cleaned"
      else
        final_urls="$cleaned"
      fi
    fi
  fi
  if [[ -z "$final_urls" ]]; then
    print_error "No URLs provided."
    exit 1
  fi

  validate_token

  # Optional reachability check (only if --check)
  if $enable_check; then
    IFS=',' read -ra url_array <<<"$final_urls"
    for url in "${url_array[@]}"; do
      if ! check_url_reachable "$url"; then
        print_warn "Unreachable: $url"
      fi
    done
  fi

  # Build command
  local repo
  repo=$(get_repo)
  CMD=(gh workflow run download-url.yml --repo "$repo"
    --field token="$DOWNLOAD_TOKEN"
    --field urls="$final_urls"
    --field mode="$mode"
    --field split_size_mb="$split_size")

  # Map quality to workflow fields only if YouTube URLs are present
  if echo "$final_urls" | grep -qE '(youtube\.com/watch\?v=|youtu\.be/)'; then
    local qfields
    qfields=$(quality_to_workflow_fields "$quality")
    if [[ -n "$qfields" ]]; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        CMD+=($line)
      done <<<"$qfields"
    fi
  fi

  if [[ -n "$cookies" && -f "$cookies" ]]; then
    CMD+=(--field cookies="$(cat "$cookies")")
  fi

  if $dry_run; then
    echo "Dry run – would execute:"
    printf '%q ' "${CMD[@]}"
    echo
    exit 0
  fi

  "${CMD[@]}"
  print_success "Workflow dispatched."
}

usage() {
  cat <<EOF
Usage: ./download.sh [OPTIONS]

Options:
  -u, --urls "URL1,URL2"        Comma-separated URLs
  -f, --urls-file FILE          File with one URL per line
  -q, --quality QUALITY         Quality (best,1080p,720p,480p,audio)
  -m, --mode MODE               Mode (download-full, auto, download-zip)
  -s, --split-size MB           Split size in MB (0 to disable, default 95)
  -c, --cookies FILE            Path to cookies.txt
  -t, --token TOKEN             DOWNLOAD_TOKEN (overrides .env)
      --check                   Enable URL reachability checks (off by default)
      --dry-run                 Print command without executing
  -h, --help                    This message

Interactive mode: run without any options.
EOF
}
