import { Injectable } from '@nestjs/common';
import { BoardPosition, NormalizedPiece, PieceColor, PieceType } from './xiangqi.types';

/** Languages the descriptive move notation is available in. */
export type NotationLanguage = 'en' | 'vi' | 'zh';

export interface DescribeMoveInput {
  from: BoardPosition;
  to: BoardPosition;
  /** The board BEFORE the move (used to find the moving piece + disambiguate). */
  pieces: NormalizedPiece[];
  language: NotationLanguage;
}

export interface MoveDescription {
  /** Localized, human-readable traditional notation, e.g. "Cannon 8 traverses to 5". */
  human: string;
  /** Universal WXF code, e.g. "C8=5", "H8+7", "+R=4". */
  wxf: string;
}

type Direction = 'advance' | 'retreat' | 'traverse';
type Disambiguation = 'front' | 'rear' | null;

/** Pieces that move diagonally / in an L: their value is always a destination file. */
const DIAGONAL_TYPES: ReadonlySet<PieceType> = new Set<PieceType>(['horse', 'elephant', 'advisor']);

const WXF_LETTER: Record<PieceType, string> = {
  king: 'K',
  advisor: 'A',
  elephant: 'E',
  horse: 'H',
  rook: 'R',
  cannon: 'C',
  pawn: 'P',
};

const PIECE_NAME_EN: Record<PieceType, string> = {
  king: 'King',
  advisor: 'Advisor',
  elephant: 'Elephant',
  horse: 'Horse',
  rook: 'Rook',
  cannon: 'Cannon',
  pawn: 'Pawn',
};

const PIECE_NAME_VI: Record<PieceType, string> = {
  king: 'Tướng',
  advisor: 'Sĩ',
  elephant: 'Tượng',
  horse: 'Mã',
  rook: 'Xe',
  cannon: 'Pháo',
  pawn: 'Tốt',
};

// Chinese piece names differ by colour (the classic 俥/車 etc. distinction).
const PIECE_NAME_ZH: Record<PieceColor, Record<PieceType, string>> = {
  red: {
    king: '帥',
    advisor: '仕',
    elephant: '相',
    horse: '傌',
    rook: '俥',
    cannon: '炮',
    pawn: '兵',
  },
  black: {
    king: '將',
    advisor: '士',
    elephant: '象',
    horse: '馬',
    rook: '車',
    cannon: '砲',
    pawn: '卒',
  },
};

const CHINESE_NUMERALS = ['', '一', '二', '三', '四', '五', '六', '七', '八', '九'];

/**
 * Converts an engine move into traditional Xiangqi notation (the relative
 * "Cannon 8 traverses to 5" form players actually use), in English, Vietnamese,
 * or Chinese, plus the universal WXF code.
 *
 * File numbering: each side counts files 1..9 from its OWN right. In our
 * coordinates (file 0 = Red's far left), that means Red file = 9 - file, and
 * Black file = file + 1.
 */
@Injectable()
export class MoveNotationService {
  describe(input: DescribeMoveInput): MoveDescription {
    const moving = input.pieces.find(
      (p) => p.position.file === input.from.file && p.position.rank === input.from.rank,
    );

    // Defensive fallback: if we cannot identify the piece, emit a simple
    // coordinate move rather than throwing.
    if (!moving) {
      const cols = 'abcdefghi';
      const fallback = `${cols[input.from.file]}${input.from.rank + 1} → ${cols[input.to.file]}${input.to.rank + 1}`;
      return { human: fallback, wxf: fallback };
    }

    const { color, type } = moving;
    const fromFileNum = this.fileNumber(input.from.file, color);
    const toFileNum = this.fileNumber(input.to.file, color);

    const { direction, value, valueIsFile } = this.resolveMove(
      type,
      color,
      input.from,
      input.to,
      toFileNum,
    );
    const disambig = this.disambiguate(input.pieces, moving);

    return {
      human: this.format(
        input.language,
        color,
        type,
        fromFileNum,
        direction,
        value,
        valueIsFile,
        disambig,
      ),
      wxf: this.formatWxf(type, fromFileNum, direction, value, disambig),
    };
  }

  /** File index (0 = Red far-left) -> that side's 1..9 file number. */
  private fileNumber(file: number, color: PieceColor): number {
    return color === 'red' ? 9 - file : file + 1;
  }

