import { spawn, ChildProcessWithoutNullStreams } from 'node:child_process';
import { accessSync, constants as fsConstants, existsSync } from 'node:fs';
import { dirname } from 'node:path';
import { Injectable, Logger, OnModuleDestroy, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AppConfig } from '../../config/configuration';
import {
  EngineBestMoveInput,
  EngineBestMoveResult,
  EngineMoveLine,
  XiangqiEngine,
} from './engine.interface';
import { uciToMove } from './uci.util';

const SIGTERM_GRACE_MS = 1500;
/** Kill a warm engine that has sat idle this long (frees RAM between bursts). */
const IDLE_SHUTDOWN_MS = 5 * 60 * 1000;
/** Budget for option changes to take effect (Hash realloc can be slow). */
const READY_TIMEOUT_MS = 15_000;
/** Cap on requests waiting for a free engine before we shed load. */
const MAX_QUEUE_DEPTH = 32;

/** Per-search UCI options that may differ between requests. */
interface SearchOptions {
  threads: number;
  hashMb: number;
  multiPv: number;
}

/**
 * One persistent engine child process. The expensive initialization (process
 * spawn, UCI handshake, NNUE network load, hash allocation) happens ONCE here;
 * subsequent searches reuse the warm process with just
 * `ucinewgame / position / go`.
 *
 * A slot runs at most one search at a time (`busy`); the pool serializes
 * access. All stdio handles are unref'd so an idle pool never keeps the event
 * loop (or a test runner) alive.
 */
class EngineSlot {
  alive = true;
  busy = false;
  /** Options last applied via setoption; -1 forces the first application. */
  applied: SearchOptions = { threads: -1, hashMb: -1, multiPv: -1 };
  /** Resolves once uciok + base options + readyok complete. */
  readonly ready: Promise<void>;

  private readonly child: ChildProcessWithoutNullStreams;
  private buffer = '';
  private waiter?: {
    test: RegExp;
    resolve: (transcript: string) => void;
    reject: (err: Error) => void;
    timer: NodeJS.Timeout;
  };
  private idleTimer?: NodeJS.Timeout;

  constructor(
    binaryPath: string,
    nnuePath: string,
    variant: string,
    moveOverheadMs: number,
    private readonly onDeath: (slot: EngineSlot) => void,
  ) {
    // ARGS ARRAY, no shell: no command injection possible. cwd is the binary's
    // directory so a co-located "pikafish.nnue" resolves by default.
    this.child = spawn(binaryPath, [], { stdio: 'pipe', cwd: dirname(binaryPath) });
    // Never let a warm idle engine keep the parent event loop alive. The stdio
    // pipes are net.Sockets at runtime (typed as plain streams), so unref must
    // be feature-detected.
    this.child.unref();
    const unrefStream = (s: unknown): void => {
      const maybe = s as { unref?: () => void } | null;
      if (maybe && typeof maybe.unref === 'function') maybe.unref();
    };
    unrefStream(this.child.stdin);
    unrefStream(this.child.stdout);
    unrefStream(this.child.stderr);

    this.child.stdout.setEncoding('utf8');
    this.child.stdout.on('data', (chunk: string) => {
      this.buffer += chunk;
      this.checkWaiter();
    });
    // Drain stderr (rarely used by UCI engines) so a chatty warm process can
    // never fill the 64KB pipe buffer and block mid-search.
    this.child.stderr.resume();
    this.child.on('error', (err) => this.die(`Engine process error: ${err.message}`));
    this.child.on('close', (code) => this.die(`Engine exited (code ${code})`));

    this.ready = this.handshake(nnuePath, variant, moveOverheadMs);
    // Swallow here; acquirers await `ready` and receive the real rejection.
    this.ready.catch(() => undefined);
    this.touchIdle();
  }

