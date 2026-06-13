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
#     engine/pikafish.nnue      the SERVER engine's NNUE net (PIKAFISH_NNUE_PATH)
#     engine/master-net.nnue    the ON-DEVICE net served to the app at /api/engine/net
#     DEPLOY.md                 server-side steps
#
# Download pikafish.nnue from https://github.com/official-pikafish/Networks/releases/download/master-net/pikafish.nnue
# Deploy + run (from your machine, then on the server):
#   ONDEVICE_NET_SRC=~/Downloads/pikafish.nnue bash scripts/build-release.sh
#   rsync -av --delete --exclude='/data' --exclude='/logs' --exclude='/node_modules' release/ root@103.157.205.175:/opt/xiangqi-solver/apps/backend
#   ssh root@103.157.205.175
# The --exclude flags keep the server's runtime data/ (hint ledger), logs/
# (date-grouped error logs), and installed node_modules — the release bundle
# does NOT contain them, so without the excludes --delete would wipe them.
#   cd /opt/xiangqi-solver/apps/backend && npm install --omit=dev && npm run start:prod
#
# Overridable via env:
#   DEPLOY_DIR    where the bundle lands on the server (default below) — used to
#                 write ABSOLUTE engine paths into the release .env.
#   PIKAFISH_BIN  which Linux binary the server CPU supports (default pikafish-avx2;
#                 use pikafish-sse41-popcnt for old CPUs that lack AVX2).
#   PIKAFISH_SRC  path to the unpacked Pikafish.2026-01-02 dir.
#   ONDEVICE_NET_SRC  the master-net the Android app downloads (served at
#                 /api/engine/net); MUST be 50,760,458 bytes — a DIFFERENT net
#                 from the server engine's pikafish.nnue.
#   PUBLIC_BASE_URL  the URL the app reaches this backend at (default the prod
#                 host) — pins ONDEVICE_NET_URL=<it>/api/engine/net in the .env.
set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$BACKEND_DIR/../.." && pwd)"
RELEASE_DIR="$BACKEND_DIR/release"

DEPLOY_DIR="${DEPLOY_DIR:-/opt/xiangqi-solver/apps/backend}"
PIKAFISH_BIN="${PIKAFISH_BIN:-pikafish-avx2}"
PIKAFISH_SRC="${PIKAFISH_SRC:-$REPO_ROOT/Pikafish.2026-01-02}"
# Public base URL the APP reaches this backend at — used to pin ONDEVICE_NET_URL
# so the app downloads the on-device net from us (GET /api/engine/net).
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-http://103.157.205.175:3000}"
ONDEVICE_NET_SRC="${ONDEVICE_NET_SRC:-}"
ONDEVICE_NET_BYTES=50760458   # master-net size; MUST match backend ONDEVICE_NET_BYTES

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

# On-device master-net (served at /api/engine/net) — a DIFFERENT net from the
# server engine's pikafish.nnue above; the app verifies its size, so check it here.
if [ -z "$ONDEVICE_NET_SRC" ]; then
  echo "ERROR: ONDEVICE_NET_SRC is not set — the master-net the app downloads must be provided." >&2
  echo "       Fetch it once from:" >&2
  echo "         https://github.com/official-pikafish/Networks/releases/download/master-net/pikafish.nnue" >&2
  echo "       then rebuild: ONDEVICE_NET_SRC=/path/to/pikafish.nnue bash scripts/build-release.sh" >&2
  exit 1
fi
[ -f "$ONDEVICE_NET_SRC" ] || { echo "ERROR: ONDEVICE_NET_SRC not found: $ONDEVICE_NET_SRC" >&2; exit 1; }
ondevice_net_size=$(stat -f %z "$ONDEVICE_NET_SRC" 2>/dev/null || stat -c %s "$ONDEVICE_NET_SRC")
[ "$ondevice_net_size" = "$ONDEVICE_NET_BYTES" ] || {
  echo "ERROR: ONDEVICE_NET_SRC is $ondevice_net_size bytes, expected $ONDEVICE_NET_BYTES (the master-net)." >&2
  echo "       That's the WRONG net (e.g. the 53MB Jan release) — the app checks the size and would reject it." >&2
  exit 1
}

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
# TLS scaffolding: ready-made Caddy reverse-proxy config (see DEPLOY.md "TLS").
cp deploy/Caddyfile "$RELEASE_DIR/Caddyfile"

# engine: ALL Linux binaries (so the arch can be switched server-side) + the net
cp -R "$PIKAFISH_SRC/Linux" "$RELEASE_DIR/engine/Linux"
cp "$PIKAFISH_SRC/pikafish.nnue" "$RELEASE_DIR/engine/pikafish.nnue"
cp "$ONDEVICE_NET_SRC" "$RELEASE_DIR/engine/master-net.nnue"   # served at GET /api/engine/net
chmod +x "$RELEASE_DIR/engine/Linux/"pikafish-*

