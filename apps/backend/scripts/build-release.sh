#!/usr/bin/env bash
#
# Build a self-contained backend deploy bundle into apps/backend/release/.
#
# The bundle contains everything the server needs EXCEPT node_modules (installed
# on the server) and the Node.js runtime itself:
#   release/
#     dist/                     compiled backend (nest build output)
#     package.json              + package-lock.json
#     .env                      production env (engine paths pinned to the server)
#     engine/Linux/pikafish-*   all Linux engine binaries (made executable)
#     engine/pikafish.nnue      the NNUE net
#     DEPLOY.md                 server-side steps
#
# Deploy + run (from your machine, then on the server):
#   bash scripts/build-release.sh
#   rsync -av --delete release/ root@103.157.205.175:/opt/xiangqi-solver/apps/backend
#   ssh root@103.157.205.175
#   cd /opt/xiangqi-solver/apps/backend && npm install --omit=dev && npm run start:prod
#
# Overridable via env:
#   DEPLOY_DIR    where the bundle lands on the server (default below) — used to
#                 write ABSOLUTE engine paths into the release .env.
#   PIKAFISH_BIN  which Linux binary the server CPU supports (default pikafish-avx2;
#                 use pikafish-sse41-popcnt for old CPUs that lack AVX2).
#   PIKAFISH_SRC  path to the unpacked Pikafish.2026-01-02 dir.
set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$BACKEND_DIR/../.." && pwd)"
RELEASE_DIR="$BACKEND_DIR/release"

DEPLOY_DIR="${DEPLOY_DIR:-/opt/xiangqi-solver/apps/backend}"
PIKAFISH_BIN="${PIKAFISH_BIN:-pikafish-avx2}"
PIKAFISH_SRC="${PIKAFISH_SRC:-$REPO_ROOT/Pikafish.2026-01-02}"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }

bold "==> Backend:      $BACKEND_DIR"
bold "==> Pikafish src: $PIKAFISH_SRC"
bold "==> Server dir:   $DEPLOY_DIR   (engine binary: $PIKAFISH_BIN)"

# --- preflight -------------------------------------------------------------
cd "$BACKEND_DIR"
[ -f .env ] || { echo "ERROR: apps/backend/.env not found — create it (copy .env.example) before building a release." >&2; exit 1; }
[ -d "$PIKAFISH_SRC/Linux" ] || { echo "ERROR: $PIKAFISH_SRC/Linux not found." >&2; exit 1; }
[ -f "$PIKAFISH_SRC/Linux/$PIKAFISH_BIN" ] || { echo "ERROR: engine binary $PIKAFISH_SRC/Linux/$PIKAFISH_BIN not found (set PIKAFISH_BIN)." >&2; exit 1; }
[ -f "$PIKAFISH_SRC/pikafish.nnue" ] || { echo "ERROR: $PIKAFISH_SRC/pikafish.nnue not found." >&2; exit 1; }

# --- 1. install build deps + compile --------------------------------------
bold "==> Installing build deps + compiling (nest build -> dist/)..."
npm install
npm run build
[ -f dist/main.js ] || { echo "ERROR: build did not produce dist/main.js." >&2; exit 1; }

# --- 2. assemble release/ --------------------------------------------------
bold "==> Assembling $RELEASE_DIR..."
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR/engine"

cp -R dist "$RELEASE_DIR/dist"
cp package.json "$RELEASE_DIR/package.json"
[ -f package-lock.json ] && cp package-lock.json "$RELEASE_DIR/package-lock.json"

# engine: ALL Linux binaries (so the arch can be switched server-side) + the net
cp -R "$PIKAFISH_SRC/Linux" "$RELEASE_DIR/engine/Linux"
cp "$PIKAFISH_SRC/pikafish.nnue" "$RELEASE_DIR/engine/pikafish.nnue"
chmod +x "$RELEASE_DIR/engine/Linux/"pikafish-*

# --- 3. production .env: copy, then PIN engine paths to the server layout ---
bold "==> Writing release .env (engine paths -> $DEPLOY_DIR/engine)..."
# Keep every other var (API keys, etc.); drop the engine path/provider/variant
# lines and re-add them pinned to where the bundle lands on the server.
grep -vE '^(ENGINE_PROVIDER|PIKAFISH_BINARY_PATH|PIKAFISH_NNUE_PATH|ENGINE_UCI_VARIANT)=' .env > "$RELEASE_DIR/.env"
{
  echo ""
  echo "# --- engine: pinned for the server bundle by scripts/build-release.sh ---"
  echo "ENGINE_PROVIDER=pikafish"
  echo "PIKAFISH_BINARY_PATH=$DEPLOY_DIR/engine/Linux/$PIKAFISH_BIN"
  echo "PIKAFISH_NNUE_PATH=$DEPLOY_DIR/engine/pikafish.nnue"
  # Pikafish is xiangqi-native — UCI_Variant must stay empty (only set it for
  # Fairy-Stockfish). Left unset here so the backend defaults to empty.
} >> "$RELEASE_DIR/.env"

# --- 4. server-side runbook ------------------------------------------------
cat > "$RELEASE_DIR/DEPLOY.md" <<EOF
# Deploy

This folder is a self-contained backend bundle. It assumes it is deployed to
\`$DEPLOY_DIR\` (the engine paths in \`.env\` are pinned to that location — rebuild
with \`DEPLOY_DIR=... bash scripts/build-release.sh\` if you deploy elsewhere).

## From your machine
\`\`\`sh
rsync -av --delete release/ root@103.157.205.175:$DEPLOY_DIR
\`\`\`
(Tip: add \`--exclude=node_modules\` to keep the server's installed deps between deploys.)

## On the server
\`\`\`sh
cd $DEPLOY_DIR
npm install --omit=dev      # 'npm install' also works; --omit=dev is smaller (dist/ is prebuilt)
npm run start:prod          # node dist/main.js   (listens on \$PORT, default 3000)
\`\`\`

Run it under a process manager (pm2 / systemd) so it restarts on crash/reboot, e.g.:
\`\`\`sh
pm2 start "npm run start:prod" --name xiangqi-backend --cwd $DEPLOY_DIR
\`\`\`

## Engine binary
The bundled CPU build is **$PIKAFISH_BIN**. If the server prints
"Illegal instruction" on start, the CPU lacks those SIMD extensions — point
\`PIKAFISH_BINARY_PATH\` in \`.env\` at a more compatible build, e.g.
\`$DEPLOY_DIR/engine/Linux/pikafish-sse41-popcnt\`. Quick check:
\`\`\`sh
echo quit | ./engine/Linux/$PIKAFISH_BIN   # should print the Pikafish banner
\`\`\`
Requires Node.js 20+ on the server.
EOF

# --- done ------------------------------------------------------------------
bold "==> Done."
echo "    Bundle size: $(du -sh "$RELEASE_DIR" | cut -f1)   ($RELEASE_DIR)"
echo ""
echo "Next:"
echo "  rsync -av --delete release/ root@103.157.205.175:$DEPLOY_DIR"
echo "  ssh root@103.157.205.175 'cd $DEPLOY_DIR && npm install --omit=dev && npm run start:prod'"