  /** uci -> uciok, then static options (variant/net/overhead) -> readyok. */
  private async handshake(
    nnuePath: string,
    variant: string,
    moveOverheadMs: number,
  ): Promise<void> {
    this.send(['uci']);
    await this.waitFor(/\buciok\b/, READY_TIMEOUT_MS, 'ENGINE_UNAVAILABLE');
    // Fresh window per wait: a stale "uciok"/"readyok" left in the buffer must
    // never satisfy a LATER wait (it would unblock before options take effect).
    this.buffer = '';
    const opts: string[] = [];
    // For Fairy-Stockfish the variant MUST be selected before the net loads.
    if (variant) opts.push(`setoption name UCI_Variant value ${variant}`);
    if (nnuePath) opts.push(`setoption name EvalFile value ${nnuePath}`);
    opts.push(`setoption name Move Overhead value ${moveOverheadMs}`);
    opts.push('isready');
    this.send(opts);
    await this.waitFor(/\breadyok\b/, READY_TIMEOUT_MS, 'ENGINE_UNAVAILABLE');
    this.buffer = '';
  }

  /** Apply per-search options only when they differ from the last search. */
  async applyOptions(wanted: SearchOptions): Promise<void> {
    const cmds: string[] = [];
    if (wanted.threads !== this.applied.threads) {
      cmds.push(`setoption name Threads value ${wanted.threads}`);
    }
    if (wanted.hashMb !== this.applied.hashMb) {
      cmds.push(`setoption name Hash value ${wanted.hashMb}`);
    }
    if (wanted.multiPv !== this.applied.multiPv) {
      cmds.push(`setoption name MultiPV value ${wanted.multiPv}`);
    }
    if (cmds.length === 0) return;
    // Discard any stale transcript (e.g. an old readyok) before waiting on a
    // fresh one, so the wait reflects THIS option application.
    this.buffer = '';
    cmds.push('isready');
    this.send(cmds);
    await this.waitFor(/\breadyok\b/, READY_TIMEOUT_MS, 'ENGINE_TIMEOUT');
    this.applied = { ...wanted };
  }

  /**
   * Run one search on the warm process and resolve with the transcript that
   * accumulated since the search started (so stale lines from a previous
   * search can never leak into this parse).
   */
  async search(fen: string, goCommand: string, timeoutMs: number): Promise<string> {
    this.buffer = '';
    this.send(['ucinewgame', `position fen ${fen}`, goCommand]);
    return this.waitFor(/\bbestmove\b/, timeoutMs, 'ENGINE_TIMEOUT');
  }

  /** Mark the slot used; (re)arm the idle shutdown timer. */
  touchIdle(): void {
    if (this.idleTimer) clearTimeout(this.idleTimer);
    this.idleTimer = setTimeout(() => {
      // Never reap a slot mid-search; release() re-arms the timer afterwards.
      if (!this.busy) this.kill();
    }, IDLE_SHUTDOWN_MS);
    this.idleTimer.unref();
  }

  private send(cmds: string[]): void {
    if (!this.alive) return;
    try {
      this.child.stdin.write(cmds.map((c) => `${c}\n`).join(''));
    } catch {
      // stdin already closed — the close handler surfaces the real cause.
    }
  }

