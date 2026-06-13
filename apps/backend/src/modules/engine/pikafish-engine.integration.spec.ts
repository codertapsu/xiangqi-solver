import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PikafishEngineService } from './pikafish-engine.service';
import { AppConfig } from '../../config/configuration';

/**
 * Drives PikafishEngineService against a tiny FAKE UCI engine (a shell script)
 * so the spawn -> handshake -> parse pipeline is exercised end-to-end WITHOUT
 * the real Pikafish binary. This covers the UCI transcript parsing (bestmove,
 * score cp/mate, depth) that unit-mocking cannot reach.
 *
 * Skipped automatically on platforms without /bin/sh (e.g. native Windows).
 */
const hasPosixShell = process.platform !== 'win32';
const describePosix = hasPosixShell ? describe : describe.skip;

const FEN = 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1';

function configWith(binaryPath: string): ConfigService {
  return configWithPool(binaryPath, 2);
}

function configWithPool(binaryPath: string, poolSize: number): ConfigService {
  return {
    get: (key: string): unknown => {
      if (key === 'app.engine') {
        return {
          provider: 'pikafish',
          pikafishBinaryPath: binaryPath,
          defaultDepth: 5,
          defaultMoveTimeMs: 100,
          poolSize,
        } as AppConfig['engine'];
      }
      return undefined;
    },
  } as unknown as ConfigService;
}

