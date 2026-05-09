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

  # YouTube advanced options
  local yt_format_spec="" yt_extract_audio=false yt_audio_format="mp3"
  local yt_subs="" yt_embed_subs=false yt_embed_thumbnail=false yt_remux=false

  # Manual argument parsing
  while [[ $# -gt 0 ]]; do
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
    --yt-format-spec)
      yt_format_spec="$2"
      shift 2
      ;;
    --yt-extract-audio)
      yt_extract_audio=true
      shift
      ;;
    --yt-audio-format)
      yt_audio_format="$2"
      shift 2
      ;;
    --yt-subs)
      yt_subs="$2"
      shift 2
      ;;
    --yt-embed-subs)
      yt_embed_subs=true
      shift
      ;;
    --yt-embed-thumbnail)
      yt_embed_thumbnail=true
      shift
      ;;
    --yt-remux)
      yt_remux=true
      shift
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
    -*)
      print_error "Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      # Non-option argument – treat as URL? (not in spec)
      print_error "Unexpected argument: $1"
      usage
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

  # Optional reachability check
  if $enable_check; then
    IFS=',' read -ra url_array <<<"$final_urls"
    for url in "${url_array[@]}"; do
      if ! check_url_reachable "$url"; then
        print_warn "Unreachable: $url"
      fi
    done
  fi

  # Build gh workflow command
  local repo
  repo=$(get_repo)
  CMD=(gh workflow run download-url.yml --repo "$repo"
    --field token="$DOWNLOAD_TOKEN"
    --field urls="$final_urls"
    --field mode="$mode"
    --field split_size_mb="$split_size")

  # Add YouTube-specific fields only if YouTube URLs are present
  if echo "$final_urls" | grep -qE '(youtube\.com/watch\?v=|youtu\.be/)'; then

    # 1. Format spec (custom takes precedence over quality mapping)
    if [[ -n "$yt_format_spec" ]]; then
      CMD+=(--field yt_format_spec="$yt_format_spec")
    elif [[ "$quality" != "best" ]]; then
      local qfields
      qfields=$(quality_to_workflow_fields "$quality")
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        CMD+=($line)
      done <<<"$qfields"
    fi

    # 2. Audio extraction (explicit flag or quality=audio)
    if [[ "$yt_extract_audio" == "true" ]] || [[ "$quality" == "audio" ]]; then
      CMD+=(--field yt_extract_audio=true)
      CMD+=(--field yt_audio_format="$yt_audio_format")
    fi

    # 3. Subtitles
    if [[ -n "$yt_subs" ]]; then
      CMD+=(--field yt_subs="$yt_subs")
      if [[ "$yt_embed_subs" == "true" ]]; then
        CMD+=(--field yt_embed_subs=true)
      fi
    fi

    # 4. Thumbnail embedding
    if [[ "$yt_embed_thumbnail" == "true" ]]; then
      CMD+=(--field yt_embed_thumbnail=true)
    fi

    # 5. Remux
    if [[ "$yt_remux" == "true" ]]; then
      CMD+=(--field yt_remux=true)
    fi
  fi

  # Cookies file
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
  -q, --quality QUALITY         Simple quality preset (best,1080p,720p,480p,audio)
  -m, --mode MODE               Mode (download-full, auto, download-zip)
  -s, --split-size MB           Split size in MB (0 to disable, default 95)
  -c, --cookies FILE            Path to cookies.txt
  -t, --token TOKEN             DOWNLOAD_TOKEN (overrides .env)

YouTube advanced options (if URL is YouTube):
  --yt-format-spec SPEC         yt-dlp format spec (overrides --quality)
  --yt-extract-audio            Extract audio only
  --yt-audio-format FORMAT      Audio format: mp3, m4a, opus (default mp3)
  --yt-subs LANGS               Comma-separated subtitle languages (e.g., en,fr)
  --yt-embed-subs               Embed subtitles into file
  --yt-embed-thumbnail          Embed thumbnail into file
  --yt-remux                    Remux video for better compatibility

Other:
      --check                   Enable URL reachability checks (off by default)
      --dry-run                 Print command without executing
  -h, --help                    This message

Interactive mode: run without any options.
EOF
}
