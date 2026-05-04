#!/usr/bin/env bash
# Interactive dispatch – sourced
set -euo pipefail

source "${SCRIPT_DIR}/lib/helpers.sh"
source "${SCRIPT_DIR}/lib/input_parsing.sh"

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

  # --- 2. Quality (only if YouTube present) ---
  local quality="best"
  local yt_csv
  yt_csv=$(extract_youtube_urls "$urls")
  if [[ -n "$yt_csv" ]]; then
    if $GUM_AVAILABLE; then
      quality=$(gum choose --header "Select video quality:" "best" "1080p" "720p" "480p" "audio")
    else
      echo ""
      echo "Select quality:"
      echo "  1) best"
      echo "  2) 1080p"
      echo "  3) 720p"
      echo "  4) 480p"
      echo "  5) audio"
      local c
      while :; do
        read -rp "Choice (1-5): " c
        case "$c" in
        1)
          quality="best"
          break
          ;;
        2)
          quality="1080p"
          break
          ;;
        3)
          quality="720p"
          break
          ;;
        4)
          quality="480p"
          break
          ;;
        5)
          quality="audio"
          break
          ;;
        *) echo "Invalid – try again" ;;
        esac
      done
    fi
  else
    print_success "No YouTube URLs – using default quality (best)."
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
  echo "  │ Quality:        $quality"
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
    --field quality="$quality"
    --field mode="$mode"
    --field split_size_mb="$split_size")
  if [[ -n "$cookies" && -f "$cookies" ]]; then
    CMD+=(--field cookies="$(cat "$cookies")")
  fi

  print_success "Dispatching..."
  "${CMD[@]}" &
  spinner $! "Dispatching workflow..."
  wait $!
  print_success "Done! Track: https://github.com/$repo/actions"
}
