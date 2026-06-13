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
ENGINE_POOL_SIZE=2        # warm persistent engines = max CONCURRENT searches
                          # (~1 per spare CPU core; extra requests queue)
```

Per-request overrides (both `/api/analysis/board` and `/screenshot`):
`engineThreads` (clamped 1…8), `engineHashMb` (1…1024), `engineMultiPv` (1…10)
(plus the existing `engineDepth`, `engineMoveTimeMs`). The Flutter app exposes
**MultiPV** as "Top moves to show" in Settings.

With `MultiPV > 1`, the response includes a `candidates[]` array (ranked, index 0
= best), each with localized traditional notation + WXF + score, e.g.:

```
1. Cannon 8 traverses to 5  (C8=5)  +3.91
2. King 5 traverses to 6    (K5=6)  +3.48
3. King 5 traverses to 4    (K5=4)  mate -2
```

## Warm engine pool (process lifecycle)

The backend keeps a small pool of **persistent, warm Pikafish processes**
(`pikafish-engine.service.ts`) instead of spawning a fresh process per request.
The expensive initialization — process spawn + UCI handshake + NNUE network
load (~50 MB) + hash allocation — is paid **once per process**; a warm search
is just `ucinewgame / position / go`.

- **Pool size = hard concurrency cap**: at most `ENGINE_POOL_SIZE` (default 2)
  searches run simultaneously, which also bounds engine RAM/CPU on the host.
  Engines spawn lazily on demand up to the cap.
- **Bounded FIFO queue**: further requests wait in arrival order; when more
  than 32 are already waiting, the request is shed with `ENGINE_BUSY` (503).
- **Idle shutdown**: an engine idle for 5 minutes quits (polite `quit`, then
  SIGTERM, then SIGKILL after a 1.5 s grace) to free RAM between bursts; it is
  respawned on the next request.
- **Option re-application**: per-search options (`Threads`/`Hash`/`MultiPV`)
  are diffed against the slot's last-applied values and only re-sent (followed
  by `isready` → `readyok`) when they changed — repeat solves with the same
  settings skip the Hash reallocation entirely.
- **Combined search bounds**: when both depth and movetime are set the engine
  receives **both** — `go depth D movetime M` — and stops at whichever bound
  it reaches first, so a pathological position can no longer run unbounded by
  time. With only one set: `go depth D` / `go movetime M`; with neither:
  `go movetime 1000`.
- **Search timeout**: `max(moveTimeMs × 2 + 5000, 10000)` ms. A stuck engine
  is killed and its slot replaced (a killed slot is never reused — its late
  `bestmove` could answer the wrong position); the request fails with
  `ENGINE_TIMEOUT`. Option changes get a separate 15 s budget (Hash realloc
  can be slow).
- **Crash respawn**: if a warm process dies, the slot leaves the pool (a
  `bestmove` already in its buffer still resolves the in-flight request) and a
  replacement is spawned on demand — including for queued requests freed up by
  the death.

### Engine result cache

`EngineService` memoizes successful results in a 500-entry in-memory LRU keyed
`(provider | fen | depth | moveTimeMs | threads | hashMb | multiPv)`
(`engine.service.ts` + `common/utils/lru-cache.ts`). Positions repeat
(openings, retry taps, vision-cache hits), making those solves instant. The
raw UCI transcript is stripped before caching/returning — it is debug-only and
can reach hundreds of KB per long search.

### Measured latencies (M-series dev Mac, real HTTP requests)

| Scenario | Latency |
|---|---|
| Cold first solve (spawn + NNUE load + search) | ~240 ms |
| Warm solve (pool hit) | ~28 ms |
| Cached repeat (LRU hit) | ~2 ms |
| Depth-16 warm search | ~208 ms |

## UCI handshake we use (best practice)

Once per process, at spawn:

```
uci                                  → uciok
setoption name UCI_Variant value …   # only when ENGINE_UCI_VARIANT is set
                                     # (Fairy-Stockfish: variant BEFORE net load)
setoption name EvalFile value <nnue> # options BEFORE isready: the engine
setoption name Move Overhead value <ms>  # blocks on isready until they apply
isready                              → readyok
```

Per search, on the warm process:

```
setoption name Threads value <n>     # ONLY the options that changed since the
setoption name Hash value <mb>       # slot's previous search, followed by
setoption name MultiPV value <n>     # isready → readyok
ucinewgame                           # fresh search state for an independent FEN
position fen <xiangqi-fen>           # no "moves …" for a static position
go depth <n> movetime <ms>           # BOTH bounds when both are configured
                                     → info … multipv K … score cp/mate … pv …
                                     → bestmove <uci> [ponder <uci>]
```

Notes from the source:

- **`setoption` must come before `isready`** — `Hash`/`Threads` trigger
  reallocation and the engine waits for them on `isready`.
- Processes are **reused across requests** (warm pool, above); `ucinewgame`
  before each `position` keeps search state clean between unrelated FENs.
- **Score**: `info … score cp N` (centipawns) or `score mate N`. We display cp/100
  as `±x.xx` and `mate N` as-is. With MultiPV we take the **`multipv 1`** line for
  the primary score (not the last `info` line, which is the worst candidate).
- **Xiangqi FEN**: `<placement> <w|b> - - 0 1`; the `60` counter is the
  no-capture draw rule (not chess's 50). See [ARCHITECTURE.md] / `FenService`.

See also [ON_DEVICE_ENGINE.md](ON_DEVICE_ENGINE.md) for the on-device/backendless analysis.
