#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

pass=0; fail=0; skip=0
ok()   { printf "  \033[0;32m✓\033[0m %s\n" "$*"; pass=$((pass+1)); }
fail_() { printf "  \033[0;31m✗\033[0m %s\n" "$*"; fail=$((fail+1)); }
section() { printf "\n\033[1m══ %s ══\033[0m\n\n" "$*"; }

contains() { grep -q "$2" "$1" 2>/dev/null; }

count_matching() {
  local file="$1" pat="$2"
  local n
  n=$(grep -c "$pat" "$file" 2>/dev/null || true)
  [[ -z "$n" ]] && n=0
  echo "${n}"
}

assert_uses_action() {
  local f="$1"; local a="$2"
  local n; n=$(count_matching "$f" "uses:.*$a")
  if [[ -n "$n" && "$n" -gt 0 ]]; then ok "$f uses $a"; else fail_ "$f does not use $a"; fi
}

assert_cancel_in_progress() {
  local f="$1"
  local val; val=$(python3 -c "
import yaml
with open('$f') as f: doc = yaml.safe_load(f)
c = doc.get('concurrency', {})
print(c.get('cancel-in-progress', 'not-set'))
")
  if   [[ "$val" == "True"  ]]; then ok "$f cancel-in-progress: true"
  elif [[ "$val" == "False" ]]; then fail_ "$f cancel-in-progress: false (should be true)"
  elif [[ "$val" == "true"  ]]; then ok "$f cancel-in-progress: true"
  elif [[ "$val" == "false" ]]; then fail_ "$f cancel-in-progress: false (should be true)"
  else fail_ "$f cancel-in-progress not set"
  fi
}

assert_dispatch_trigger() {
  local f="$1"
  contains "$f" "workflow_dispatch" && ok "$f has workflow_dispatch" || fail_ "$f missing workflow_dispatch"
}

assert_workflow_call() {
  local f="$1"
  contains "$f" "workflow_call:" \
    && ok "$f is reusable workflow" || fail_ "$f not reusable workflow"
}

assert_early_exit() {
  local f="$1"
  contains "$f" "Early exit" && ok "$f has early exit" || fail_ "$f missing early exit"
}

assert_compress() {
  local f="$1"
  contains "$f" "zip -r" && ok "$f compresses before upload" || fail_ "$f missing zip compression"
}

assert_uses_cache() {
  local f="$1"
  local n; n=$(count_matching "$f" "actions/cache@v")
  if [[ -n "$n" && "$n" -gt 0 ]]; then ok "$f uses actions/cache ($n)"; else fail_ "$f does not use cache"; fi
}

assert_sparse_checkout() {
  local f="$1"
  contains "$f" "sparse-checkout:" && ok "$f uses sparse-checkout" || fail_ "$f missing sparse-checkout"
}

assert_no_fetch_0() {
  local f="$1"
  local n; n=$(count_matching "$f" "fetch-depth: 0")
  if [[ -z "$n" || "$n" -eq 0 ]]; then ok "$f avoids fetch-depth: 0"; else fail_ "$f uses fetch-depth: 0"; fi
}

assert_input() {
  local f="$1"; local k="$2"
  contains "$f" "^[[:space:]]*$k:" && ok "$f has input: $k" || fail_ "$f missing input: $k"
}

assert_job() {
  local f="$1"; local j="$2"
  local r; r=$(python3 -c "
import yaml
with open('$f') as f: print('found' if '$j' in yaml.safe_load(f).get('jobs',{}) else 'missing')
")
  [[ "$r" == "found" ]] && ok "$f has job: $j" || fail_ "$f missing job: $j"
}

assert_matrix() {
  local f="$1"
  contains "$f" "strategy:" && contains "$f" "matrix:" && ok "$f has matrix strategy" || fail_ "$f missing matrix strategy"
}

assert_line() {
  local f="$1"; local p="$2"; local d="$3"
  contains "$f" "$p" && ok "$f: $d" || fail_ "$f: missing $d"
}

# ============================================================================
section "dispatch.yml"
D="$REPO_ROOT/.github/workflows/dispatch.yml"
assert_dispatch_trigger "$D"
assert_cancel_in_progress "$D"
assert_job "$D" "validate"
assert_job "$D" "prepare"
assert_job "$D" "dispatch-sequential"
assert_job "$D" "dispatch-parallel"
assert_matrix "$D"
assert_input "$D" "parallel"
assert_input "$D" "token"
assert_input "$D" "download_type"
assert_input "$D" "urls"
assert_no_fetch_0 "$D"

# ============================================================================
section "download-urls.yml"
DU="$REPO_ROOT/.github/workflows/download-urls.yml"
assert_workflow_call "$DU"
assert_job "$DU" "download"
assert_job "$DU" "finalize"
assert_uses_action "$DU" "install-tools"
assert_uses_action "$DU" "finalize-download"
assert_compress "$DU"

# ============================================================================
section "install-tools/action.yml"
INST="$REPO_ROOT/.github/actions/install-tools/action.yml"
assert_uses_cache "$INST"

# ============================================================================
section "finalize-download/action.yml"
FIN="$REPO_ROOT/.github/actions/finalize-download/action.yml"
assert_no_fetch_0 "$FIN"
assert_sparse_checkout "$FIN"
assert_early_exit "$FIN"
assert_uses_action "$FIN" "actions/checkout"
assert_uses_action "$FIN" "actions/download-artifact"
assert_line "$FIN" "sparse-checkout-cone-mode: false" "sparse-checkout-cone-mode: false"
assert_line "$FIN" "fetch-depth: 1" "fetch-depth: 1"
assert_compress "$FIN"

# ============================================================================
section "clean-downloads.yml"
CLEAN="$REPO_ROOT/.github/workflows/clean-downloads.yml"
assert_dispatch_trigger "$CLEAN"
assert_job "$CLEAN" "clean"

# ============================================================================
echo ""
printf "═══════════════════════════════════\n"
printf "  \033[0;32mpassed\033[0m: %d  \033[0;31mfailed\033[0m: %d  \033[1;33mskipped\033[0m: %d\n" "$pass" "$fail" "$skip"
echo "═══════════════════════════════════"

if [[ "$fail" -gt 0 ]]; then exit 1; else exit 0; fi