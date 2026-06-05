import { BoardPosition } from '../board/xiangqi.types';

/**
 * UCI <-> {file,rank} conversion helpers for Xiangqi.
 *
 * file index -> column letter: 0->a, 1->b, ... 8->i.
 * A UCI move is fromCol+fromRank+toCol+toRank, e.g. {file:1,rank:2} ->
 * {file:1,rank:7} = "b2b7".
 *
 * Human text = UPPER(col)+(rank+1), e.g. "B3" to "B8".
 */

const A_CHAR_CODE = 'a'.charCodeAt(0);
const MAX_FILE = 8;
const MAX_RANK = 9;

/** file 0..8 -> 'a'..'i'. */
export function fileToColumn(file: number): string {
  if (!Number.isInteger(file) || file < 0 || file > MAX_FILE) {
    throw new Error(`Invalid file index ${file}; expected 0..${MAX_FILE}.`);
  }
  return String.fromCharCode(A_CHAR_CODE + file);
}

/** 'a'..'i' -> file 0..8. */
export function columnToFile(column: string): number {
  const file = column.charCodeAt(0) - A_CHAR_CODE;
  if (column.length !== 1 || file < 0 || file > MAX_FILE) {
    throw new Error(`Invalid column letter '${column}'; expected 'a'..'i'.`);
  }
  return file;
}

/** {file,rank} -> UCI square token, e.g. {file:1,rank:2} -> "b2". */
export function positionToSquare(pos: BoardPosition): string {
  if (!Number.isInteger(pos.rank) || pos.rank < 0 || pos.rank > MAX_RANK) {
    throw new Error(`Invalid rank ${pos.rank}; expected 0..${MAX_RANK}.`);
  }
  return `${fileToColumn(pos.file)}${pos.rank}`;
}

/** UCI square token -> {file,rank}, e.g. "b2" -> {file:1,rank:2}. */
export function squareToPosition(square: string): BoardPosition {
  if (square.length !== 2) {
    throw new Error(`Invalid UCI square '${square}'; expected 2 chars like 'b2'.`);
  }
  const file = columnToFile(square[0]);
  const rank = Number(square[1]);
  if (!Number.isInteger(rank) || rank < 0 || rank > MAX_RANK) {
    throw new Error(`Invalid UCI square '${square}'; rank must be 0..${MAX_RANK}.`);
  }
  return { file, rank };
}

/** {from,to} -> UCI move string, e.g. "b2b7". */
export function moveToUci(from: BoardPosition, to: BoardPosition): string {
  return `${positionToSquare(from)}${positionToSquare(to)}`;
}

/** UCI move string -> { from, to }, e.g. "b2b7" -> positions. */
export function uciToMove(uci: string): { from: BoardPosition; to: BoardPosition } {
  if (uci.length !== 4) {
    throw new Error(`Invalid UCI move '${uci}'; expected 4 chars like 'b2b7'.`);
  }
  return {
    from: squareToPosition(uci.slice(0, 2)),
    to: squareToPosition(uci.slice(2, 4)),
  };
}

/** Human label for a square: UPPER(col)+(rank+1), e.g. {file:1,rank:2} -> "B3". */
export function positionToHuman(pos: BoardPosition): string {
  return `${fileToColumn(pos.file).toUpperCase()}${pos.rank + 1}`;
}

/** Human move text, e.g. "B3 to B8". */
export function moveToHuman(from: BoardPosition, to: BoardPosition): string {
  return `${positionToHuman(from)} to ${positionToHuman(to)}`;
}
