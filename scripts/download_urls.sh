#!/usr/bin/env bash
set -euo pipefail

# === defaults ===
FORMAT_SPEC="bestvideo+bestaudio/best"
EXTRACT_AUDIO="false"
AUDIO_FORMAT="mp3"
SUBS="false"
EMBED_SUBS="false"
EMBED_THUMBNAIL="false"
REMUX="false"
COOKIES_FILE=""
PLAYLIST_ITEMS=""
DOWNLOAD_SUBS="false"
SUB_LANGS="en"
EMBED_META="false"
EMBED_CHAPTERS="false"
SPONSORBLOCK="false"
EXTRA_ARGS=""
USE_POT="false"
NO_PLAYLIST=true

# === argument parsing ===
while [[ $# -gt 0 ]]; do
  case "$1" in
    --urls)            URLS="$2"; shift 2 ;;
    --format-spec)     FORMAT_SPEC="$2"; shift 2 ;;
    --extract-audio)   EXTRACT_AUDIO="$2"; shift 2 ;;
    --audio-format)    AUDIO_FORMAT="$2"; shift 2 ;;
    --subs)            SUBS="$2"; shift 2 ;;
    --embed-subs)      EMBED_SUBS="$2"; shift 2 ;;
    --embed-thumbnail) EMBED_THUMBNAIL="$2"; shift 2 ;;
    --remux)           REMUX="$2"; shift 2 ;;
    --cookies)         COOKIES_FILE="$2"; shift 2 ;;
    --playlist-items)  PLAYLIST_ITEMS="$2"; shift 2 ;;
    --download-subs)   DOWNLOAD_SUBS="$2"; shift 2 ;;
    --sub-langs)       SUB_LANGS="$2"; shift 2 ;;
    --embed-metadata)  EMBED_META="$2"; shift 2 ;;
    --embed-chapters)  EMBED_CHAPTERS="$2"; shift 2 ;;
    --sponsorblock)    SPONSORBLOCK="$2"; shift 2 ;;
    --extra-args)      EXTRA_ARGS="$2"; shift 2 ;;
    --po-token)        USE_POT="true"; shift ;;
    --no-playlist)     NO_PLAYLIST="true"; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "${URLS:-}" ]]; then
  echo "Error: --urls is required" >&2
  exit 1
fi

# Build yt-dlp command options
OPTS=(
  --console-title
  --progress
  --newline
)

# Default: no playlist
if [[ "$NO_PLAYLIST" == "true" && -z "$PLAYLIST_ITEMS" ]]; then
  OPTS+=( --no-playlist )
fi

# Format / audio
if [[ "$EXTRACT_AUDIO" == "true" ]]; then
  OPTS+=( -x --audio-format "$AUDIO_FORMAT" )
else
  OPTS+=( -f "$FORMAT_SPEC" --merge-output-format mp4 )
  [[ "$REMUX" == "true" ]] && OPTS+=( --remux-video mp4 )
fi

# Subtitles
if [[ "$SUBS" == "true" ]]; then
  OPTS+=( --write-subs --write-auto-subs --embed-subs )
fi
if [[ "$DOWNLOAD_SUBS" == "true" && "$SUBS" != "true" ]]; then
  OPTS+=( --write-subs --write-auto-subs --sub-langs "$SUB_LANGS" )
fi
[[ "$EMBED_SUBS" == "true" ]] && OPTS+=( --embed-subs )

# Thumbnail, metadata, chapters
[[ "$EMBED_THUMBNAIL" == "true" ]] && OPTS+=( --embed-thumbnail )
if [[ "$EMBED_META" == "true" ]]; then
  OPTS+=( --embed-thumbnail --embed-metadata --add-metadata )
fi
[[ "$EMBED_CHAPTERS" == "true" ]] && OPTS+=( --embed-chapters )

# SponsorBlock
if [[ "$SPONSORBLOCK" == "true" ]]; then
  OPTS+=( --sponsorblock-remove "sponsor,intro,outro,selfpromo,interaction" )
fi

# Playlist handling
if [[ -n "$PLAYLIST_ITEMS" ]]; then
  if [[ "$PLAYLIST_ITEMS" == "all" ]]; then
    OPTS+=( --yes-playlist )
  else
    OPTS+=( --playlist-items "$PLAYLIST_ITEMS" --yes-playlist )
  fi
fi

# PO Token server-based anti‑bot
if [[ "$USE_POT" == "true" ]]; then
  OPTS+=( --extractor-args "youtube:extractor_args.po_token.server=http://localhost:4416" )
fi

# Cookies
[[ -n "$COOKIES_FILE" ]] && OPTS+=( --cookies "$COOKIES_FILE" )

# Output template
OPTS+=( -o "%(title)s [%(id)s].%(ext)s" )

# Extra args
if [[ -n "$EXTRA_ARGS" ]]; then
  IFS=' ' read -ra EXTRA <<< "$EXTRA_ARGS"
  OPTS+=( "${EXTRA[@]}" )
fi

# === Download each URL ===
IFS=',' read -ra URL_ARRAY <<< "$URLS"
for url in "${URL_ARRAY[@]}"; do
  url="$(echo "$url" | xargs)"
  [[ -z "$url" ]] && continue
  echo "Downloading: $url"
  yt-dlp "${OPTS[@]}" "$url"
done