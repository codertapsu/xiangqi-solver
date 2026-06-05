#!/usr/bin/env bash
#
# setup.sh — one-shot dependency installer for the Xiangqi Solver monorepo.
#
# What it does:
#   1. Installs backend dependencies in apps/backend (npm ci if a lockfile is
#      present, otherwise npm install).
#   2. Runs `flutter pub get` in apps/mobile IF the Flutter SDK is on PATH.
#
# It prints a clear summary of what it did and what it skipped.
#
# Make it executable once with:  chmod +x scripts/setup.sh
# Then run from anywhere:        bash scripts/setup.sh   (or ./scripts/setup.sh)
#
set -euo pipefail

# Resolve the repository root from this script's location so the script can be
# invoked from any working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKEND_DIR="${REPO_ROOT}/apps/backend"
MOBILE_DIR="${REPO_ROOT}/apps/mobile"

DID=()
SKIPPED=()

echo "=============================================="
echo " Xiangqi Solver — setup"
echo " repo root: ${REPO_ROOT}"
echo "=============================================="

# ---------------------------------------------------------------------------
# Backend (NestJS)
# ---------------------------------------------------------------------------
echo
echo ">>> Backend (apps/backend)"
if [[ -d "${BACKEND_DIR}" && -f "${BACKEND_DIR}/package.json" ]]; then
  if ! command -v npm >/dev/null 2>&1; then
    echo "    npm not found on PATH — skipping backend install."
    SKIPPED+=("backend deps (npm not installed)")
  else
    if [[ -f "${BACKEND_DIR}/package-lock.json" ]]; then
      echo "    package-lock.json found -> npm ci"
      ( cd "${BACKEND_DIR}" && npm ci )
    else
      echo "    no lockfile -> npm install"
      ( cd "${BACKEND_DIR}" && npm install )
    fi
    DID+=("backend deps installed")
  fi
else
  echo "    apps/backend/package.json not present yet — skipping."
  SKIPPED+=("backend deps (apps/backend not ready)")
fi

# ---------------------------------------------------------------------------
# Mobile (Flutter)
# ---------------------------------------------------------------------------
echo
echo ">>> Mobile (apps/mobile)"
if [[ -d "${MOBILE_DIR}" && -f "${MOBILE_DIR}/pubspec.yaml" ]]; then
  if command -v flutter >/dev/null 2>&1; then
    echo "    flutter found -> flutter pub get"
    ( cd "${MOBILE_DIR}" && flutter pub get )
    DID+=("flutter pub get")
  else
    echo "    SKIPPED: Flutter not installed (Flutter SDK not on PATH)."
    SKIPPED+=("flutter pub get (Flutter not installed)")
  fi
else
  echo "    apps/mobile/pubspec.yaml not present yet — skipping."
  SKIPPED+=("flutter pub get (apps/mobile not ready)")
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "=============================================="
echo " Setup summary"
echo "=============================================="
if [[ ${#DID[@]} -gt 0 ]]; then
  echo "Completed:"
  for item in "${DID[@]}"; do echo "  + ${item}"; done
else
  echo "Completed: (nothing)"
fi
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  echo "Skipped:"
  for item in "${SKIPPED[@]}"; do echo "  - ${item}"; done
fi
echo
echo "Done."
