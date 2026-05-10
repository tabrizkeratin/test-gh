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

get_repo() {
  gh repo view --json nameWithOwner -q ".nameWithOwner" 2>/dev/null || {
    print_error "Cannot determine repo. Are you in a git repo with an origin?"
    exit 1
  }
}

validate_token() { }

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
