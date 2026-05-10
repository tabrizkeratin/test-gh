#!/usr/bin/env bash
# Non‑interactive dispatch – sourced
set -euo pipefail

source "${SCRIPT_DIR}/lib/helpers.sh"
source "${SCRIPT_DIR}/lib/input_parsing.sh"
source "${SCRIPT_DIR}/lib/quality_map.sh"

run_noninteractive() {
  # Defaults
  local urls="" urls_file="" quality="best"
  local mode="auto"
  local split_size=0
  local dry_run=false enable_check=false

  # Type selection
  local download_type="url"
  local package_name="" architecture="arm64" merge_splits="true" title=""

  # YouTube advanced options
  local yt_format_spec="" yt_extract_audio=false yt_audio_format="mp3"
  local yt_subs=false yt_embed_subs=false yt_embed_thumbnail=false yt_remux=false
  local playlist_items="" download_subtitles=false subtitle_langs="en"
  local embed_metadata=true embed_chapters=true sponsorblock=false
  local extra_args="" use_pot=true

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
    --type)
      download_type="$2"
      shift 2
      ;;
    --package-name)
      package_name="$2"
      shift 2
      ;;
    --architecture)
      architecture="$2"
      shift 2
      ;;
    --merge-splits)
      merge_splits="$2"
      shift 2
      ;;
    --title)
      title="$2"
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
    --playlist-items)
      playlist_items="$2"
      shift 2
      ;;
    --download-subs)
      download_subtitles=true
      shift
      ;;
    --sub-langs)
      subtitle_langs="$2"
      shift 2
      ;;
    --embed-metadata)
      embed_metadata=true
      shift
      ;;
    --embed-chapters)
      embed_chapters=true
      shift
      ;;
    --sponsorblock)
      sponsorblock=true
      shift
      ;;
    --use-pot)
      use_pot=true
      shift
      ;;
    --no-pot)
      use_pot=false
      shift
      ;;
    --extra-args)
      extra_args="$2"
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
    -*)
      print_error "Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      print_error "Unexpected argument: $1"
      usage
      exit 1
      ;;
    esac
  done

  # Validate type‑specific required fields
  if [[ "$download_type" == "url" ]]; then
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
      print_error "No URLs provided for type=url."
      exit 1
    fi
  elif [[ "$download_type" == "mhtml" ]]; then
    if [[ -z "$urls" && -z "$urls_file" ]]; then
      print_error "URL required for type=mhtml. Use -u or --urls."
      exit 1
    fi
    # Use first URL from either source
    if [[ -n "$urls_file" ]]; then
      final_urls=$(head -n1 "$urls_file")
    else
      final_urls=$(echo "$urls" | cut -d',' -f1)
    fi
  elif [[ "$download_type" == "googleplay" ]]; then
    if [[ -z "$package_name" ]]; then
      print_error "Package name required for type=googleplay. Use --package-name."
      exit 1
    fi
  else
    print_error "Invalid download type: $download_type"
    exit 1
  fi

  validate_token

  # Optional reachability check (only for URL type)
  if $enable_check && [[ "$download_type" == "url" ]]; then
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
    --field download_type="$download_type"
    --field mode="$mode"
    --field split_size_mb="$split_size")

  case "$download_type" in
  url)
    CMD+=(--field urls="$final_urls")
    # YouTube fields (only if YouTube URLs present)
    if echo "$final_urls" | grep -qE '(youtube\.com/watch\?v=|youtu\.be/)'; then
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
      if [[ "$yt_extract_audio" == "true" ]] || [[ "$quality" == "audio" ]]; then
        CMD+=(--field yt_extract_audio=true)
        CMD+=(--field yt_audio_format="$yt_audio_format")
      fi
      [[ "$yt_subs" == "true" ]] && CMD+=(--field yt_subs=true)
      [[ "$yt_embed_subs" == "true" ]] && CMD+=(--field yt_embed_subs=true)
      [[ "$yt_embed_thumbnail" == "true" ]] && CMD+=(--field yt_embed_thumbnail=true)
      [[ "$yt_remux" == "true" ]] && CMD+=(--field yt_remux=true)
      [[ -n "$playlist_items" ]] && CMD+=(--field playlist_items="$playlist_items")
      [[ "$download_subtitles" == "true" ]] && CMD+=(--field download_subtitles=true)
      [[ -n "$subtitle_langs" ]] && CMD+=(--field subtitle_langs="$subtitle_langs")
      [[ "$embed_metadata" == "true" ]] && CMD+=(--field embed_metadata=true)
      [[ "$embed_chapters" == "true" ]] && CMD+=(--field embed_chapters=true)
      [[ "$sponsorblock" == "true" ]] && CMD+=(--field sponsorblock=true)
      [[ "$use_pot" == "true" ]] && CMD+=(--field use_pot=true)
      [[ -n "$extra_args" ]] && CMD+=(--field extra_args="$extra_args")
    fi
    ;;
  mhtml)
    CMD+=(--field urls="$final_urls")
    [[ -n "$title" ]] && CMD+=(--field title="$title")
    ;;
  googleplay)
    CMD+=(--field package_name="$package_name")
    CMD+=(--field architecture="$architecture")
    CMD+=(--field merge_splits="$merge_splits")
    ;;
  esac

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
Usage: ./scripts/download.sh [OPTIONS]

General options:
  -m, --mode MODE               Mode: auto, download, download-zip (default: auto)
  -s, --split-size MB           Split size in MB (0 = never split, default: 0)
      --check                   Enable URL reachability checks
      --dry-run                 Print command without executing
  -h, --help                    This message

Type selection (default: url):
  --type TYPE                   One of: url, playlist_url, mhtml, googleplay

For --type url:
  -u, --urls "URL1,URL2"        Comma-separated URLs
  -f, --urls-file FILE          File with one URL per line
  -q, --quality QUALITY         best,1080p,720p,480p,audio
  --yt-format-spec SPEC         Overrides --quality
  --yt-extract-audio            Extract audio only
  --yt-audio-format FORMAT      mp3, m4a, opus (default mp3)
  --yt-subs                     Download subtitles
  --yt-embed-subs               Embed subtitles
  --yt-embed-thumbnail          Embed thumbnail
  --yt-remux                    Remux video
  --playlist-items ITEMS        Playlist items (e.g., 3-7, all, 1,3,5)
  --download-subs               Download separate subtitle files
  --sub-langs LANGS             Subtitle languages (comma-separated, default: en)
  --embed-metadata              Embed thumbnail + metadata (default: true)
  --embed-chapters              Embed chapter markers (default: true)
  --sponsorblock                Skip sponsor/intro/outro segments
  --use-pot                     Use PO-Token server (default: true)
  --no-pot                      Disable PO-Token server
  --extra-args "ARGS"          Extra yt-dlp arguments

For --type mhtml:
  -u, --urls URL                Single URL to archive
  --title TITLE                 Optional filename (no spaces/special chars)

For --type googleplay:
  --package-name NAME           Package name (e.g., com.google.android.youtube)
  --architecture ARCH           arm64 or armv7 (default arm64)
  --merge-splits true/false     Merge split APKs (default true)

Interactive mode: run without any options.
EOF
}
