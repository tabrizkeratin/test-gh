#!/usr/bin/env bash
# Interactive dispatch – sourced
set -euo pipefail

source "${SCRIPT_DIR}/lib/helpers.sh"
source "${SCRIPT_DIR}/lib/input_parsing.sh"
source "${SCRIPT_DIR}/lib/quality_map.sh"

run_interactive() {
  check_gh_async &
  local bg_pid=$!

  validate_token
  local repo

  print_header

  # --- 0. Select download type ---
  local download_type="url"
  if $GUM_AVAILABLE; then
    download_type=$(gum choose --header "What do you want to download?" \
      "URL (direct or YouTube)" \
      "MHTML (webpage archive)" \
      "Google Play APK")
    case "$download_type" in
    "URL (direct or YouTube)") download_type="url" ;;
    "MHTML (webpage archive)") download_type="mhtml" ;;
    "Google Play APK") download_type="googleplay" ;;
    esac
  else
    echo ""
    echo "Select download type:"
    echo "  1) URL (direct or YouTube)"
    echo "  2) MHTML (webpage archive)"
    echo "  3) Google Play APK"
    read -rp "Choice (1-3): " dt
    case "$dt" in
    2) download_type="mhtml" ;;
    3) download_type="googleplay" ;;
    *) download_type="url" ;;
    esac
  fi

  # --- Common defaults ---
  local mode="${DEFAULT_MODE:-auto}"
  local split_size="${DEFAULT_SPLIT_MB:-95}"
  local cookies="${DEFAULT_COOKIES:-}"

  # --- Variables for specific types ---
  local urls="" title="" package_name="" architecture="arm64" merge_splits=true

  case "$download_type" in
  url)
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

    # --- YouTube specific options (only if YouTube URLs present) ---
    local quality="best"
    local yt_format_spec="" yt_extract_audio=false yt_audio_format="mp3"
    local yt_subs="" yt_embed_subs=false yt_embed_thumbnail=false yt_remux=false

    local yt_csv
    yt_csv=$(extract_youtube_urls "$urls")
    if [[ -n "$yt_csv" ]]; then
      if $GUM_AVAILABLE; then
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
          [[ -z "$yt_format_spec" ]] && yt_format_spec="bestvideo+bestaudio"
        fi

        if gum confirm "Add subtitles?"; then
          yt_subs=$(gum input --placeholder "Language codes: en,fr,de" --value="")
          if [[ -n "$yt_subs" ]] && gum confirm "Embed subtitles?"; then
            yt_embed_subs=true
          fi
        fi
        gum confirm "Embed thumbnail?" && yt_embed_thumbnail=true
        gum confirm "Remux video (ffmpeg copy)?" && yt_remux=true
      else
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
    ;;

  mhtml)
    # MHTML: single URL, optional title
    urls=$(collect_urls_interactive) # only first URL matters, but we'll use as is
    if $GUM_AVAILABLE; then
      title=$(gum input --placeholder "Optional title (no spaces/special chars)" --value="")
    else
      read -rp "Optional title for the MHTML file (no spaces/special chars): " title
    fi
    ;;

  googleplay)
    # Google Play: package name, architecture, merge splits
    if $GUM_AVAILABLE; then
      package_name=$(gum input --placeholder "Package name (e.g., com.google.android.youtube)")
      architecture=$(gum choose --header "Architecture" "arm64" "armv7")
      merge_splits=$(gum confirm "Merge split APKs into single installable APK?" && echo true || echo false)
    else
      read -rp "Package name: " package_name
      read -rp "Architecture (arm64/armv7): " architecture
      read -rp "Merge split APKs? (y/n): " ms
      merge_splits=$([[ $ms =~ ^[Yy]$ ]] && echo true || echo false)
    fi
    ;;
  esac

  # --- Summary & confirm ---
  echo ""
  echo "  ╭──────────── Review ───────────╮"
  echo "  │ Type:           $download_type"
  case "$download_type" in
  url)
    local yt_count=0
    if [[ -n "$yt_csv" ]]; then
      yt_count=$(echo "$yt_csv" | tr ',' '\n' | grep -c . || true)
    fi
    local total_count
    total_count=$(echo "$urls" | tr ',' '\n' | grep -c .)
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
    ;;
  mhtml)
    echo "  │ URL:            $urls"
    [[ -n "$title" ]] && echo "  │ Title:          $title"
    ;;
  googleplay)
    echo "  │ Package:        $package_name"
    echo "  │ Architecture:   $architecture"
    echo "  │ Merge splits:   $merge_splits"
    ;;
  esac
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

  # --- Build and dispatch ---
  check_gh_async_wait $bg_pid
  repo=$(get_repo)

  CMD=(gh workflow run download-url.yml --repo "$repo"
    --field token="$DOWNLOAD_TOKEN"
    --field download_type="$download_type"
    --field mode="$mode"
    --field split_size_mb="$split_size")

  case "$download_type" in
  url)
    CMD+=(--field urls="$urls")
    if [[ -n "$yt_csv" ]]; then
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
      if [[ -n "$yt_subs" ]]; then
        CMD+=(--field yt_subs="$yt_subs")
        [[ "$yt_embed_subs" == "true" ]] && CMD+=(--field yt_embed_subs=true)
      fi
      [[ "$yt_embed_thumbnail" == "true" ]] && CMD+=(--field yt_embed_thumbnail=true)
      [[ "$yt_remux" == "true" ]] && CMD+=(--field yt_remux=true)
    fi
    ;;
  mhtml)
    CMD+=(--field urls="$urls")
    [[ -n "$title" ]] && CMD+=(--field title="$title")
    ;;
  googleplay)
    CMD+=(--field package_name="$package_name")
    CMD+=(--field architecture="$architecture")
    CMD+=(--field merge_splits="$merge_splits")
    ;;
  esac

  if [[ -n "$cookies" && -f "$cookies" ]]; then
    CMD+=(--field cookies="$(cat "$cookies")")
  fi

  print_success "Dispatching..."
  "${CMD[@]}" &
  spinner $! "Dispatching workflow..."
  wait $!
  print_success "Done! Track: https://github.com/$repo/actions"
}
