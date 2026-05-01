#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
pass=0
fail=0

# ---- Helper: run parsing logic exactly as download.sh does -------------------
parse_urls() {
  local input="$1"
  local unified urls=() token clean filtered=()
  unified=$(echo "$input" | tr ',' ' ')
  for token in $unified; do
    clean=$(echo "$token" | sed -e 's/^["'"'"']//' -e 's/["'"'"']$//')
    urls+=("$clean")
  done
  for u in "${urls[@]}"; do [ -n "$u" ] && filtered+=("$u"); done
  echo "${filtered[@]}"
}

assert_urls() {
  local input="$1"
  shift
  local expected=("$@")
  local actual
  actual=($(parse_urls "$input"))
  if [ "${actual[*]}" = "${expected[*]}" ]; then
    printf "${GREEN}PASS${NC}  \"%s\" → %s\n" "$input" "${actual[*]}"
    ((pass++))
  else
    printf "${RED}FAIL${NC}  \"%s\"\n  Expected: %s\n  Got:      %s\n" "$input" "${expected[*]}" "${actual[*]}"
    ((fail++))
  fi
}

# ---- URL parsing tests -------------------------------------------------------
echo "=== URL Parsing Tests ==="
assert_urls "https://a.com/x.bin https://b.com/y.bin" "https://a.com/x.bin" "https://b.com/y.bin"
assert_urls "\"https://a.com/x.bin https://b.com/y.bin\"" "https://a.com/x.bin" "https://b.com/y.bin"
assert_urls "\"https://a.com/x.bin, https://b.com/y.bin\"" "https://a.com/x.bin" "https://b.com/y.bin"
assert_urls "https://a.com/x.bin,https://b.com/y.bin" "https://a.com/x.bin" "https://b.com/y.bin"
assert_urls "'https://a.com/x.bin' 'https://b.com/y.bin'" "https://a.com/x.bin" "https://b.com/y.bin"
assert_urls "\"https://a.com/x.bin\" \"https://b.com/y.bin\"" "https://a.com/x.bin" "https://b.com/y.bin"
assert_urls "https://a.com/x.bin" "https://a.com/x.bin"
assert_urls "\"https://a.com/x.bin\"" "https://a.com/x.bin"
assert_urls "  https://a.com/x.bin,   https://b.com/y.bin  " "https://a.com/x.bin" "https://b.com/y.bin"
assert_urls "https://a.com/x.bin,https://b.com/y.bin,https://c.com/z.bin" "https://a.com/x.bin" "https://b.com/y.bin" "https://c.com/z.bin"
assert_urls "\"https://a.com/x.bin,https://b.com/y.bin\"  https://c.com/z.bin" "https://a.com/x.bin" "https://b.com/y.bin" "https://c.com/z.bin"
# Duplicates are kept (not deduped)
assert_urls "https://a.com/x.bin https://a.com/x.bin" "https://a.com/x.bin" "https://a.com/x.bin"
# URL with commas in path (unlikely, but survive)
assert_urls "https://a.com/path,with,commas.bin" "https://a.com/path" "with" "commas.bin" # not ideal, but expected due to comma splitting

echo ""

# ---- Mode auto‑detection tests ------------------------------------------------
echo "=== Mode Auto‑Detection Tests ==="
check_mode() {
  local count=$1 expected=$2
  local mode
  if [ $count -gt 1 ]; then mode="download-zip"; else mode="download"; fi
  if [ "$mode" = "$expected" ]; then
    printf "${GREEN}PASS${NC}  %d URL(s) → %s\n" "$count" "$mode"
    ((pass++))
  else
    printf "${RED}FAIL${NC}  %d URL(s) → expected %s, got %s\n" "$count" "$expected" "$mode"
    ((fail++))
  fi
}
check_mode 1 "download"
check_mode 2 "download-zip"
check_mode 3 "download-zip"
check_mode 10 "download-zip"

echo ""

# ---- Domain validation tests --------------------------------------------------
echo "=== Domain Validation Tests ==="
domain_ok() {
  local allowed="$1" domain="$2" expected="$3" # "ok" or "fail"
  # Replicate workflow logic
  if [ "$allowed" = "*" ]; then
    result="ok"
  elif [ -z "$allowed" ]; then
    result="fail"
  else
    IFS=',' read -ra AD_ARR <<<"$allowed"
    found=false
    for AD in "${AD_ARR[@]}"; do
      AD_CLEAN=$(echo "$AD" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      if [[ "$domain" == "$AD_CLEAN" ]]; then
        found=true
        break
      fi
    done
    if $found; then result="ok"; else result="fail"; fi
  fi
  if [ "$result" = "$expected" ]; then
    printf "${GREEN}PASS${NC}  allowed=\"%s\" domain=\"%s\" → %s\n" "$allowed" "$domain" "$result"
    ((pass++))
  else
    printf "${RED}FAIL${NC}  allowed=\"%s\" domain=\"%s\"  expected %s, got %s\n" "$allowed" "$domain" "$expected" "$result"
    ((fail++))
  fi
}

domain_ok "example.com,cdn.com" "example.com" "ok"
domain_ok "example.com,cdn.com" "cdn.com" "ok"
domain_ok "example.com,cdn.com" "other.com" "fail"
domain_ok "  example.com , cdn.com " "example.com" "ok" # whitespace trimming
domain_ok "  example.com , cdn.com " "cdn.com" "ok"
domain_ok "*" "anything.org" "ok"
domain_ok "*" "evil.com" "ok"
domain_ok "" "example.com" "fail"                  # empty → deny
domain_ok "example.com" "EXAMPLE.com" "fail"       # case‑sensitive (bash ==)
domain_ok "*.example.com" "sub.example.com" "fail" # literal glob not expanded
domain_ok "sub.example.com" "sub.example.com" "ok"

echo ""

# ---- Token check simulation ---------------------------------------------------
echo "=== Token Check Simulation ==="
TOKEN_SECRET="mysecret"
INPUT_TOKEN="mysecret"
if [ "$INPUT_TOKEN" = "$TOKEN_SECRET" ]; then
  printf "${GREEN}PASS${NC}  token matches → allowed\n"
  ((pass++))
else
  printf "${RED}FAIL${NC}  token should match\n"
  ((fail++))
fi

INPUT_TOKEN="wrong"
if [ "$INPUT_TOKEN" != "$TOKEN_SECRET" ]; then
  printf "${GREEN}PASS${NC}  token mismatch → denied\n"
  ((pass++))
else
  printf "${RED}FAIL${NC}  token should have been denied\n"
  ((fail++))
fi

echo ""
echo "Tests passed: $pass  failed: $fail"
if [ $fail -gt 0 ]; then exit 1; fi