  private waitFor(test: RegExp, timeoutMs: number, timeoutCode: string): Promise<string> {
    if (!this.alive) {
      return Promise.reject(
        new ServiceUnavailableException({
          message: 'Engine process is not running.',
          code: 'ENGINE_UNAVAILABLE',
        }),
      );
    }
    return new Promise<string>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.waiter = undefined;
        // A stuck engine is unrecoverable for this slot; replace it.
        this.kill();
        reject(
          new ServiceUnavailableException({
            message: `Engine timed out after ${timeoutMs}ms.`,
            code: timeoutCode,
          }),
        );
      }, timeoutMs);
      timer.unref();
      this.waiter = { test, resolve, reject, timer };
      this.checkWaiter();
    });
  }

  private checkWaiter(): void {
    const w = this.waiter;
    if (!w || !w.test.test(this.buffer)) return;
    this.waiter = undefined;
    clearTimeout(w.timer);
    w.resolve(this.buffer);
  }

  /** Settle a pending waiter on shutdown/death, honoring a bestmove that made
   *  it into the buffer (an engine may legitimately exit right after printing
   *  bestmove — e.g. fake engines in tests, or a crash post-result). */
  private settleWaiter(reason: string): void {
    const w = this.waiter;
    this.waiter = undefined;
    if (!w) return;
    clearTimeout(w.timer);
    if (/\bbestmove\b/.test(this.buffer) && w.test.test(this.buffer)) {
      w.resolve(this.buffer);
    } else {
      w.reject(
        new ServiceUnavailableException({
          message: `${reason} without returning a best move.`,
          code: 'ENGINE_ERROR',
        }),
      );
    }
  }

  /** Process died (error/close): settle any pending waiter and leave the pool. */
  private die(reason: string): void {
    // Already dead (e.g. close after an explicit kill()): everything settled.
    if (!this.alive) return;
    this.alive = false;
    if (this.idleTimer) clearTimeout(this.idleTimer);
    this.settleWaiter(reason);
    this.onDeath(this);
  }

  /**
   * Politely quit, then escalate. Safe to call multiple times.
   *
   * Marks the slot dead IMMEDIATELY: a killed slot must never be handed to a
   * later request — the aborted search's late "bestmove" could otherwise land
   * in that request's transcript window and answer the WRONG position (which
   * the result cache would then pin).
   */
  kill(): void {
    if (this.idleTimer) clearTimeout(this.idleTimer);
    if (!this.alive) return;
    this.alive = false;
    this.settleWaiter('Engine shut down');
    const child = this.child;
    try {
      // Bypass send(): alive is already false. UCI engines exit on `quit`.
      child.stdin.write('quit\n');
    } catch {
      // stdin already closed — escalation below still applies.
    }
    const term = setTimeout(() => {
      if (child.exitCode === null && child.signalCode === null) child.kill('SIGTERM');
    }, 100);
    term.unref();
    const escalate = setTimeout(() => {
      // exitCode/signalCode (not `killed`, which is true once a signal is
      // merely SENT) tell us whether the process actually terminated.
      if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL');
    }, SIGTERM_GRACE_MS);
    escalate.unref();
  }
}

/**
 * Real Xiangqi engine backed by the Pikafish binary, driven over the UCI
 * protocol via a small pool of WARM, persistent child processes.
 *
 * Previously a fresh process was spawned per request, paying process startup +
 * NNUE network load (~50 MB) + hash allocation on every solve (hundreds of ms
 * to seconds on a small VPS). The pool pays that once per process and reuses
 * it: a warm search is just `ucinewgame / position / go`.
 *
 * Concurrency: at most ENGINE_POOL_SIZE engines run simultaneously; further
 * requests queue FIFO (bounded), which also bounds engine RAM/CPU on the host.
 * Idle engines shut down after IDLE_SHUTDOWN_MS to release memory.
 *
 * Search limits: when both depth and movetime are provided the engine receives
 * BOTH (`go depth D movetime M`) and stops at whichever bound it reaches
 * first, so a pathological position can no longer run unbounded by time.
 *
 * Security: the binary is spawned with an ARGS ARRAY (never a shell string),
 * so user-controlled FEN/move-time values can never inject shell commands.
 *
 * FEN board orientation is verified against the real binary in
 * pikafish-real-binary.integration.spec.ts (see FenService).
 */
@Injectable()
export class PikafishEngineService implements XiangqiEngine, OnModuleDestroy {
  readonly name = 'pikafish';
  private readonly logger = new Logger(PikafishEngineService.name);

  private readonly slots: EngineSlot[] = [];
  private readonly waitQueue: {
    resolve: (slot: EngineSlot) => void;
    reject: (err: Error) => void;
  }[] = [];

  constructor(private readonly config: ConfigService) {}

