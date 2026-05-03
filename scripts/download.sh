#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Direct link & YouTube downloader - local dispatcher
# ------------------------------------------------------------

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

# Default values
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

# Parse command line
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
  --help)
    cat <<EOF
Usage: $0 [options] <URL> [URL...]

Options:
  --mode <auto|download|download-zip>   default auto
  --split-size <MB>                     split files larger than this, 0 = never (default 90)
  --commit-msg <msg>                    custom commit message

YouTube-specific:
  --yt-quality <best|1080p|720p|480p|audio|height>   default best
  --yt-fps <30|60>                      limit frame rate
  --yt-extract-audio                    extract audio only
  --yt-audio-format <mp3|m4a|opus>      default mp3
  --yt-subs <lang1,lang2>               download subtitles (e.g. en,fr)
  --yt-embed-subs                       embed subtitles into file
  --yt-embed-thumbnail                  embed thumbnail
  --yt-remux                            remux video for better compatibility

Environment variables (can be set in .env):
  ALLOWED_DOMAINS, DOWNLOAD_TOKEN, SPLIT_SIZE, COMMIT_MSG
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

if [[ ${#URLS[@]} -eq 0 ]]; then
  echo "Error: No URLs provided"
  exit 1
fi

# Auto-detect mode
if [[ "$MODE" == "auto" ]]; then
  if [[ ${#URLS[@]} -eq 1 ]]; then
    MODE="download"
  else
    MODE="download-zip"
  fi
fi

# Validate token
if [[ -z "$DOWNLOAD_TOKEN" ]]; then
  echo "Error: DOWNLOAD_TOKEN not set in .env or environment"
  exit 1
fi

# Build yt-dlp format spec from user-friendly options
build_yt_format_spec() {
  local quality="$1"
  local fps="$2"
  local extract_audio="$3"

  if [[ "$extract_audio" == "true" ]]; then
    echo "bestaudio/best"
    return
  fi

  case "$quality" in
  best)
    echo "bestvideo+bestaudio/best"
    ;;
  1080p)
    echo "bestvideo[height<=1080]+bestaudio/best[height<=1080]"
    ;;
  720p)
    echo "bestvideo[height<=720]+bestaudio/best[height<=720]"
    ;;
  480p)
    echo "bestvideo[height<=480]+bestaudio/best[height<=480]"
    ;;
  audio)
    echo "bestaudio/best"
    ;;
  *)
    if [[ "$quality" =~ ^[0-9]+$ ]]; then
      if [[ -n "$fps" ]]; then
        echo "bestvideo[height<=$quality][fps<=$fps]+bestaudio/best[height<=$quality][fps<=$fps]"
      else
        echo "bestvideo[height<=$quality]+bestaudio/best[height<=$quality]"
      fi
    else
      # raw format string
      echo "$quality"
    fi
    ;;
  esac
}

YT_FORMAT_SPEC=$(build_yt_format_spec "$YT_QUALITY" "$YT_FPS" "$YT_EXTRACT_AUDIO" "$YT_AUDIO_FORMAT")

# Prepare URLs string (space separated)
URLS_STR="${URLS[*]}"

# Dispatch workflow
echo "Dispatching workflow with ${#URLS[@]} URL(s)..."
echo "Mode: $MODE"
echo "Split size: ${SPLIT_SIZE}MB"
echo "YT format spec: $YT_FORMAT_SPEC"

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

echo "Workflow triggered. Check progress at:"
echo "https://github.com/$(git config --get remote.origin.url | sed 's/.*:\(.*\)\.git/\1/')/actions"
