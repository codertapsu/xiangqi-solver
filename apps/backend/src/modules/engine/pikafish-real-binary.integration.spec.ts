import { accessSync, constants as fsConstants, existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { ConfigService } from '@nestjs/config';
import { PikafishEngineService } from './pikafish-engine.service';
import { uciToMove } from './uci.util';
import { AppConfig } from '../../config/configuration';
import { START_POSITION_FEN } from '../board/xiangqi.types';

/**
 * REAL Pikafish binary integration test — orientation & sanity check.
 *
 * Goal: prove that the FEN we generate is the position Pikafish actually
 * recognizes (i.e. our coordinate <-> FEN orientation matches the engine), by
 * feeding known positions to the real binary and checking the moves it returns
 * map back onto the squares we expect.
 *
 * This test is OPT-IN and self-skips unless a runnable binary is configured. It
 * reads PIKAFISH_BINARY_PATH / PIKAFISH_NNUE_PATH from the environment, falling
 * back to the values in apps/backend/.env so a developer who has Pikafish set
 * up gets real coverage from a plain `npm test`. CI without the binary skips.
 */

interface PikafishEnv {
  binaryPath: string;
  nnuePath: string;
}

/** Minimal .env reader (no dotenv dependency) for the two keys we care about. */
function readEnvFallback(): Record<string, string> {
  const envPath = join(__dirname, '..', '..', '..', '.env');
  if (!existsSync(envPath)) return {};
  const out: Record<string, string> = {};
  for (const line of readFileSync(envPath, 'utf8').split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    let value = trimmed.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    out[key] = value;
  }
  return out;
}

function resolvePikafishEnv(): PikafishEnv {
  const fallback = readEnvFallback();
  return {
    binaryPath: process.env.PIKAFISH_BINARY_PATH || fallback.PIKAFISH_BINARY_PATH || '',
    nnuePath: process.env.PIKAFISH_NNUE_PATH || fallback.PIKAFISH_NNUE_PATH || '',
  };
}

function isRunnable(binaryPath: string): boolean {
  if (!binaryPath || !existsSync(binaryPath)) return false;
  try {
    accessSync(binaryPath, fsConstants.X_OK);
    return true;
  } catch {
    return false;
  }
}

const pikafish = resolvePikafishEnv();
const runnable = isRunnable(pikafish.binaryPath);

// Choose describe vs describe.skip at collection time so CI stays green.
const describeReal = runnable ? describe : describe.skip;

if (!runnable) {
  console.warn(
    '[pikafish-real-binary] SKIPPED — set PIKAFISH_BINARY_PATH (and PIKAFISH_NNUE_PATH) ' +
      'to an executable Pikafish build to run the real-engine orientation check.',
  );
}

function configWith(env: PikafishEnv): ConfigService {
  return {
    get: (key: string): unknown => {
      if (key === 'app.engine') {
        return {
          provider: 'pikafish',
          pikafishBinaryPath: env.binaryPath,
          pikafishNnuePath: env.nnuePath,
          defaultDepth: 12,
          defaultMoveTimeMs: 1000,
        } as AppConfig['engine'];
      }
      return undefined;
    },
  } as unknown as ConfigService;
}

describeReal('PikafishEngineService (REAL binary orientation check)', () => {
  // Real searches can take a moment on first NNUE load; give them headroom.
  const TIMEOUT = 30_000;
  let engine: PikafishEngineService;

  beforeAll(() => {
    engine = new PikafishEngineService(configWith(pikafish));
  });

  it(
    "accepts our start-position FEN and Red moves from Red's half (low ranks)",
    async () => {
      const result = await engine.getBestMove({
        fen: START_POSITION_FEN, // ends with " w " -> Red to move
        sideToMove: 'red',
        depth: 12,
        moveTimeMs: 1000,
      });

      // A real, parseable opening move came back.
      expect(result.uci).toMatch(/^[a-i][0-9][a-i][0-9]$/);
      const { from, to } = uciToMove(result.uci);

      // Orientation invariant: every legal Red opening move ORIGINATES on
      // Red's half of the board, which in our coords is rank 0..4 (rank 0 =
      // Red home). If the FEN were mirrored, Red's move would start high.
      expect(from.rank).toBeLessThanOrEqual(4);
      expect(from.rank).toBeGreaterThanOrEqual(0);
      expect(to.rank).toBeGreaterThanOrEqual(0);
      expect(to.rank).toBeLessThanOrEqual(9);
    },
    TIMEOUT,
  );

  it(
    "with Black to move, Black moves from Black's half (high ranks)",
    async () => {
      const blackToMove = START_POSITION_FEN.replace(' w ', ' b ');
      const result = await engine.getBestMove({
        fen: blackToMove,
        sideToMove: 'black',
        depth: 12,
        moveTimeMs: 1000,
      });

      expect(result.uci).toMatch(/^[a-i][0-9][a-i][0-9]$/);
      const { from } = uciToMove(result.uci);

      // Black's army lives on ranks 5..9 in our coords (rank 9 = Black home).
      expect(from.rank).toBeGreaterThanOrEqual(5);
      expect(from.rank).toBeLessThanOrEqual(9);
    },
    TIMEOUT,
  );

  it(
    'returns the only legal move, mapping squares exactly (move-mapping sanity)',
    async () => {
      // A position with EXACTLY ONE legal move (engine-taste-independent):
      // Red king on e0 is in check from a Black rook on a0 (along rank 0). The
      // only escape is e0 -> e1; d0/f0 stay on the checked rank and Red has no
      // piece to block or capture. Black king sits at i9 (off the e-file) so
      // e0e1 is not a flying-general violation. The engine MUST answer e0e1,
      // which pins file/rank <-> UCI square mapping against the real binary.
      //   rank9 "8k"   (Black king i9 / file 8)
      //   rank0 "r3K4" (Black rook a0 / file 0, Red king e0 / file 4)
      const fen = '8k/9/9/9/9/9/9/9/9/r3K4 w - - 0 1';
      const result = await engine.getBestMove({
        fen,
        sideToMove: 'red',
        depth: 14,
        moveTimeMs: 1000,
      });

      expect(result.uci).toBe('e0e1');
      expect(result.from).toEqual({ file: 4, rank: 0 }); // 'e0'
      expect(result.to).toEqual({ file: 4, rank: 1 }); // 'e1' (toward Black)
    },
    TIMEOUT,
  );
});
