#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load .env if present
if [[ -f ".env" ]]; then
  set -a
  source .env
  set +a
elif [[ -f "../.env" ]]; then
  set -a
  source ../.env
  set +a
fi

# Defaults
MODE="auto"
SPLIT_SIZE="${SPLIT_SIZE:-90}"
ALLOWED_DOMAINS="${ALLOWED_DOMAINS:-*}"
DOWNLOAD_TOKEN="${DOWNLOAD_TOKEN:-}"
COMMIT_MSG="${COMMIT_MSG:-Add downloaded files}"

# yt-dlp defaults
YT_QUALITY="best"
YT_FPS=""
YT_EXTRACT_AUDIO="false"
YT_AUDIO_FORMAT="mp3"
YT_SUBS=""
YT_EMBED_SUBS="false"
YT_EMBED_THUMBNAIL="false"
YT_REMUX="false"

INTERACTIVE=false
ADVANCED=false

# Parse arguments
URLS=()
while [[ $# -gt 0 ]]; do
  case $1 in
  --mode)
    MODE="$2"
    shift 2
    ;;
  --split-size)
    SPLIT_SIZE="$2"
    shift 2
    ;;
  --commit-msg)
    COMMIT_MSG="$2"
    shift 2
    ;;
  --yt-quality)
    YT_QUALITY="$2"
    shift 2
    ;;
  --yt-fps)
    YT_FPS="$2"
    shift 2
    ;;
  --yt-extract-audio)
    YT_EXTRACT_AUDIO="true"
    shift
    ;;
  --yt-audio-format)
    YT_AUDIO_FORMAT="$2"
    shift 2
    ;;
  --yt-subs)
    YT_SUBS="$2"
    shift 2
    ;;
  --yt-embed-subs)
    YT_EMBED_SUBS="true"
    shift
    ;;
  --yt-embed-thumbnail)
    YT_EMBED_THUMBNAIL="true"
    shift
    ;;
  --yt-remux)
    YT_REMUX="true"
    shift
    ;;
  --interactive)
    INTERACTIVE=true
    shift
    ;;
  --advanced)
    ADVANCED=true
    INTERACTIVE=true
    shift
    ;;
  --help)
    cat <<EOF
Usage: $0 [options] <URL> [URL...]

Options:
  --mode <auto|download|download-zip>
  --split-size <MB>
  --commit-msg <msg>

YouTube:
  --yt-quality <best|1080p|720p|480p|audio|height|formatID>   e.g., 135+251
  --yt-fps <30|60>
  --yt-extract-audio
  --yt-audio-format <mp3|m4a|opus>
  --yt-subs <lang1,lang2>
  --yt-embed-subs
  --yt-embed-thumbnail
  --yt-remux

  --interactive    Simple interactive mode (URLs + quality)
  --advanced       Full interactive mode (all options)

Environment: DOWNLOAD_TOKEN (required), ALLOWED_DOMAINS, SPLIT_SIZE, COMMIT_MSG
EOF
    exit 0
    ;;
  -*)
    echo "Unknown option: $1"
    exit 1
    ;;
  *)
    URLS+=("$1")
    shift
    ;;
  esac
done

