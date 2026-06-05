import { detectImageType } from './image-type.util';

describe('detectImageType', () => {
  const png = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC',
    'base64',
  );

  it('detects PNG by signature', () => {
    expect(detectImageType(png)).toBe('image/png');
  });

  it('detects JPEG by SOI + marker', () => {
    const jpeg = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(12)]);
    expect(detectImageType(jpeg)).toBe('image/jpeg');
  });

  it('detects WEBP by RIFF/WEBP container', () => {
    const webp = Buffer.concat([
      Buffer.from('RIFF', 'ascii'),
      Buffer.from([0, 0, 0, 0]),
      Buffer.from('WEBP', 'ascii'),
    ]);
    expect(detectImageType(webp)).toBe('image/webp');
  });

  it('detects GIF by header', () => {
    const gif = Buffer.concat([Buffer.from('GIF89a', 'ascii'), Buffer.alloc(8)]);
    expect(detectImageType(gif)).toBe('image/gif');
  });

  it('returns null for non-image bytes', () => {
    expect(detectImageType(Buffer.from('not an image at all, just text'))).toBeNull();
  });

  it('returns null for too-short buffers', () => {
    expect(detectImageType(Buffer.from([0x89, 0x50]))).toBeNull();
  });
});