  private resolveMove(
    type: PieceType,
    color: PieceColor,
    from: BoardPosition,
    to: BoardPosition,
    toFileNum: number,
  ): { direction: Direction; value: number; valueIsFile: boolean } {
    // "Advancing" means moving toward the enemy: Red up (rank increases),
    // Black down (rank decreases).
    const advancing = color === 'red' ? to.rank > from.rank : to.rank < from.rank;

    if (DIAGONAL_TYPES.has(type)) {
      return { direction: advancing ? 'advance' : 'retreat', value: toFileNum, valueIsFile: true };
    }
    if (from.rank === to.rank) {
      return { direction: 'traverse', value: toFileNum, valueIsFile: true };
    }
    return {
      direction: advancing ? 'advance' : 'retreat',
      value: Math.abs(to.rank - from.rank),
      valueIsFile: false,
    };
  }

  /**
   * When two pieces of the same colour+type share the moving piece's file, the
   * file number is ambiguous, so notation uses front/rear instead. (3+ on a
   * file — only possible with pawns — falls back to the file number.)
   */
  private disambiguate(pieces: NormalizedPiece[], moving: NormalizedPiece): Disambiguation {
    const sameFile = pieces.filter(
      (p) =>
        p.color === moving.color &&
        p.type === moving.type &&
        p.position.file === moving.position.file,
    );
    if (sameFile.length !== 2) return null;

    const front = sameFile.reduce((a, b) => (this.isFronter(moving.color, a, b) ? a : b));
    return front.position.rank === moving.position.rank ? 'front' : 'rear';
  }

  /** True if a is closer to the enemy than b. */
  private isFronter(color: PieceColor, a: NormalizedPiece, b: NormalizedPiece): boolean {
    return color === 'red' ? a.position.rank > b.position.rank : a.position.rank < b.position.rank;
  }

  private formatWxf(
    type: PieceType,
    fromFileNum: number,
    direction: Direction,
    value: number,
    disambig: Disambiguation,
  ): string {
    const letter = WXF_LETTER[type];
    const dirSym = direction === 'advance' ? '+' : direction === 'retreat' ? '-' : '=';
    if (disambig) {
      return `${disambig === 'front' ? '+' : '-'}${letter}${dirSym}${value}`;
    }
    return `${letter}${fromFileNum}${dirSym}${value}`;
  }

  private format(
    language: NotationLanguage,
    color: PieceColor,
    type: PieceType,
    fromFileNum: number,
    direction: Direction,
    value: number,
    valueIsFile: boolean,
    disambig: Disambiguation,
  ): string {
    switch (language) {
      case 'vi':
        return this.formatVi(type, fromFileNum, direction, value, disambig);
      case 'zh':
        return this.formatZh(color, type, fromFileNum, direction, value, disambig);
      default:
        return this.formatEn(type, fromFileNum, direction, value, valueIsFile, disambig);
    }
  }

  private formatEn(
    type: PieceType,
    fromFileNum: number,
    direction: Direction,
    value: number,
    valueIsFile: boolean,
    disambig: Disambiguation,
  ): string {
    const piece = PIECE_NAME_EN[type];
    const verb =
      direction === 'advance' ? 'advances' : direction === 'retreat' ? 'retreats' : 'traverses';
    const valuePart = valueIsFile ? `to ${value}` : `${value}`;
    if (disambig) {
      const where = disambig === 'front' ? 'Front' : 'Rear';
      return `${where} ${piece.toLowerCase()} ${verb} ${valuePart}`;
    }
    return `${piece} ${fromFileNum} ${verb} ${valuePart}`;
  }

  private formatVi(
    type: PieceType,
    fromFileNum: number,
    direction: Direction,
    value: number,
    disambig: Disambiguation,
  ): string {
    const piece = PIECE_NAME_VI[type];
    const dir = direction === 'advance' ? 'tiến' : direction === 'retreat' ? 'thoái' : 'bình';
    const origin = disambig ? (disambig === 'front' ? 'trước' : 'sau') : `${fromFileNum}`;
    return `${piece} ${origin} ${dir} ${value}`;
  }

  private formatZh(
    color: PieceColor,
    type: PieceType,
    fromFileNum: number,
    direction: Direction,
    value: number,
    disambig: Disambiguation,
  ): string {
    const piece = PIECE_NAME_ZH[color][type];
    const dir = direction === 'advance' ? '進' : direction === 'retreat' ? '退' : '平';
    // Red uses Chinese numerals; Black uses Arabic — the classic convention.
    const num = (n: number): string => (color === 'red' ? CHINESE_NUMERALS[n] : `${n}`);
    if (disambig) {
      return `${disambig === 'front' ? '前' : '後'}${piece}${dir}${num(value)}`;
    }
    return `${piece}${num(fromFileNum)}${dir}${num(value)}`;
  }
}
