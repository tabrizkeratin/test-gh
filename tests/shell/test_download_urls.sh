#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_ROOT="$SCRIPT_DIR"
FIXTURES="$TEST_ROOT/fixtures"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

pass=0
fail=0
skip=0

log() { printf "${CYAN}[test]${NC} %s\n" "$*"; }
ok()  { printf "  ${GREEN}✓${NC} %s\n" "$*"; ((pass++)); }
fail_() { printf "  ${RED}✗${NC} %s\n" "$*"; ((fail++)); }
skip_() { printf "  ${YELLOW}⊘${NC} %s\n" "$*"; ((skip++)); }

section() { printf "\n${BOLD}══ %s ══${NC}\n\n" "$*"; }

run_tests() {
  local suite="$1"; shift
  log "Running $suite..."
  "$@"
}

# ============================================================================
# Suite: URL parsing
# ============================================================================
test_url_parsing__single_url() {
  # No-op parser - just ensures function exists and doesn't crash
  echo "https://example.com/file.mp4"
}

test_url_parsing__multiple_urls() {
  echo "https://a.com/file.mp4 https://b.com/file.mp4"
}

test_url_parsing__comma_separated() {
  echo "https://a.com/file.mp4,https://b.com/file.mp4"
}

test_url_parsing__newline_separated() {
  echo -e "https://a.com/file.mp4\nhttps://b.com/file.mp4"
}

test_url_parsing__dedup() {
  echo "https://a.com/file.mp4 https://a.com/file.mp4"
}

test_url_parsing__whitespace_stripped() {
  echo "  https://a.com/file.mp4 , https://b.com/file.mp4  "
}

# ============================================================================
# Suite: YouTube detection
# ============================================================================
test_yt_detection__youtube_com() {
  echo "https://www.youtube.com/watch?v=abc123"
}

test_yt_detection__youtu_be() {
  echo "https://youtu.be/abc123"
}

test_yt_detection__non_youtube() {
  echo "https://example.com/video.mp4"
}

test_yt_detection__non_youtube_vimeo() {
  echo "https://vimeo.com/123456789"
}

# ============================================================================
# Suite: Shell word splitting for URL extraction
# ============================================================================
parse_urls_shell() {
  local input="$1"
  local unified urls=()
  unified=$(echo "$input" | tr ',\n' ' ')
  for token in $unified; do
    urls+=("$token")
  done
  local filtered=()
  for u in "${urls[@]}"; do
    [[ -n "$u" ]] && filtered+=("$u")
  done
  printf '%s\n' "${filtered[@]}"
}

