#!/usr/bin/env bash
set -euo pipefail

# === Helper functions ===
ask_bool() {
  local prompt="$1" default="$2"
  local yn
  read -p "$prompt [y/N] " yn
  case "${yn:-$default}" in
    [Yy]*) echo "true" ;;
    *) echo "false" ;;
  esac
}

ask() {
  local prompt="$1" default="$2"
  read -p "$prompt [$default]: " val
  echo "${val:-$default}"
}

# === Gather input ===
echo "=== YouTube Downloader (local) ==="
URLS=$(ask "YouTube URL(s) (comma separated)" "")
if [[ -z "$URLS" ]]; then
  echo "No URL provided." >&2
  exit 1
fi

FORMAT=$(ask "Format spec (e.g. bestvideo[height<=1080]+bestaudio/best)" "bestvideo+bestaudio/best")
EXTRACT_AUDIO=$(ask_bool "Extract audio only?" "n")
AUDIO_FMT="mp3"
[[ "$EXTRACT_AUDIO" == "true" ]] && AUDIO_FMT=$(ask "Audio format" "mp3")

REMUX="false"
if [[ "$EXTRACT_AUDIO" != "true" ]]; then
  REMUX=$(ask_bool "Force remux to mp4?" "n")
fi

OLD_SUBS=$(ask_bool "Download subtitles (old style, embed)?" "n")
SUBS="false"; EMBED_SUBS="false"
if [[ "$OLD_SUBS" == "true" ]]; then
  SUBS="true"; EMBED_SUBS="true"
else
  SUBS="false"
  EMBED_SUBS=$(ask_bool "Embed subtitles?" "n")
fi
DOWNLOAD_SUBS=$(ask_bool "Download separate subtitle files?" "n")
SUB_LANGS="en"
[[ "$DOWNLOAD_SUBS" == "true" ]] && SUB_LANGS=$(ask "Subtitle languages (comma separated)" "en")

EMBED_THUMBNAIL=$(ask_bool "Embed thumbnail?" "n")
EMBED_META=$(ask_bool "Embed metadata & thumbnail?" "y")
EMBED_CHAPTERS=$(ask_bool "Embed chapters?" "y")
SPONSORBLOCK=$(ask_bool "Skip sponsor segments?" "n")

PLAYLIST_ITEMS=""
NO_PLAYLIST="true"
if [[ "$URLS" != *","* ]]; then
  IS_PLAYLIST=$(ask_bool "Is this a playlist URL?" "n")
  if [[ "$IS_PLAYLIST" == "true" ]]; then
    PLAYLIST_ITEMS=$(ask "Playlist items (all, 3-7, 1,3,5) or leave empty for entire playlist" "")
    [[ -z "$PLAYLIST_ITEMS" ]] && PLAYLIST_ITEMS="all"
    NO_PLAYLIST="false"
  fi
fi

USE_POT=$(ask_bool "Use PO‑Token bot evasion? (requires 'bgutil-ytdlp-pot-provider' installed)" "y")
EXTRA_ARGS=$(ask "Any extra yt-dlp arguments?" "")

COOKIES_FILE=""
HAVE_COOKIES=$(ask_bool "Do you have a cookies.txt file?" "n")
if [[ "$HAVE_COOKIES" == "true" ]]; then
  COOKIES_FILE=$(ask "Path to cookies.txt" "cookies.txt")
fi

# === Build command ===
CMD=(yt-dlp --console-title --progress --newline)

# Playlist default
[[ "$NO_PLAYLIST" == "true" && -z "$PLAYLIST_ITEMS" ]] && CMD+=( --no-playlist )

if [[ "$EXTRACT_AUDIO" == "true" ]]; then
  CMD+=( -x --audio-format "$AUDIO_FMT" )
else
  CMD+=( -f "$FORMAT" --merge-output-format mp4 )
  [[ "$REMUX" == "true" ]] && CMD+=( --remux-video mp4 )
fi

[[ "$SUBS" == "true" ]] && CMD+=( --write-subs --write-auto-subs --embed-subs )
[[ "$DOWNLOAD_SUBS" == "true" && "$SUBS" != "true" ]] && CMD+=( --write-subs --write-auto-subs --sub-langs "$SUB_LANGS" )
[[ "$EMBED_SUBS" == "true" && "$SUBS" != "true" ]] && CMD+=( --embed-subs )
[[ "$EMBED_THUMBNAIL" == "true" ]] && CMD+=( --embed-thumbnail )
if [[ "$EMBED_META" == "true" ]]; then
  CMD+=( --embed-thumbnail --embed-metadata --add-metadata )
fi
[[ "$EMBED_CHAPTERS" == "true" ]] && CMD+=( --embed-chapters )
[[ "$SPONSORBLOCK" == "true" ]] && CMD+=( --sponsorblock-remove "sponsor,intro,outro,selfpromo,interaction" )

# Playlist
if [[ -n "$PLAYLIST_ITEMS" ]]; then
  if [[ "$PLAYLIST_ITEMS" == "all" ]]; then
    CMD+=( --yes-playlist )
  else
    CMD+=( --playlist-items "$PLAYLIST_ITEMS" --yes-playlist )
  fi
fi

# PO Token (Python provider uses auto-discovery)
if [[ "$USE_POT" == "true" ]]; then
  CMD+=( --extractor-args "youtube:po_token=web" )
fi

[[ -n "$COOKIES_FILE" ]] && CMD+=( --cookies "$COOKIES_FILE" )
CMD+=( -o "%(title)s [%(id)s].%(ext)s" )

if [[ -n "$EXTRA_ARGS" ]]; then
  IFS=' ' read -ra EXTRA <<< "$EXTRA_ARGS"
  CMD+=( "${EXTRA[@]}" )
fi

# Split URLs
IFS=',' read -ra URL_ARRAY <<< "$URLS"
for url in "${URL_ARRAY[@]}"; do url=$(echo "$url" | xargs); [[ -n "$url" ]] && echo "Will download: $url"; done

echo ""
echo "Command to run:"
echo "${CMD[@]}"
read -p "Proceed? [Y/n] " go
go="${go:-y}"
if [[ "$go" =~ ^[Yy] ]]; then
  for url in "${URL_ARRAY[@]}"; do
    url="$(echo "$url" | xargs)"
    [[ -z "$url" ]] && continue
    "${CMD[@]}" "$url"
  done
else
  echo "Aborted."
fi