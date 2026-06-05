import { spawn, ChildProcessWithoutNullStreams } from 'node:child_process';
import { accessSync, constants as fsConstants, existsSync } from 'node:fs';
import { dirname } from 'node:path';
import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
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

/**
 * Real Xiangqi engine backed by the Pikafish binary, driven over the UCI
 * protocol via a spawned child process.
 *
 * Security: the binary is spawned with an ARGS ARRAY (never a shell string),
 * so user-controlled FEN/move-time values can never inject shell commands.
 *
 * Lifecycle per query: uci -> uciok -> isready -> readyok ->
 * position fen <fen> -> go {depth N | movetime M} -> read until "bestmove".
 * A hard timeout kills the child (SIGTERM, then SIGKILL after a grace).
 *
 * FEN board orientation is verified against the real binary in
 * pikafish-real-binary.integration.spec.ts (see FenService).
 */
@Injectable()
export class PikafishEngineService implements XiangqiEngine {
  readonly name = 'pikafish';
  private readonly logger = new Logger(PikafishEngineService.name);

  constructor(private readonly config: ConfigService) {}

  async getBestMove(input: EngineBestMoveInput): Promise<EngineBestMoveResult> {
    const binaryPath = this.resolveBinaryPath();
    const nnuePath = this.resolveNnuePath();
    const raw = await this.runUci(binaryPath, nnuePath, input);
    return this.parse(raw, input);
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

  /**
   * Spawn the engine, perform the UCI handshake, request a best move, and
   * resolve with the full stdout transcript. Always kills the child.
   */
  private runUci(
    binaryPath: string,
    nnuePath: string,
    input: EngineBestMoveInput,
  ): Promise<string> {
    const timeoutMs = Math.max(input.moveTimeMs * 2 + 5000, 10_000);
    const engineCfg = this.config.get<AppConfig['engine']>('app.engine');
    const threads = input.threads ?? engineCfg?.threads ?? 1;
    const hashMb = input.hashMb ?? engineCfg?.hashMb ?? 128;
    const multiPv = input.multiPv ?? engineCfg?.multiPv ?? 1;
    const moveOverheadMs = input.moveOverheadMs ?? engineCfg?.moveOverheadMs ?? 10;

    return new Promise<string>((resolve, reject) => {
      let child: ChildProcessWithoutNullStreams;
      try {
        // ARGS ARRAY, no shell: no command injection possible. cwd is the
        // binary's directory so a co-located "pikafish.nnue" resolves by default.
        child = spawn(binaryPath, [], { stdio: 'pipe', cwd: dirname(binaryPath) });
      } catch (err) {
        reject(
          new ServiceUnavailableException({
            message: `Failed to start Pikafish: ${(err as Error).message}`,
            code: 'ENGINE_UNAVAILABLE',
          }),
        );
        return;
      }

      let stdout = '';
      let settled = false;
      let killTimer: NodeJS.Timeout | undefined;

      const cleanup = (): void => {
        if (killTimer) clearTimeout(killTimer);
        clearTimeout(timer);
        if (!child.killed) {
          child.kill('SIGTERM');
          // Escalate to SIGKILL if it ignores SIGTERM.
          setTimeout(() => {
            if (!child.killed) child.kill('SIGKILL');
          }, SIGTERM_GRACE_MS).unref();
        }
      };

      const finish = (fn: () => void): void => {
        if (settled) return;
        settled = true;
        cleanup();
        fn();
      };

      const timer = setTimeout(() => {
        finish(() =>
          reject(
            new ServiceUnavailableException({
              message: `Pikafish timed out after ${timeoutMs}ms.`,
              code: 'ENGINE_TIMEOUT',
            }),
          ),
        );
      }, timeoutMs);
      timer.unref();

      const send = (cmd: string): void => {
        child.stdin.write(`${cmd}\n`);
      };

      let phase: 'uci' | 'ready' | 'search' = 'uci';

      child.stdout.setEncoding('utf8');
      child.stdout.on('data', (chunk: string) => {
        stdout += chunk;

        if (phase === 'uci' && /\buciok\b/.test(stdout)) {
          phase = 'ready';
          // Apply UCI options BEFORE isready: the engine reallocates on Hash/
          // Threads changes and blocks on isready until they take effect.
          // (Pikafish has no Skill/Elo option — strength is depth/movetime only.)
          if (nnuePath) send(`setoption name EvalFile value ${nnuePath}`);
          send(`setoption name Threads value ${threads}`);
          send(`setoption name Hash value ${hashMb}`);
          send(`setoption name MultiPV value ${multiPv}`);
          send(`setoption name Move Overhead value ${moveOverheadMs}`);
          send('isready');
        }
        if (phase === 'ready' && /\breadyok\b/.test(stdout)) {
          phase = 'search';
          // Fresh search state for this independent position, then analyze.
          send('ucinewgame');
          send(`position fen ${input.fen}`);
          send(input.depth > 0 ? `go depth ${input.depth}` : `go movetime ${input.moveTimeMs}`);
        }
        if (phase === 'search' && /\bbestmove\b/.test(stdout)) {
          finish(() => resolve(stdout));
        }
      });

      child.on('error', (err) => {
        finish(() =>
          reject(
            new ServiceUnavailableException({
              message: `Pikafish process error: ${err.message}`,
              code: 'ENGINE_UNAVAILABLE',
            }),
          ),
        );
      });

      child.on('close', (code) => {
        finish(() => {
          if (/\bbestmove\b/.test(stdout)) {
            resolve(stdout);
          } else {
            reject(
              new ServiceUnavailableException({
                message: `Pikafish exited (code ${code}) without returning a best move.`,
                code: 'ENGINE_ERROR',
              }),
            );
          }
        });
      });

      // Kick off the handshake.
      send('uci');
    });
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
