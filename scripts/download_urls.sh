#!/usr/bin/env bash
set -euo pipefail

# Usage: download_urls.sh --urls "url1 url2" --format-spec "bestvideo+bestaudio" --extract-audio true --audio-format mp3 --subs en --embed-subs true --embed-thumbnail true --remux true [--cookies-file file]

echo "DEBUG: All args: $@"
echo "DEBUG: Number of args: $#"

URLS=()
FORMAT_SPEC="bestvideo+bestaudio"
EXTRACT_AUDIO=false
AUDIO_FORMAT="mp3"
SUBS=""
EMBED_SUBS=false
EMBED_THUMBNAIL=false
REMUX=false
COOKIES_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --urls)
    shift
    while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
      URLS+=("$1")
      shift
    done
    ;;
  --format-spec)
    FORMAT_SPEC="$2"
    shift 2
    ;;
  --extract-audio)
    EXTRACT_AUDIO="$2"
    shift 2
    ;;
  --audio-format)
    AUDIO_FORMAT="$2"
    shift 2
    ;;
  --subs)
    SUBS="$2"
    shift 2
    ;;
  --embed-subs)
    EMBED_SUBS="$2"
    shift 2
    ;;
  --embed-thumbnail)
    EMBED_THUMBNAIL="$2"
    shift 2
    ;;
  --remux)
    REMUX="$2"
    shift 2
    ;;
  --cookies-file)
    COOKIES_FILE="$2"
    shift 2
    ;;
  *)
    echo "Unknown option: $1"
    exit 1
    ;;
  esac
done

if [[ ${#URLS[@]} -eq 0 ]]; then
  echo "Error: No URLs provided"
  exit 1
fi

for url in "${URLS[@]}"; do
  echo "Downloading: $url"
  echo "COOKIES_FILE='$COOKIES_FILE'"
  if echo "$url" | grep -qE '(youtube\.com/watch\?v=|youtu\.be/)'; then
    CMD="yt-dlp --no-progress --js-runtimes bun --remote-components ejs:npm"
    [[ -n "$COOKIES_FILE" ]] && CMD="$CMD --cookies $COOKIES_FILE"
    CMD="$CMD -f '$FORMAT_SPEC'"
    [[ "$EXTRACT_AUDIO" == "true" ]] && CMD="$CMD --extract-audio --audio-format $AUDIO_FORMAT"
    [[ -n "$SUBS" ]] && CMD="$CMD --write-subs --sub-langs $SUBS"
    [[ "$EMBED_SUBS" == "true" ]] && CMD="$CMD --embed-subs"
    [[ "$EMBED_THUMBNAIL" == "true" ]] && CMD="$CMD --embed-thumbnail"
    eval $CMD "$url"
    sleep 5
    if [[ "$REMUX" == "true" ]]; then
      for f in *.mp4 *.webm *.mkv; do
        [ -f "$f" ] && ffmpeg -i "$f" -c copy "fixed_$f" -y && mv "fixed_$f" "$f"
      done
    fi
  else
    aria2c --max-connection-per-server=16 --split=16 --min-split-size=1M \
      --console-log-level=error --summary-interval=0 \
      --out="downloaded_file_$(basename "$url")" "$url"
  fi
done