  async getBestMove(input: EngineBestMoveInput): Promise<EngineBestMoveResult> {
    const binaryPath = this.resolveBinaryPath();
    const nnuePath = this.resolveNnuePath();
    const engineCfg = this.config.get<AppConfig['engine']>('app.engine');
    const wanted: SearchOptions = {
      threads: input.threads ?? engineCfg?.threads ?? 1,
      hashMb: input.hashMb ?? engineCfg?.hashMb ?? 128,
      multiPv: input.multiPv ?? engineCfg?.multiPv ?? 1,
    };
    const timeoutMs = Math.max(input.moveTimeMs * 2 + 5000, 10_000);

    const slot = await this.acquire(binaryPath, nnuePath);
    try {
      await slot.applyOptions(wanted);
      const raw = await slot.search(input.fen, this.buildGoCommand(input), timeoutMs);
      return this.parse(raw, input);
    } finally {
      this.release(slot);
    }
  }

  /** Stop every warm engine and fail anything still waiting for one. */
  onModuleDestroy(): void {
    for (const slot of [...this.slots]) slot.kill();
    this.slots.length = 0;
    for (const waiter of this.waitQueue.splice(0)) {
      waiter.reject(
        new ServiceUnavailableException({
          message: 'Engine pool is shutting down.',
          code: 'ENGINE_UNAVAILABLE',
        }),
      );
    }
  }

  /** Both bounds when both are set: the engine stops at whichever hits first. */
  private buildGoCommand(input: EngineBestMoveInput): string {
    const depth = input.depth > 0 ? input.depth : 0;
    const moveTimeMs = input.moveTimeMs > 0 ? input.moveTimeMs : 0;
    if (depth && moveTimeMs) return `go depth ${depth} movetime ${moveTimeMs}`;
    if (depth) return `go depth ${depth}`;
    return `go movetime ${moveTimeMs || 1000}`;
  }

  /** Find or create a free warm engine, else queue (bounded FIFO). */
  private async acquire(binaryPath: string, nnuePath: string): Promise<EngineSlot> {
    // Drop any slots that died while idle.
    for (let i = this.slots.length - 1; i >= 0; i--) {
      if (!this.slots[i].alive) this.slots.splice(i, 1);
    }

    const free = this.slots.find((s) => !s.busy && s.alive);
    if (free) {
      free.busy = true;
      free.touchIdle();
      return free;
    }

    if (this.slots.length < this.poolSize()) {
      const slot = this.spawnSlot(binaryPath, nnuePath);
      slot.busy = true;
      this.slots.push(slot);
      try {
        await slot.ready;
      } catch (err) {
        slot.kill();
        this.removeSlot(slot);
        throw err instanceof ServiceUnavailableException
          ? err
          : new ServiceUnavailableException({
              message: `Failed to start Pikafish: ${(err as Error).message}`,
              code: 'ENGINE_UNAVAILABLE',
            });
      }
      return slot;
    }

    if (this.waitQueue.length >= MAX_QUEUE_DEPTH) {
      throw new ServiceUnavailableException({
        message: 'The engine is busy with too many analyses right now. Try again shortly.',
        code: 'ENGINE_BUSY',
      });
    }
    return new Promise<EngineSlot>((resolve, reject) => {
      this.waitQueue.push({
        resolve: (slot) => {
          slot.busy = true;
          slot.touchIdle();
          resolve(slot);
        },
        reject,
      });
    });
  }

  private release(slot: EngineSlot): void {
    slot.busy = false;
    slot.touchIdle();
    if (!slot.alive) {
      this.removeSlot(slot);
      // Capacity was freed by a death — the queue may need a fresh engine.
      this.dispatchQueue();
      return;
    }
    const next = this.waitQueue.shift();
    if (next) next.resolve(slot);
  }

