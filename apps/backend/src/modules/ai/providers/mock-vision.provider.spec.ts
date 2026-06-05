import { MockVisionProvider } from './mock-vision.provider';

describe('MockVisionProvider', () => {
  let provider: MockVisionProvider;
  const image = { imageBuffer: Buffer.from('not-a-real-image'), mimeType: 'image/png' };

  beforeEach(() => {
    provider = new MockVisionProvider();
  });

  it('detects the standard 32-piece start position', async () => {
    const result = await provider.extractBoardState(image);
    expect(result.boardDetected).toBe(true);
    expect(result.pieces).toHaveLength(32);
    expect(result.confidence).toBeCloseTo(0.9, 5);
    expect(result.warnings).toEqual([]);
  });

  it('contains exactly one king per color', async () => {
    const { pieces } = await provider.extractBoardState(image);
    expect(pieces.filter((p) => p.type === 'king' && p.color === 'red')).toHaveLength(1);
    expect(pieces.filter((p) => p.type === 'king' && p.color === 'black')).toHaveLength(1);
  });

  it('defaults side to move to red when no hint is given', async () => {
    const result = await provider.extractBoardState(image);
    expect(result.sideToMove).toBe('red');
  });

  it('honors a side-to-move hint', async () => {
    const result = await provider.extractBoardState({ ...image, sideToMoveHint: 'black' });
    expect(result.sideToMove).toBe('black');
  });

  it('ignores an "unknown" hint and falls back to red', async () => {
    const result = await provider.extractBoardState({ ...image, sideToMoveHint: 'unknown' });
    expect(result.sideToMove).toBe('red');
  });

  it('is deterministic across calls', async () => {
    const a = await provider.extractBoardState(image);
    const b = await provider.extractBoardState(image);
    expect(a).toEqual(b);
  });
});