# --- 3. production .env: copy, then PIN engine paths to the server layout ---
bold "==> Writing release .env (engine paths -> $DEPLOY_DIR/engine)..."
# Keep every other var (API keys, etc.); drop the engine path/provider/variant
# lines and re-add them pinned to where the bundle lands on the server.
grep -vE '^(ENGINE_PROVIDER|PIKAFISH_BINARY_PATH|PIKAFISH_NNUE_PATH|ENGINE_UCI_VARIANT|ONDEVICE_NET_URL|ONDEVICE_NET_PATH)=' .env > "$RELEASE_DIR/.env"
{
  echo ""
  echo "# --- engine: pinned for the server bundle by scripts/build-release.sh ---"
  echo "ENGINE_PROVIDER=pikafish"
  echo "PIKAFISH_BINARY_PATH=$DEPLOY_DIR/engine/Linux/$PIKAFISH_BIN"
  echo "PIKAFISH_NNUE_PATH=$DEPLOY_DIR/engine/pikafish.nnue"
  # On-device net: the app downloads it from THIS backend (GET /api/engine/net),
  # streamed from the pinned master-net file — not GitHub.
  echo "ONDEVICE_NET_URL=$PUBLIC_BASE_URL/api/engine/net"
  echo "ONDEVICE_NET_PATH=$DEPLOY_DIR/engine/master-net.nnue"
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
rsync -av --delete --exclude='/data' --exclude='/logs' --exclude='/node_modules' release/ root@103.157.205.175:$DEPLOY_DIR
\`\`\`
**Important:** the \`--exclude\` flags protect the server's runtime \`data/\` (hint
ledger) and \`logs/\` (date-grouped error logs), plus the installed \`node_modules\`,
from being wiped by \`--delete\` — the release bundle does not contain them.

## On the server
\`\`\`sh
cd $DEPLOY_DIR
npm install --omit=dev      # 'npm install' also works; --omit=dev is smaller (dist/ is prebuilt)
npm run start:prod          # node dist/main.js   (listens on \$PORT, default 3000)
\`\`\`

**Note (since the latency release):** \`npm install\` now also pulls in \`sharp\`
(prebuilt linux-x64 binaries — no compiler needed) for server-side image
downscaling, and the engine runs as a WARM POOL: set \`ENGINE_POOL_SIZE\` in
\`.env\` to roughly the number of spare CPU cores (default 2). Each pool process
holds the NNUE net + \`ENGINE_HASH_MB\` of RAM while warm; idle engines exit
after 5 minutes.

Run it under a process manager (pm2 / systemd) so it restarts on crash/reboot, e.g.:
\`\`\`sh
pm2 start "npm run start:prod" --name xiangqi-backend --cwd $DEPLOY_DIR
\`\`\`

## TLS (recommended)
The backend itself speaks plain HTTP. Terminate TLS with Caddy in front of it
— see the bundled [Caddyfile](./Caddyfile) for a ready-made config and the app/
config changes to make afterwards. Requires a DOMAIN pointed at the VPS (ACME
does not issue certificates for bare IPs); until then the app keeps using the
scoped cleartext exception.

## Engine binary
The bundled CPU build is **$PIKAFISH_BIN**. If the server prints
"Illegal instruction" on start, the CPU lacks those SIMD extensions — point
\`PIKAFISH_BINARY_PATH\` in \`.env\` at a more compatible build, e.g.
\`$DEPLOY_DIR/engine/Linux/pikafish-sse41-popcnt\`. Quick check:
\`\`\`sh
echo quit | ./engine/Linux/$PIKAFISH_BIN   # should print the Pikafish banner
\`\`\`

## On-device engine net
The Android app downloads its NNUE net from THIS backend at \`GET /api/engine/net\`
(served from \`$DEPLOY_DIR/engine/master-net.nnue\`, pinned in \`.env\`) — no GitHub
dependency. Verify after starting:
\`\`\`sh
curl -sI http://127.0.0.1:\${PORT:-3000}/api/engine/net | grep -i content-length   # = $ONDEVICE_NET_BYTES
\`\`\`
If it 404s, the master-net file is missing on the server (re-run the build with
\`ONDEVICE_NET_SRC\` set, then redeploy).

Requires Node.js 20+ on the server.
EOF

# --- done ------------------------------------------------------------------
bold "==> Done."
echo "    Bundle size: $(du -sh "$RELEASE_DIR" | cut -f1)   ($RELEASE_DIR)"
echo ""
echo "Next (the --exclude flags keep the server's data/, logs/, node_modules):"
echo "  rsync -av --delete --exclude='/data' --exclude='/logs' --exclude='/node_modules' release/ root@103.157.205.175:$DEPLOY_DIR"
echo "  ssh root@103.157.205.175 'cd $DEPLOY_DIR && npm install --omit=dev && npm run start:prod'"
