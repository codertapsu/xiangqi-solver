#!/usr/bin/env bash
#
# check.sh — run all quality gates for the Xiangqi Solver monorepo.
#
# Backend (apps/backend):  lint + test + build
# Mobile  (apps/mobile):   flutter analyze + flutter test  (only if Flutter is
#                          installed; otherwise clearly marked SKIPPED).
#
# This script is TOLERANT: it keeps running every check even after one fails,
# tracks pass/fail per step, prints a summary, and exits non-zero ONLY when a
# real check failed. Steps that are skipped (e.g. tool not installed, or a sub-
# project not yet present) do NOT cause a non-zero exit.
#
# Run with:  bash scripts/check.sh   (or ./scripts/check.sh after chmod +x)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKEND_DIR="${REPO_ROOT}/apps/backend"
MOBILE_DIR="${REPO_ROOT}/apps/mobile"

# Result tracking. Each entry is "STATUS|label".
RESULTS=()
FAILED=0

record() { RESULTS+=("$1|$2"); }

# run_step <label> <working-dir> <command...>
# Runs a command, records PASS/FAIL, and never aborts the whole script.
run_step() {
  local label="$1"; shift
  local workdir="$1"; shift
  echo
  echo "----------------------------------------------"
  echo ">>> ${label}"
  echo "    ($*)"
  echo "----------------------------------------------"
  if ( cd "${workdir}" && "$@" ); then
    echo "    RESULT: PASS — ${label}"
    record "PASS" "${label}"
  else
    echo "    RESULT: FAIL — ${label}"
    record "FAIL" "${label}"
    FAILED=1
  fi
}

skip_step() {
  local label="$1"; local reason="$2"
  echo
  echo ">>> SKIPPED: ${label} — ${reason}"
  record "SKIP" "${label} (${reason})"
}

echo "=============================================="
echo " Xiangqi Solver — checks"
echo " repo root: ${REPO_ROOT}"
echo "=============================================="

# ---------------------------------------------------------------------------
# Backend
# ---------------------------------------------------------------------------
if [[ -d "${BACKEND_DIR}" && -f "${BACKEND_DIR}/package.json" ]]; then
  if ! command -v npm >/dev/null 2>&1; then
    skip_step "backend lint"  "npm not installed"
    skip_step "backend test"  "npm not installed"
    skip_step "backend build" "npm not installed"
  else
    if [[ ! -d "${BACKEND_DIR}/node_modules" ]]; then
      echo "NOTE: apps/backend/node_modules missing — run scripts/setup.sh first."
    fi
    run_step "backend lint"  "${BACKEND_DIR}" npm run lint
    run_step "backend test"  "${BACKEND_DIR}" npm test
    run_step "backend build" "${BACKEND_DIR}" npm run build
  fi
else
  skip_step "backend lint"  "apps/backend not ready"
  skip_step "backend test"  "apps/backend not ready"
  skip_step "backend build" "apps/backend not ready"
fi

# ---------------------------------------------------------------------------
# Mobile
# ---------------------------------------------------------------------------
if [[ -d "${MOBILE_DIR}" && -f "${MOBILE_DIR}/pubspec.yaml" ]]; then
  if command -v flutter >/dev/null 2>&1; then
    run_step "flutter analyze" "${MOBILE_DIR}" flutter analyze
    run_step "flutter test"    "${MOBILE_DIR}" flutter test
  else
    skip_step "flutter analyze" "Flutter not installed"
    skip_step "flutter test"    "Flutter not installed"
  fi
else
  skip_step "flutter analyze" "apps/mobile not ready"
  skip_step "flutter test"    "apps/mobile not ready"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "=============================================="
echo " Check summary"
echo "=============================================="
for entry in "${RESULTS[@]}"; do
  status="${entry%%|*}"
  label="${entry#*|}"
  case "${status}" in
    PASS) echo "  [PASS] ${label}" ;;
    FAIL) echo "  [FAIL] ${label}" ;;
    SKIP) echo "  [SKIP] ${label}" ;;
  esac
done
echo "----------------------------------------------"
if [[ "${FAILED}" -ne 0 ]]; then
  echo "Overall: FAILED (one or more real checks failed)."
  exit 1
fi
echo "Overall: OK (no failing checks; skips are not failures)."
exit 0
