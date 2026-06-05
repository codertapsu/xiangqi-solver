import { MoveNotationService } from './move-notation.service';
import { NormalizedPiece, PieceColor, PieceType } from './xiangqi.types';

const piece = (
  color: PieceColor,
  type: PieceType,
  file: number,
  rank: number,
): NormalizedPiece => ({
  color,
  type,
  position: { file, rank },
});

describe('MoveNotationService', () => {
  let svc: MoveNotationService;
  beforeEach(() => {
    svc = new MoveNotationService();
  });

  it('describes the central cannon (炮二平五) across languages', () => {
    const pieces = [piece('red', 'cannon', 7, 2)]; // Red file 2
    const from = { file: 7, rank: 2 };
    const to = { file: 4, rank: 2 }; // traverse to centre (file 5)

    expect(svc.describe({ from, to, pieces, language: 'en' })).toEqual({
      human: 'Cannon 2 traverses to 5',
      wxf: 'C2=5',
    });
    expect(svc.describe({ from, to, pieces, language: 'vi' }).human).toBe('Pháo 2 bình 5');
    expect(svc.describe({ from, to, pieces, language: 'zh' }).human).toBe('炮二平五');
  });

  it('describes a horse advance (馬八進七) — value is the destination file', () => {
    const pieces = [piece('red', 'horse', 1, 0)]; // Red file 8
    const r = svc.describe({
      from: { file: 1, rank: 0 },
      to: { file: 2, rank: 2 },
      pieces,
      language: 'en',
    });
    expect(r).toEqual({ human: 'Horse 8 advances to 7', wxf: 'H8+7' });
    expect(
      svc.describe({ from: { file: 1, rank: 0 }, to: { file: 2, rank: 2 }, pieces, language: 'zh' })
        .human,
    ).toBe('傌八進七');
  });

  it('describes a vertical king advance (帥五進一) — value is a step count', () => {
    const pieces = [piece('red', 'king', 4, 0)];
    const r = svc.describe({
      from: { file: 4, rank: 0 },
      to: { file: 4, rank: 1 },
      pieces,
      language: 'en',
    });
    expect(r).toEqual({ human: 'King 5 advances 1', wxf: 'K5+1' });
    expect(
      svc.describe({ from: { file: 4, rank: 0 }, to: { file: 4, rank: 1 }, pieces, language: 'zh' })
        .human,
    ).toBe('帥五進一');
  });

  it('describes a rook retreat (steps)', () => {
    const pieces = [piece('red', 'rook', 0, 3)];
    const r = svc.describe({
      from: { file: 0, rank: 3 },
      to: { file: 0, rank: 1 },
      pieces,
      language: 'en',
    });
    expect(r).toEqual({ human: 'Rook 9 retreats 2', wxf: 'R9-2' });
  });

  it('disambiguates two pieces on the same file with front/rear', () => {
    const pieces = [piece('red', 'rook', 0, 0), piece('red', 'rook', 0, 3)];
    // Move the FRONT rook (higher rank, closer to the enemy) forward.
    const front = svc.describe({
      from: { file: 0, rank: 3 },
      to: { file: 0, rank: 5 },
      pieces,
      language: 'en',
    });
    expect(front).toEqual({ human: 'Front rook advances 2', wxf: '+R+2' });
    expect(
      svc.describe({ from: { file: 0, rank: 3 }, to: { file: 0, rank: 5 }, pieces, language: 'zh' })
        .human,
    ).toBe('前俥進二');

    // Move the REAR rook.
    const rear = svc.describe({
      from: { file: 0, rank: 0 },
      to: { file: 0, rank: 1 },
      pieces,
      language: 'en',
    });
    expect(rear).toEqual({ human: 'Rear rook advances 1', wxf: '-R+1' });
  });

  it('uses Arabic numerals for Black in Chinese notation', () => {
    const pieces = [piece('black', 'cannon', 1, 7)]; // Black file 2
    const r = svc.describe({
      from: { file: 1, rank: 7 },
      to: { file: 4, rank: 7 },
      pieces,
      language: 'zh',
    });
    expect(r.human).toBe('砲2平5');
    expect(r.wxf).toBe('C2=5');
  });

  it('falls back to coordinates when the moving piece is unknown', () => {
    const r = svc.describe({
      from: { file: 1, rank: 2 },
      to: { file: 4, rank: 2 },
      pieces: [],
      language: 'en',
    });
    expect(r.human).toContain('→');
  });
});