  /**
   * Serve queued requests when capacity exists: hand over a free slot, or
   * spawn a replacement engine when a death dropped us below the pool size.
   */
  private dispatchQueue(): void {
    if (this.waitQueue.length === 0) return;
    const free = this.slots.find((s) => !s.busy && s.alive);
    if (free) {
      this.waitQueue.shift()?.resolve(free);
      return;
    }
    if (this.slots.length >= this.poolSize()) return;
    const next = this.waitQueue.shift();
    if (!next) return;
    try {
      const slot = this.spawnSlot(this.resolveBinaryPath(), this.resolveNnuePath());
      // Reserve BEFORE publishing to the pool: a concurrent acquire() must
      // never grab a slot whose UCI handshake is still in flight.
      slot.busy = true;
      this.slots.push(slot);
      slot.ready.then(
        () => next.resolve(slot),
        (err: Error) => {
          slot.kill();
          this.removeSlot(slot);
          next.reject(
            err instanceof ServiceUnavailableException
              ? err
              : new ServiceUnavailableException({
                  message: `Failed to start Pikafish: ${err.message}`,
                  code: 'ENGINE_UNAVAILABLE',
                }),
          );
        },
      );
    } catch (err) {
      next.reject(err as Error);
    }
  }

  private spawnSlot(binaryPath: string, nnuePath: string): EngineSlot {
    const engineCfg = this.config.get<AppConfig['engine']>('app.engine');
    const slot = new EngineSlot(
      binaryPath,
      nnuePath,
      engineCfg?.uciVariant ?? '',
      engineCfg?.moveOverheadMs ?? 10,
      (dead) => {
        this.removeSlot(dead);
        this.logger.warn('Warm engine process exited; it will be respawned on demand.');
        // A death may free capacity a queued request is waiting for.
        this.dispatchQueue();
      },
    );
    return slot;
  }

  private removeSlot(slot: EngineSlot): void {
    const i = this.slots.indexOf(slot);
    if (i >= 0) this.slots.splice(i, 1);
  }

  private poolSize(): number {
    const engine = this.config.get<AppConfig['engine']>('app.engine');
    return Math.max(1, engine?.poolSize ?? 2);
  }

  /** Ensure the configured binary exists and is executable, else fail clearly. */
  private resolveBinaryPath(): string {
    const engine = this.config.get<AppConfig['engine']>('app.engine');
    const path = engine?.pikafishBinaryPath ?? '';
    if (!path) {
      throw new ServiceUnavailableException({
        message:
          'Pikafish binary path is not configured. Set PIKAFISH_BINARY_PATH or use ENGINE_PROVIDER=mock.',
        code: 'ENGINE_UNAVAILABLE',
      });
    }
    if (!existsSync(path)) {
      throw new ServiceUnavailableException({
        message: `Pikafish binary not found at "${path}". Fix PIKAFISH_BINARY_PATH or use ENGINE_PROVIDER=mock.`,
        code: 'ENGINE_UNAVAILABLE',
      });
    }
    // Catch the common EACCES cause up front with actionable guidance: a binary
    // that is not marked executable, or one for the wrong OS/architecture
    // (e.g. a Linux build pointed at on macOS).
    try {
      accessSync(path, fsConstants.X_OK);
    } catch {
      throw new ServiceUnavailableException({
        message:
          `Pikafish binary at "${path}" is not executable. Run "chmod +x" on it, ` +
          'remove any download quarantine (macOS: xattr -d com.apple.quarantine <file>), ' +
          "and make sure it matches this machine's OS/architecture.",
        code: 'ENGINE_NOT_EXECUTABLE',
      });
    }
    return path;
  }

  /**
   * Resolve the NNUE network path. Optional: when empty, Pikafish falls back to
   * a "pikafish.nnue" relative to its working directory (we set the child's cwd
   * to the binary's directory). When set, it must exist.
   */
  private resolveNnuePath(): string {
    const engine = this.config.get<AppConfig['engine']>('app.engine');
    const path = engine?.pikafishNnuePath ?? '';
    if (path && !existsSync(path)) {
      throw new ServiceUnavailableException({
        message: `Pikafish NNUE network not found at "${path}". Fix PIKAFISH_NNUE_PATH (point it at pikafish.nnue) or leave it empty.`,
        code: 'ENGINE_UNAVAILABLE',
      });
    }
    return path;
  }

