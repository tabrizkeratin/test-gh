#!/usr/bin/env bash
# Common helpers – sourced by download.sh
set -euo pipefail

export GUM_AVAILABLE=false
if command -v gum &>/dev/null; then
  GUM_AVAILABLE=true
fi

print_header() {
  echo ""
  echo "  🎯 Download Manager  v2.0"
  echo "  ──────────────────────────"
  echo ""
}

print_error() { echo "❌ Error: $*" >&2; }
print_success() { echo "✅ $*"; }
print_warn() { echo "⚠️  $*"; }

check_gh() {
  if ! command -v gh &>/dev/null; then
    print_error "GitHub CLI (gh) is not installed. Install it: https://cli.github.com/manual/installation"
    exit 1
  fi
  if ! gh auth status &>/dev/null; then
    print_error "gh not authenticated. Run: gh auth login"
    exit 1
  fi
}

_gh_auth_check_file=""
_gh_auth_checked=false

check_gh_async() {
  local _tmpfile
  _tmpfile=$(mktemp)
  _gh_auth_check_file="$_tmpfile"

  if ! command -v gh &>/dev/null; then
    echo "missing" > "$_tmpfile"
    return
  fi
  if gh auth status &>/dev/null; then
    echo "ok" > "$_tmpfile"
  else
    echo "not_authenticated" > "$_tmpfile"
  fi
}

check_gh_async_wait() {
  if [[ -z "$_gh_auth_check_file" ]]; then
    check_gh
    return
  fi
  wait "$1" 2>/dev/null || true
  local _status
  _status=$(cat "$_gh_auth_check_file")
  rm -f "$_gh_auth_check_file"
  _gh_auth_check_file=""

  if [[ "$_status" == "missing" ]]; then
    print_error "GitHub CLI (gh) is not installed. Install it: https://cli.github.com/manual/installation"
    exit 1
  elif [[ "$_status" == "not_authenticated" ]]; then
    print_error "gh not authenticated. Run: gh auth login"
    exit 1
  fi
}

get_repo() {
  gh repo view --json nameWithOwner -q ".nameWithOwner" 2>/dev/null || {
    print_error "Cannot determine repo. Are you in a git repo with an origin?"
    exit 1
  }
}

validate_token() {
  if [[ -z "${DOWNLOAD_TOKEN:-}" ]]; then
    print_error "DOWNLOAD_TOKEN is not set. Use .env or --token."
    exit 1
  fi
}

# Spinner utility
spinner() {
  local pid=$1 msg="${2:-Working...}" delay=0.1 spinstr='|/-\'
  if $GUM_AVAILABLE; then
    gum spin --spinner dot --title "$msg" -- bash -c "while kill -0 $pid 2>/dev/null; do sleep 0.1; done"
  else
    printf " %s " "$msg"
    while kill -0 $pid 2>/dev/null; do
      local temp=${spinstr#?}
      printf " [%c]  " "$spinstr"
      spinstr=$temp${spinstr%"$temp"}
      sleep $delay
      printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b\n"
  fi
}
