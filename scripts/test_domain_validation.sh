#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
pass=0
fail=0

# Re‑use the same logic as the workflow (repeat here for isolation)
validate() {
  local allowed="$1" domain="$2"
  if [ "$allowed" = "*" ]; then
    echo "ok"
    return
  fi
  if [ -z "$allowed" ]; then
    echo "fail"
    return
  fi
  IFS=',' read -ra AD_ARR <<<"$allowed"
  for AD in "${AD_ARR[@]}"; do
    AD_CLEAN=$(echo "$AD" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ "$domain" == "$AD_CLEAN" ]]; then
      echo "ok"
      return
    fi
  done
  echo "fail"
}

assert() {
  local allowed="$1" domain="$2" expect="$3"
  local result
  result=$(validate "$allowed" "$domain")
  if [ "$result" = "$expect" ]; then
    printf "${GREEN}PASS${NC}  \"%s\" @ \"%s\" → %s\n" "$domain" "$allowed" "$result"
    ((pass++))
  else
    printf "${RED}FAIL${NC}  \"%s\" @ \"%s\"  expected %s, got %s\n" "$domain" "$allowed" "$expect" "$result"
    ((fail++))
  fi
}

echo "=== Extended Domain Validation ==="

# Basic exact
assert "example.com" "example.com" "ok"
assert "example.com" "other.com" "fail"

# Multiple allowed
assert "a.com,b.com" "a.com" "ok"
assert "a.com,b.com" "b.com" "ok"
assert "a.com,b.com" "c.com" "fail"

# Wildcard
assert "*" "anything" "ok"
assert "*" "evil.com" "ok"

# Empty -> fail
assert "" "example.com" "fail"

# Whitespace
assert " a.com , b.com " "a.com" "ok"
assert " a.com , b.com " "b.com" "ok"
assert " a.com , b.com " "c.com" "fail"

# Subdomains: not matched (exact only)
assert "example.com" "sub.example.com" "fail"
assert "sub.example.com" "example.com" "fail"

# Trailing dots? unlikely but
assert "example.com." "example.com." "ok"
assert "example.com." "example.com" "fail" # dot is part of string

# Case sensitivity (bash == is case-sensitive)
assert "Example.com" "example.com" "fail"
assert "example.com" "example.com" "ok"

# Domain printed from URL may have port – but our extraction uses awk -F/ '{print $3}', which includes port.
# That's a known limitation; not tested now.

# Comma inside domain? not realistic, but safe
assert "exa,mple.com" "exa" "fail" # will be split, first token "exa"

# Extra spacing in allowed list with only one entry
assert "   example.com   " "example.com" "ok"

echo ""
echo "Tests passed: $pass  failed: $fail"
if [ $fail -gt 0 ]; then exit 1; fi
