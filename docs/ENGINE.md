# Engine Configuration & Pikafish UCI Reference

Verified against the Pikafish source (`Pikafish-2026-01-02`, `src/ucioption.cpp`,
`src/engine.cpp`).

## ⚠️ There is no "Skill Level" / Elo in Pikafish

Pikafish is a Xiangqi fork of Stockfish that **removed** Stockfish's strength
options. It exposes **none** of `Skill Level`, `UCI_Elo`, or
`UCI_LimitStrength`. The only way to make it "weaker" is to **limit the search**
(lower `ENGINE_DEFAULT_DEPTH` or `ENGINE_DEFAULT_MOVE_TIME_MS`) — that makes it
play **faster**, not human-like-weaker. Don't send a Skill Level option; the
engine would reject it.

## Pikafish UCI options (the complete list)

| Option | Type | Default | Range | We use it? |
|---|---|---|---|---|
| `Threads` | spin | 1 | 1…(hw) | ✅ `ENGINE_THREADS` |
| `Hash` | spin | 16 | 1…33554432 (MB) | ✅ `ENGINE_HASH_MB` (default 128) |
| `MultiPV` | spin | 1 | 1…128 | ✅ `ENGINE_MULTIPV` (→ ranked candidates) |
| `Move Overhead` | spin | 10 | 0…5000 (ms) | ✅ `ENGINE_MOVE_OVERHEAD_MS` |
| `EvalFile` | string | `pikafish.nnue` | — | ✅ `PIKAFISH_NNUE_PATH` |
| `Ponder` | check | false | — | ➖ (no pondering in our flow) |
| `UCI_ShowWDL` | check | false | — | ➖ |
| `nodestime` | spin | 0 | 0…10000 | ➖ |
| `Clear Hash` | button | — | — | ➖ (auto on `ucinewgame`) |
| `Debug Log File` | string | — | — | ➖ |
| `NumaPolicy` | string | auto | — | ➖ (single-socket) |

## What we configure

Env (backend, all optional — safe defaults; ignored by the mock engine):

```env
ENGINE_THREADS=1          # search worker threads
ENGINE_HASH_MB=128        # transposition table size
ENGINE_MULTIPV=1          # 1 = best move only; N = top-N ranked candidates
ENGINE_MOVE_OVERHEAD_MS=10
```

Per-request overrides (both `/api/analysis/board` and `/screenshot`):
`engineThreads`, `engineHashMb`, `engineMultiPv` (plus the existing
`engineDepth`, `engineMoveTimeMs`). The Flutter app exposes **MultiPV** as
"Top moves to show" in Settings.

With `MultiPV > 1`, the response includes a `candidates[]` array (ranked, index 0
= best), each with localized traditional notation + WXF + score, e.g.:

```
1. Cannon 8 traverses to 5  (C8=5)  +3.91
2. King 5 traverses to 6    (K5=6)  +3.48
3. King 5 traverses to 4    (K5=4)  mate -2
```

## UCI handshake we use (best practice)

```
uci                                  → uciok
setoption name EvalFile value <nnue> # options BEFORE isready: the engine
setoption name Threads value <n>     # reallocates on Hash/Threads and blocks
setoption name Hash value <mb>       # on isready until they take effect
setoption name MultiPV value <n>
setoption name Move Overhead value <ms>
isready                              → readyok
ucinewgame                           # fresh search state for an independent FEN
position fen <xiangqi-fen>           # no "moves …" for a static position
go depth <n>            (or)  go movetime <ms>
                                     → info … multipv K … score cp/mate … pv …
                                     → bestmove <uci> [ponder <uci>]
```

Notes from the source:

- **`setoption` must come before `isready`** — `Hash`/`Threads` trigger
  reallocation and the engine waits for them on `isready`.
- We spawn a **fresh process per request**, so state is always clean;
  `ucinewgame` is sent anyway as a correctness nicety.
- **Score**: `info … score cp N` (centipawns) or `score mate N`. We display cp/100
  as `±x.xx` and `mate N` as-is. With MultiPV we take the **`multipv 1`** line for
  the primary score (not the last `info` line, which is the worst candidate).
- **Xiangqi FEN**: `<placement> <w|b> - - 0 1`; the `60` counter is the
  no-capture draw rule (not chess's 50). See [ARCHITECTURE.md] / `FenService`.

See also [ON_DEVICE_ENGINE.md](ON_DEVICE_ENGINE.md) for the on-device/backendless analysis.
