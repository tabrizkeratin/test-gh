#!/usr/bin/env bash
# Interactive dispatch – sourced
set -euo pipefail

source "${SCRIPT_DIR}/lib/helpers.sh"
source "${SCRIPT_DIR}/lib/input_parsing.sh"
source "${SCRIPT_DIR}/lib/quality_map.sh"

run_interactive() {
  check_gh
  validate_token
  local repo
  repo=$(get_repo)

  print_header

  # --- 1. How to provide URLs ---
  local method
  if $GUM_AVAILABLE; then
    method=$(gum choose --header "How to provide URLs?" "Paste now" "Load from file")
  else
    echo "How to provide URLs?"
    echo "  1) Paste now"
    echo "  2) Load from file"
    read -rp "Choice (1/2): " method
    case "$method" in
    1 | "Paste now" | "paste") method="Paste now" ;;
    2 | "Load from file" | "file") method="Load from file" ;;
    *)
      print_error "Invalid choice"
      exit 1
      ;;
    esac
  fi

  local urls
  case "$method" in
  "Paste now") urls=$(collect_urls_interactive) ;;
  "Load from file")
    local f
    if $GUM_AVAILABLE; then
      f=$(gum file --file --height 10)
    else
      read -rp "Path to file: " f
    fi
    urls=$(collect_urls_from_file "$f")
    ;;
  esac

  # --- 2. Quality & YouTube options ---
  local quality="best"
  local yt_format_spec="" yt_extract_audio=false yt_audio_format="mp3"
  local yt_subs="" yt_embed_subs=false yt_embed_thumbnail=false yt_remux=false

  local yt_csv
  yt_csv=$(extract_youtube_urls "$urls")
  if [[ -n "$yt_csv" ]]; then
    if $GUM_AVAILABLE; then
      # Choose simple quality or custom format spec?
      local advanced
      advanced=$(gum choose --header "YouTube setup:" "Simple quality preset" "Custom yt-dlp format spec")
      if [[ "$advanced" == "Simple quality preset" ]]; then
        quality=$(gum choose --header "Select video quality:" "best" "1080p" "720p" "480p" "360p" "audio")
        if [[ "$quality" == "audio" ]]; then
          yt_extract_audio=true
          yt_audio_format=$(gum choose --header "Audio format:" "mp3" "m4a" "opus")
        fi
      else
        yt_format_spec=$(gum input --placeholder 'Example: "bestvideo[height<=720]+bestaudio"' --value="")
        # If format spec is empty, fall back to best
        [[ -z "$yt_format_spec" ]] && yt_format_spec="bestvideo+bestaudio"
      fi

      # Extra options (subtitles, thumbnail, remux)
      if gum confirm "Add subtitles?"; then
        yt_subs=$(gum input --placeholder "Language codes: en,fr,de" --value="")
        if [[ -n "$yt_subs" ]] && gum confirm "Embed subtitles?"; then
          yt_embed_subs=true
        fi
      fi
      gum confirm "Embed thumbnail?" && yt_embed_thumbnail=true
      gum confirm "Remux video (ffmpeg copy)?" && yt_remux=true
    else
      # Plain read fallback
      echo ""
      echo "YouTube setup (press Enter to skip):"
      read -rp "Use custom yt-dlp format spec? (leave blank for simple quality): " fmt
      if [[ -n "$fmt" ]]; then
        yt_format_spec="$fmt"
      else
        echo "Select quality: best, 1080p, 720p, 480p, 360p, audio"
        read -rp "Quality [best]: " qual
        quality="${qual:-best}"
        if [[ "$quality" == "audio" ]]; then
          yt_extract_audio=true
          read -rp "Audio format (mp3/m4a/opus) [mp3]: " af
          yt_audio_format="${af:-mp3}"
        fi
      fi

      read -rp "Subtitle languages (comma, e.g., en,fr): " yt_subs
      if [[ -n "$yt_subs" ]]; then
        read -rp "Embed subtitles? (y/n): " emb
        [[ "$emb" =~ ^[Yy]$ ]] && yt_embed_subs=true
      fi
      read -rp "Embed thumbnail? (y/n): " thumb
      [[ "$thumb" =~ ^[Yy]$ ]] && yt_embed_thumbnail=true
      read -rp "Remux? (y/n): " rem
      [[ "$rem" =~ ^[Yy]$ ]] && yt_remux=true
    fi
  else
    print_success "No YouTube URLs – quality settings ignored."
  fi

  # --- 3. Defaults for mode/split/cookies ---
  local mode="${DEFAULT_MODE:-auto}"
  local split_size="${DEFAULT_SPLIT_MB:-95}"
  local cookies="${DEFAULT_COOKIES:-}"

  # --- 4. Summary & confirm ---
  local yt_count
  yt_count=$(echo "$yt_csv" | tr ',' '\n' | grep -c . || true)
  local total_count
  total_count=$(echo "$urls" | tr ',' '\n' | grep -c .)
  echo ""
  echo "  ╭──────────── Review ───────────╮"
  echo "  │ Total URLs:     $total_count"
  echo "  │ YouTube URLs:   $yt_count"
  if [[ -n "$yt_format_spec" ]]; then
    echo "  │ Format spec:    $yt_format_spec"
  else
    echo "  │ Quality:        $quality"
  fi
  [[ "$yt_extract_audio" == "true" ]] && echo "  │ Audio only:     yes (format $yt_audio_format)"
  [[ -n "$yt_subs" ]] && echo "  │ Subtitles:      $yt_subs (embed: $yt_embed_subs)"
  [[ "$yt_embed_thumbnail" == "true" ]] && echo "  │ Embed thumbnail: yes"
  [[ "$yt_remux" == "true" ]] && echo "  │ Remux:          yes"
  echo "  │ Mode:           $mode"
  echo "  │ Split size:     $split_size MB"
  echo "  │ Cookies:        $([[ -n "$cookies" ]] && echo "$cookies" || echo "none")"
  echo "  │ Token:          ********"
  echo "  ╰────────────────────────────────╯"
  echo ""

  local proceed=true
  if $GUM_AVAILABLE; then
    gum confirm "Proceed?" || proceed=false
  else
    read -rp "Proceed? [Y/n] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || proceed=false
  fi
  $proceed || exit 0

  # --- 5. Dispatch ---
  CMD=(gh workflow run download-url.yml --repo "$repo"
    --field token="$DOWNLOAD_TOKEN"
    --field urls="$urls"
    --field mode="$mode"
    --field split_size_mb="$split_size")

  if [[ -n "$yt_csv" ]]; then
    # Format spec: custom or from quality mapping
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

    # Audio extraction
    if [[ "$yt_extract_audio" == "true" ]] || [[ "$quality" == "audio" ]]; then
      CMD+=(--field yt_extract_audio=true)
      CMD+=(--field yt_audio_format="$yt_audio_format")
    fi

    # Subtitles
    if [[ -n "$yt_subs" ]]; then
      CMD+=(--field yt_subs="$yt_subs")
      if [[ "$yt_embed_subs" == "true" ]]; then
        CMD+=(--field yt_embed_subs=true)
      fi
    fi

    # Thumbnail & remux
    [[ "$yt_embed_thumbnail" == "true" ]] && CMD+=(--field yt_embed_thumbnail=true)
    [[ "$yt_remux" == "true" ]] && CMD+=(--field yt_remux=true)
  fi

  if [[ -n "$cookies" && -f "$cookies" ]]; then
    CMD+=(--field cookies="$(cat "$cookies")")
  fi

  print_success "Dispatching..."
  "${CMD[@]}" &
  spinner $! "Dispatching workflow..."
  wait $!
  print_success "Done! Track: https://github.com/$repo/actions"
}