describePosix('PikafishEngineService (fake UCI engine integration)', () => {
  let dir: string;

  beforeAll(() => {
    dir = mkdtempSync(join(tmpdir(), 'fake-pikafish-'));
  });

  afterAll(() => {
    rmSync(dir, { recursive: true, force: true });
  });

  /** Write an executable shell script that emulates a UCI engine. */
  function writeFakeEngine(name: string, script: string): string {
    const path = join(dir, name);
    writeFileSync(path, script, { mode: 0o755 });
    chmodSync(path, 0o755);
    return path;
  }

  it('completes the UCI handshake and parses bestmove + centipawn score', async () => {
    const path = writeFakeEngine(
      'engine-cp.sh',
      [
        '#!/bin/sh',
        'while IFS= read -r line; do',
        '  case "$line" in',
        '    uci) echo "id name FakeFish"; echo "uciok" ;;',
        '    isready) echo "readyok" ;;',
        '    go*)',
        '      echo "info depth 5 score cp 42 pv b2e2"',
        '      echo "bestmove b2e2 ponder h9g7"',
        '      ;;',
        '    quit) exit 0 ;;',
        '  esac',
        'done',
      ].join('\n') + '\n',
    );

    const engine = new PikafishEngineService(configWith(path));
    const result = await engine.getBestMove({
      fen: FEN,
      sideToMove: 'red',
      depth: 5,
      moveTimeMs: 100,
    });

    expect(result.uci).toBe('b2e2');
    expect(result.from).toEqual({ file: 1, rank: 2 });
    expect(result.to).toEqual({ file: 4, rank: 2 });
    expect(result.score).toBe('+0.42');
    expect(result.depth).toBe(5);
    expect(result.ponder).toBe('h9g7');
  });

  it('formats a mate score', async () => {
    const path = writeFakeEngine(
      'engine-mate.sh',
      [
        '#!/bin/sh',
        'while IFS= read -r line; do',
        '  case "$line" in',
        '    uci) echo "uciok" ;;',
        '    isready) echo "readyok" ;;',
        '    go*) echo "info depth 9 score mate 3"; echo "bestmove e1e2" ;;',
        '    quit) exit 0 ;;',
        '  esac',
        'done',
      ].join('\n') + '\n',
    );

    const engine = new PikafishEngineService(configWith(path));
    const result = await engine.getBestMove({
      fen: FEN,
      sideToMove: 'red',
      depth: 9,
      moveTimeMs: 100,
    });

    expect(result.score).toBe('mate 3');
    expect(result.uci).toBe('e1e2');
  });

  it('rejects when the engine reports no legal move (bestmove (none))', async () => {
    const path = writeFakeEngine(
      'engine-none.sh',
      [
        '#!/bin/sh',
        'while IFS= read -r line; do',
        '  case "$line" in',
        '    uci) echo "uciok" ;;',
        '    isready) echo "readyok" ;;',
        '    go*) echo "bestmove (none)" ;;',
        '    quit) exit 0 ;;',
        '  esac',
        'done',
      ].join('\n') + '\n',
    );

    const engine = new PikafishEngineService(configWith(path));
    await expect(
      engine.getBestMove({ fen: FEN, sideToMove: 'red', depth: 5, moveTimeMs: 100 }),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
  });

  it('parses MultiPV candidate lines and takes the primary score from multipv 1', async () => {
    const path = writeFakeEngine(
      'engine-multipv.sh',
      [
        '#!/bin/sh',
        'while IFS= read -r line; do',
        '  case "$line" in',
        '    uci) echo "uciok" ;;',
        '    isready) echo "readyok" ;;',
        '    go*)',
        '      echo "info depth 12 multipv 1 score cp 30 pv b2e2 h9g7"',
        '      echo "info depth 12 multipv 2 score cp 15 pv h2e2 h9g7"',
        '      echo "info depth 12 multipv 3 score cp -5 pv b0c2"',
        '      echo "bestmove b2e2 ponder h9g7"',
        '      ;;',
        '    quit) exit 0 ;;',
        '  esac',
        'done',
      ].join('\n') + '\n',
    );

    const engine = new PikafishEngineService(configWith(path));
    const result = await engine.getBestMove({
      fen: FEN,
      sideToMove: 'red',
      depth: 12,
      moveTimeMs: 100,
      multiPv: 3,
    });

    // Primary score comes from multipv 1, NOT the last info line (multipv 3).
    expect(result.uci).toBe('b2e2');
    expect(result.score).toBe('+0.30');
    expect(result.multipv).toHaveLength(3);
    expect(result.multipv?.[0]).toMatchObject({ uci: 'b2e2', score: '+0.30' });
    expect(result.multipv?.[1]).toMatchObject({ uci: 'h2e2', score: '+0.15' });
    expect(result.multipv?.[2]).toMatchObject({ uci: 'b0c2', score: '-0.05' });
  });
});

describePosix('PikafishEngineService warm pool', () => {
  let dir: string;

  beforeAll(() => {
    dir = mkdtempSync(join(tmpdir(), 'fake-pikafish-pool-'));
  });

  afterAll(() => {
    rmSync(dir, { recursive: true, force: true });
  });

  function writeCountingEngine(
    name: string,
    opts?: { sleepOnGo?: boolean },
  ): {
    path: string;
    spawnCountFile: string;
  } {
    const path = join(dir, name);
    const spawnCountFile = join(dir, `${name}.spawns`);
    writeFileSync(
      path,
      [
        '#!/bin/sh',
        `echo spawn >> "${spawnCountFile}"`,
        'while IFS= read -r line; do',
        '  case "$line" in',
        '    uci) echo "uciok" ;;',
        '    isready) echo "readyok" ;;',
        '    go*)',
        ...(opts?.sleepOnGo ? ['      sleep 0.2'] : []),
        // Echo the exact go command back so tests can assert the search limits.
        '      echo "info depth 5 score cp 42 pv b2e2 string cmd[$line]"',
        '      echo "bestmove b2e2"',
        '      ;;',
        '    quit) exit 0 ;;',
        '  esac',
        'done',
      ].join('\n') + '\n',
      { mode: 0o755 },
    );
    chmodSync(path, 0o755);
    return { path, spawnCountFile };
  }

  const spawnsIn = (file: string): number => {
    try {
      return readFileSync(file, 'utf8').split('\n').filter(Boolean).length;
    } catch {
      return 0;
    }
  };

  it('reuses ONE warm process across sequential searches', async () => {
    const { path, spawnCountFile } = writeCountingEngine('engine-warm.sh');
    const engine = new PikafishEngineService(configWith(path));
    try {
      for (let i = 0; i < 3; i++) {
        const result = await engine.getBestMove({
          fen: FEN,
          sideToMove: 'red',
          depth: 5,
          moveTimeMs: 100,
        });
        expect(result.uci).toBe('b2e2');
      }
      expect(spawnsIn(spawnCountFile)).toBe(1);
    } finally {
      engine.onModuleDestroy();
    }
  });

  it('sends BOTH bounds: go depth N movetime M', async () => {
    const { path } = writeCountingEngine('engine-cmd.sh');
    const engine = new PikafishEngineService(configWith(path));
    try {
      const result = await engine.getBestMove({
        fen: FEN,
        sideToMove: 'red',
        depth: 7,
        moveTimeMs: 250,
      });
      expect(result.raw).toContain('cmd[go depth 7 movetime 250]');
    } finally {
      engine.onModuleDestroy();
    }
  });

  it('serializes concurrent searches through the bounded pool', async () => {
    const { path, spawnCountFile } = writeCountingEngine('engine-queue.sh', { sleepOnGo: true });
    const engine = new PikafishEngineService(configWithPool(path, 1));
    try {
      const results = await Promise.all(
        Array.from({ length: 3 }, () =>
          engine.getBestMove({ fen: FEN, sideToMove: 'red', depth: 5, moveTimeMs: 100 }),
        ),
      );
      expect(results.every((r) => r.uci === 'b2e2')).toBe(true);
      // Pool size 1 -> a single process served all three queued searches.
      expect(spawnsIn(spawnCountFile)).toBe(1);
    } finally {
      engine.onModuleDestroy();
    }
  });

  it('respawns on demand after the warm process dies', async () => {
    const { path, spawnCountFile } = writeCountingEngine('engine-respawn.sh');
    const engine = new PikafishEngineService(configWith(path));
    try {
      await engine.getBestMove({ fen: FEN, sideToMove: 'red', depth: 5, moveTimeMs: 100 });
      // Kill the warm engine behind the pool's back.
      engine.onModuleDestroy();
      const result = await engine.getBestMove({
        fen: FEN,
        sideToMove: 'red',
        depth: 5,
        moveTimeMs: 100,
      });
      expect(result.uci).toBe('b2e2');
      expect(spawnsIn(spawnCountFile)).toBe(2);
    } finally {
      engine.onModuleDestroy();
    }
  });
});