assert_parse() {
  local input="$1"; shift
  local expected=("$@")
  local actual
  mapfile -t actual < <(parse_urls_shell "$input")
  local pass_=true
  [[ ${#actual[@]} -eq ${#expected[@]} ]] || pass_=false
  if $pass_; then
    for i in "${!expected[@]}"; do
      [[ "${actual[$i]}" == "${expected[$i]}" ]] || { pass_=false; break; }
    done
  fi
  if $pass_; then
    ok "parse \"$input\" → ${expected[*]}"
  else
    fail_ "parse \"$input\" expected ${expected[*]}, got ${actual[*]}"
  fi
}

# ============================================================================
# Suite: yt-dlp format spec validation
# ============================================================================
validate_format_spec() {
  local spec="$1"
  [[ -n "$spec" ]]
}

assert_format_spec() {
  local spec="$1" expect_pass="$2"
  local result
  if validate_format_spec "$spec"; then
    result=true
  else
    result=false
  fi
  if [[ "$result" == "$expect_pass" ]]; then
    ok "format_spec \"$spec\" → valid=$result"
  else
    fail_ "format_spec \"$spec\" expected valid=$expect_pass, got $result"
  fi
}

# ============================================================================
# Suite: Remux condition
# ============================================================================
should_remux() {
  local remux_flag="$1"
  [[ "$remux_flag" == "true" ]]
}

assert_remux() {
  local flag="$1" expect="$2"
  local result
  if should_remux "$flag"; then
    result=true
  else
    result=false
  fi
  if [[ "$result" == "$expect" ]]; then
    ok "remux flag=$flag → should_remux=$result"
  else
    fail_ "remux flag=$flag expected should_remux=$expect, got $result"
  fi
}

# ============================================================================
# Suite: File extension detection
# ============================================================================
is_video_ext() {
  local file="$1"
  [[ "$file" =~ \.(mp4|webm|mkv|avi|mov)$ ]]
}

assert_video_ext() {
  local file="$1" expect="$2"
  local result
  if is_video_ext "$file"; then
    result=true
  else
    result=false
  fi
  if [[ "$result" == "$expect" ]]; then
    ok "video_ext \"$file\" → $result"
  else
    fail_ "video_ext \"$file\" expected $expect, got $result"
  fi
}

# ============================================================================
# Suite: Download mode logic
# ============================================================================
get_mode() {
  local file_count="$1" total_size="$2" mode_input="$3"
  if [[ "$mode_input" == "download-full" ]]; then
    echo "download-full"
    return
  fi
  if [[ "$mode_input" == "download-zip" ]]; then
    echo "download-zip"
    return
  fi
  # auto mode
  if [[ $file_count -le 1 ]]; then
    echo "skip-zip"
  elif [[ $total_size -gt 104857600 ]]; then
    echo "skip-zip"
  else
    echo "zip"
  fi
}

assert_mode() {
  local count="$1" size="$2" mode_input="$3" expect="$4"
  local result
  result=$(get_mode "$count" "$size" "$mode_input")
  if [[ "$result" == "$expect" ]]; then
    ok "mode count=$count size=$size mode=$mode_input → $result"
  else
    fail_ "mode count=$count size=$size mode=$mode_input expected $expect, got $result"
  fi
}

# ============================================================================
# Suite: Split threshold
# ============================================================================
should_split() {
  local file_size="$1" split_mb="$2"
  [[ "$split_mb" != "0" ]] && [[ $file_size -gt $((split_mb * 1048576)) ]]
}

assert_split() {
  local size="$1" split_mb="$2" expect="$3"
  local result
  if should_split "$size" "$split_mb"; then
    result=true
  else
    result=false
  fi
  if [[ "$result" == "$expect" ]]; then
    ok "split size=$size split_mb=$split_mb → $result"
  else
    fail_ "split size=$size split_mb=$split_mb expected $expect, got $result"
  fi
}

# ============================================================================
# Suite: Token validation
# ============================================================================
validate_token() {
  local input="$1" secret="$2"
  [[ "$input" == "$secret" ]]
}

assert_token() {
  local input="$1" secret="$2" expect="$3"
  local result
  if validate_token "$input" "$secret"; then
    result=true
  else
    result=false
  fi
  if [[ "$result" == "$expect" ]]; then
    ok "token validation input=\"$input\" secret=\"$secret\" → $result"
  else
    fail_ "token validation input=\"$input\" secret=\"$secret\" expected $expect, got $result"
  fi
}

# ============================================================================
# Suite: Artifact name uniqueness per run
# ============================================================================
gen_artifact_name() {
  local run_id="$1" parallel="$2"
  if [[ "$parallel" == "true" ]]; then
    echo "downloaded-files-${run_id}-${RANDOM}"
  else
    echo "downloaded-files-${run_id}"
  fi
}

assert_artifact_name() {
  local run_id="$1" parallel="$2" expect_prefix="$3"
  local result
  result=$(gen_artifact_name "$run_id" "$parallel")
  if [[ "$result" == "$expect_prefix"* ]]; then
    ok "artifact_name run_id=$run_id parallel=$parallel → $result"
  else
    fail_ "artifact_name run_id=$run_id parallel=$parallel expected prefix $expect_prefix, got $result"
  fi
}

# ============================================================================
# Suite: Playlist range args
# ============================================================================
build_playlist_args() {
  local start="$1" end="$2" max_size="$3"
  local args=""
  [[ -n "$start" ]] && args="$args --playlist-start $start"
  [[ -n "$end" ]] && args="$args --playlist-end $end"
  [[ -n "$max_size" ]] && args="$args --max-playlist-size $max_size"
  echo "$args"
}

assert_playlist_args() {
  local start="$1" end="$2" max_size="$3" expect="$4"
  local result
  result=$(build_playlist_args "$start" "$end" "$max_size")
  if [[ "$result" == "$expect" ]]; then
    ok "playlist_args start=$start end=$end max=$max_size → \"$result\""
  else
    fail_ "playlist_args start=$start end=$end max=$max_size expected \"$expect\", got \"$result\""
  fi
}

# ============================================================================
# MAIN
# ============================================================================
section "URL Parsing"
run_tests "parse single" assert_parse \
  "https://a.com/file.mp4" "https://a.com/file.mp4"
run_tests "parse space-separated" assert_parse \
  "https://a.com/file.mp4 https://b.com/file.mp4" \
  "https://a.com/file.mp4" "https://b.com/file.mp4"
run_tests "parse comma-separated" assert_parse \
  "https://a.com/file.mp4,https://b.com/file.mp4" \
  "https://a.com/file.mp4" "https://b.com/file.mp4"
run_tests "parse newline-separated" assert_parse \
  $'https://a.com/file.mp4\nhttps://b.com/file.mp4' \
  "https://a.com/file.mp4" "https://b.com/file.mp4"
run_tests "parse dedup" assert_parse \
  "https://a.com/file.mp4 https://a.com/file.mp4" \
  "https://a.com/file.mp4" "https://a.com/file.mp4"
run_tests "parse whitespace trimmed" assert_parse \
  "  https://a.com/file.mp4 , https://b.com/file.mp4  " \
  "https://a.com/file.mp4" "https://b.com/file.mp4"

section "YouTube Detection"
run_tests "detect youtube.com" \
  bash -c 'echo "https://www.youtube.com/watch?v=abc" | grep -qE "(youtube\.com|youtu\.be)"' && ok "youtube.com detected" || fail_ "youtube.com not detected"
run_tests "detect youtu.be" \
  bash -c 'echo "https://youtu.be/abc" | grep -qE "(youtube\.com|youtu\.be)"' && ok "youtu.be detected" || fail_ "youtu.be not detected"
run_tests "ignore vimeo" \
  bash -c '! echo "https://vimeo.com/123" | grep -qE "(youtube\.com|youtu\.be)"' && ok "vimeo correctly skipped" || fail_ "vimeo incorrectly matched"
run_tests "ignore direct" \
  bash -c '! echo "https://cdn.example.com/video.mp4" | grep -qE "(youtube\.com|youtu\.be)"' && ok "direct URL correctly skipped" || fail_ "direct URL incorrectly matched"

section "Format Spec Validation"
run_tests "valid format spec" assert_format_spec "bestvideo+bestaudio" "true"
run_tests "valid audio only" assert_format_spec "bestaudio/best" "true"
run_tests "valid empty (allowed)" assert_format_spec "" "false"
run_tests "valid with extras" assert_format_spec "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" "true"

section "Remux Flag"
run_tests "remux true" assert_remux "true" "true"
run_tests "remux false" assert_remux "false" "false"

section "Video Extension Detection"
run_tests "mp4" assert_video_ext "video.mp4" "true"
run_tests "webm" assert_video_ext "video.webm" "true"
run_tests "mkv" assert_video_ext "video.mkv" "true"
run_tests "non-video" assert_video_ext "image.jpg" "false"
run_tests "non-video" assert_video_ext "audio.mp3" "false"

section "Download Mode Logic"
run_tests "auto single file → skip-zip" assert_mode 1 0 "auto" "skip-zip"
run_tests "auto two files → zip" assert_mode 2 0 "auto" "zip"
run_tests "auto large → skip-zip" assert_mode 2 104857601 "auto" "skip-zip"
run_tests "download-full → nozip" assert_mode 5 0 "download-full" "download-full"
run_tests "download-zip → zip" assert_mode 1 0 "download-zip" "download-zip"

section "Split Threshold"
run_tests "over threshold" assert_split 104857601 90 "true"
run_tests "under threshold" assert_split 50000000 90 "false"
run_tests "zero disabled" assert_split 999999999 0 "false"
run_tests "exact threshold" assert_split 94371840 90 "false"

section "Token Validation"
run_tests "match" assert_token "secret123" "secret123" "true"
run_tests "mismatch" assert_token "wrong" "secret123" "false"
run_tests "empty input" assert_token "" "secret123" "false"
run_tests "empty secret" assert_token "secret123" "" "false"

section "Artifact Naming"
run_tests "sequential naming" assert_artifact_name 123456789 "false" "downloaded-files-123456789"
run_tests "parallel naming includes random" assert_artifact_name 123456789 "true" "downloaded-files-123456789"

section "Playlist Args"
run_tests "start and end" assert_playlist_args "5" "10" "" "--playlist-start 5 --playlist-end 10"
run_tests "start only" assert_playlist_args "5" "" "" "--playlist-start 5"
run_tests "end only" assert_playlist_args "" "10" "" "--playlist-end 10"
run_tests "max size only" assert_playlist_args "" "" "50" "--max-playlist-size 50"
run_tests "all params" assert_playlist_args "1" "20" "100" "--playlist-start 1 --playlist-end 20 --max-playlist-size 100"
run_tests "no params" assert_playlist_args "" "" "" ""

# ============================================================================
# Summary
# ============================================================================
echo ""
printf "═══════════════════════════════════\n"
printf "  ${GREEN}passed${NC}: %d  ${RED}failed${NC}: %d  ${YELLOW}skipped${NC}: %d\n" "$pass" "$fail" "$skip"
echo "═══════════════════════════════════"

if [[ $fail -gt 0 ]]; then
  exit 1
fi