# ------------------------------------------------------------------
# Interactive Mode
# ------------------------------------------------------------------
if [[ "$INTERACTIVE" == "true" ]] || [[ ${#URLS[@]} -eq 0 ]]; then
  echo "========================================="
  echo "  Download Assistant"
  echo "========================================="

  # 1. URLs
  echo "Enter URLs (one per line, empty line to finish):"
  while IFS= read -r line; do
    [[ -z "$line" ]] && break
    URLS+=("$line")
  done
  if [[ ${#URLS[@]} -eq 0 ]]; then
    echo "No URLs provided. Exiting."
    exit 1
  fi

  # 2. Quality – simplified
  echo ""
  echo "Quality / format (examples: best, 1080p, 720p, audio, 135+251, 137+140):"
  read -rp "→ " input_quality
  if [[ -n "$input_quality" ]]; then
    YT_QUALITY="$input_quality"
  fi

  # If raw format like 135+251 (contains + or digits only), treat as raw format ID
  if [[ "$YT_QUALITY" =~ ^[0-9+]+$ ]] || [[ "$YT_QUALITY" =~ ^[0-9]+\+[0-9]+$ ]]; then
    # raw format ID – no transformation needed
    YT_FORMAT_SPEC="$YT_QUALITY"
  else
    # convert preset to yt-dlp filter
    case "$YT_QUALITY" in
    best) YT_FORMAT_SPEC="bestvideo+bestaudio/best" ;;
    1080p) YT_FORMAT_SPEC="bestvideo[height<=1080]+bestaudio/best[height<=1080]" ;;
    720p) YT_FORMAT_SPEC="bestvideo[height<=720]+bestaudio/best[height<=720]" ;;
    480p) YT_FORMAT_SPEC="bestvideo[height<=480]+bestaudio/best[height<=480]" ;;
    audio) YT_FORMAT_SPEC="bestaudio/best" ;;
    *) YT_FORMAT_SPEC="$YT_QUALITY" ;; # custom height or unknown
    esac
  fi

  # 3. Advanced mode – more prompts
  if [[ "$ADVANCED" == "true" ]]; then
    echo ""
    echo "--- Advanced settings ---"
    read -rp "Mode (auto/download/download-zip) [$MODE]: " m
    [[ -n "$m" ]] && MODE="$m"
    read -rp "Split files larger than (MB, 0=never) [$SPLIT_SIZE]: " s
    [[ -n "$s" ]] && SPLIT_SIZE="$s"
    read -rp "Commit message [$COMMIT_MSG]: " c
    [[ -n "$c" ]] && COMMIT_MSG="$c"

    # Check if any YouTube URL
    IS_YT=false
    for url in "${URLS[@]}"; do
      if echo "$url" | grep -Eq '(youtube\.com/watch\?v=|youtu\.be/)'; then
        IS_YT=true
        break
      fi
    done
    if [[ "$IS_YT" == "true" ]]; then
      read -rp "Extract audio only? (y/n): " ea
      [[ "$ea" =~ ^[Yy]$ ]] && YT_EXTRACT_AUDIO="true"
      if [[ "$YT_EXTRACT_AUDIO" == "true" ]]; then
        read -rp "Audio format (mp3/m4a/opus) [$YT_AUDIO_FORMAT]: " af
        [[ -n "$af" ]] && YT_AUDIO_FORMAT="$af"
      fi
      read -rp "Subtitles (comma langs or 'none'): " subs
      if [[ -n "$subs" && "$subs" != "none" ]]; then
        YT_SUBS="$subs"
        read -rp "Embed subtitles? (y/n): " emb
        [[ "$emb" =~ ^[Yy]$ ]] && YT_EMBED_SUBS="true"
      fi
      read -rp "Embed thumbnail? (y/n): " thumb
      [[ "$thumb" =~ ^[Yy]$ ]] && YT_EMBED_THUMBNAIL="true"
      read -rp "Remux (fix compatibility)? (y/n): " rem
      [[ "$rem" =~ ^[Yy]$ ]] && YT_REMUX="true"
    fi
  fi

  # 4. Show the command that will be used (for the first URL as example)
  FIRST_URL="${URLS[0]}"
  if echo "$FIRST_URL" | grep -Eq '(youtube\.com/watch\?v=|youtu\.be/)'; then
    CMD="yt-dlp --no-mtime -f '$YT_FORMAT_SPEC'"
    [[ "$YT_EXTRACT_AUDIO" == "true" ]] && CMD="$CMD --extract-audio --audio-format $YT_AUDIO_FORMAT"
    [[ -n "$YT_SUBS" ]] && CMD="$CMD --write-subs --sub-langs $YT_SUBS"
    [[ "$YT_EMBED_SUBS" == "true" ]] && CMD="$CMD --embed-subs"
    [[ "$YT_EMBED_THUMBNAIL" == "true" ]] && CMD="$CMD --embed-thumbnail"
    echo ""
    echo "🔧 Command that will run on GitHub runner:"
    echo "   $CMD \"$FIRST_URL\""
  else
    echo ""
    echo "🔧 Command: aria2c --max-connection-per-server=16 ... \"$FIRST_URL\""
  fi

  echo ""
  read -rp "Dispatch this workflow to GitHub Actions? (Y/n): " dispatch
  if [[ "$dispatch" =~ ^[Nn]$ ]]; then
    echo "Aborted. You can copy the command and run locally if you have yt-dlp/aria2c installed."
    exit 0
  fi
fi

# ------------------------------------------------------------------
# Build final format spec (again, in case non-interactive)
# ------------------------------------------------------------------
build_yt_format_spec() {
  local q="$1"
  if [[ "$q" =~ ^[0-9+]+$ ]] || [[ "$q" =~ ^[0-9]+\+[0-9]+$ ]]; then
    echo "$q"
    return
  fi
  case "$q" in
  best) echo "bestvideo+bestaudio/best" ;;
  1080p) echo "bestvideo[height<=1080]+bestaudio/best[height<=1080]" ;;
  720p) echo "bestvideo[height<=720]+bestaudio/best[height<=720]" ;;
  480p) echo "bestvideo[height<=480]+bestaudio/best[height<=480]" ;;
  audio) echo "bestaudio/best" ;;
  *) echo "$q" ;;
  esac
}
YT_FORMAT_SPEC=$(build_yt_format_spec "$YT_QUALITY")

# Validate token
if [[ -z "$DOWNLOAD_TOKEN" ]]; then
  echo "Error: DOWNLOAD_TOKEN not set. Create a .env file or export it."
  exit 1
fi

# Dispatch
URLS_STR="${URLS[*]}"
echo "Dispatching workflow with ${#URLS[@]} URL(s)..."
gh workflow run download-url.yml \
  -f urls="$URLS_STR" \
  -f mode="$MODE" \
  -f split_size_mb="$SPLIT_SIZE" \
  -f token="$DOWNLOAD_TOKEN" \
  -f yt_format_spec="$YT_FORMAT_SPEC" \
  -f yt_extract_audio="$YT_EXTRACT_AUDIO" \
  -f yt_audio_format="$YT_AUDIO_FORMAT" \
  -f yt_subs="$YT_SUBS" \
  -f yt_embed_subs="$YT_EMBED_SUBS" \
  -f yt_embed_thumbnail="$YT_EMBED_THUMBNAIL" \
  -f yt_remux="$YT_REMUX"

echo "✅ Workflow triggered. Progress:"
echo "https://github.com/$(git config --get remote.origin.url | sed 's/.*:\(.*\)\.git/\1/')/actions"
