#!/usr/bin/env bash
# Quality mapping – converts simple quality string to workflow fields
set -euo pipefail

# Given a quality string, echo the appropriate --field arguments for yt-dlp params.
# Must be called with `eval` or used to build an array.
quality_to_workflow_fields() {
  local quality="$1"
  case "$quality" in
  best)
    # default yt_format_spec is already "bestvideo+bestaudio"
    # Not sending anything means workflow will use its default
    echo ""
    ;;
  1080p | 720p | 480p | 360p | 240p | 144p)
    local height="${quality%p}"
    echo "--field yt_format_spec=bestvideo[height<=${height}]+bestaudio"
    ;;
  audio)
    echo "--field yt_extract_audio=true"
    echo "--field yt_audio_format=mp3"
    # Also set a format spec that prefers audio
    echo "--field yt_format_spec=bestaudio"
    ;;
  *)
    print_warn "Unknown quality '$quality'. Using best."
    echo ""
    ;;
  esac
}