  /** Parse "bestmove" + the (possibly multi-PV) "info" lines from stdout. */
  private parse(raw: string, input: EngineBestMoveInput): EngineBestMoveResult {
    const bestMoveMatch = raw.match(/bestmove\s+(\S+)(?:\s+ponder\s+(\S+))?/);
    if (!bestMoveMatch || bestMoveMatch[1] === '(none)') {
      throw new ServiceUnavailableException({
        message: 'Pikafish did not return a legal move for this position.',
        code: 'ENGINE_NO_MOVE',
      });
    }

    const uci = bestMoveMatch[1];
    const ponder = bestMoveMatch[2];

    let from;
    let to;
    try {
      ({ from, to } = uciToMove(uci));
    } catch (err) {
      this.logger.error(`Unparseable bestmove "${uci}" from Pikafish`);
      throw new ServiceUnavailableException({
        message: `Pikafish returned an unparseable move "${uci}".`,
        code: 'ENGINE_BAD_MOVE',
        details: (err as Error).message,
      });
    }

    // Keep the deepest info line per multipv index; index 1 is the principal
    // variation, which gives the primary score/depth.
    const byIndex = this.collectPvLines(raw);
    const primary = byIndex.get(1);
    const candidates = this.buildMoveLines(byIndex);

    return {
      uci,
      from,
      to,
      score: primary?.score ?? '0.00',
      depth: primary?.depth ?? input.depth,
      ...(ponder ? { ponder } : {}),
      // Only surface MultiPV when more than one line was requested/returned.
      ...(candidates.length > 1 ? { multipv: candidates } : {}),
      raw,
    };
  }

  /** Deepest "info ... score ... pv" line per multipv index. */
  private collectPvLines(
    raw: string,
  ): Map<number, { score: string; depth: number; moveUci: string }> {
    const byIndex = new Map<number, { score: string; depth: number; moveUci: string }>();
    for (const line of raw.split('\n')) {
      if (!line.startsWith('info') || !/\bscore\b/.test(line)) continue;
      const idx = Number(line.match(/\bmultipv\s+(\d+)/)?.[1] ?? '1');
      const depth = Number(line.match(/\bdepth\s+(\d+)/)?.[1] ?? '0');
      const moveUci = line.match(/\bpv\s+(\S+)/)?.[1] ?? '';
      const prev = byIndex.get(idx);
      if (!prev || depth >= prev.depth) {
        byIndex.set(idx, { score: this.scoreFromInfo(line), depth, moveUci });
      }
    }
    return byIndex;
  }

  /** Build ranked candidate lines (index 0 = best) from the collected pv lines. */
  private buildMoveLines(
    byIndex: Map<number, { score: string; depth: number; moveUci: string }>,
  ): EngineMoveLine[] {
    const lines: EngineMoveLine[] = [];
    for (const idx of [...byIndex.keys()].sort((a, b) => a - b)) {
      const entry = byIndex.get(idx);
      if (!entry || !entry.moveUci) continue;
      try {
        const { from, to } = uciToMove(entry.moveUci);
        lines.push({ uci: entry.moveUci, from, to, score: entry.score, depth: entry.depth });
      } catch {
        // Skip an unparseable candidate rather than failing the whole analysis.
      }
    }
    return lines;
  }

  /** Convert a single info line's score field (cp/mate) to a display string. */
  private scoreFromInfo(line: string): string {
    const cp = line.match(/\bscore\s+cp\s+(-?\d+)/);
    if (cp) {
      const pawns = Number(cp[1]) / 100;
      return `${pawns >= 0 ? '+' : ''}${pawns.toFixed(2)}`;
    }
    const mate = line.match(/\bscore\s+mate\s+(-?\d+)/);
    if (mate) return `mate ${mate[1]}`;
    return '0.00';
  }
}
