import '../../../domain/board_piece.dart';
import '../../../domain/solver_enums.dart';
import 'local_uci.dart';

/// Localized traditional Xiangqi move notation. Faithful port of the backend
/// `move-notation.service.ts` — see docs/ENGINE.md.
///
/// Returns the localized [human] form ("Cannon 8 traverses to 5") and the
/// universal WXF [wxf] code ("C8=5"). [language] is `en` | `vi` | `zh`.
({String human, String wxf}) describeMove({
  required BoardPosition from,
  required BoardPosition to,
  required List<BoardPiece> pieces,
  required String language,
}) {
  final match = pieces
      .where((p) => p.position.file == from.file && p.position.rank == from.rank)
      .toList();
  if (match.isEmpty) {
    final fallback =
        '${fileToColumn(from.file)}${from.rank + 1} → ${fileToColumn(to.file)}${to.rank + 1}';
    return (human: fallback, wxf: fallback);
  }
  final piece = match.first;

  final color = piece.color;
  final type = piece.type;
  final fromFileNum = _fileNumber(from.file, color);
  final toFileNum = _fileNumber(to.file, color);

  final diagonal =
      type == PieceType.horse || type == PieceType.elephant || type == PieceType.advisor;
  final advancing = color == PieceColor.red ? to.rank > from.rank : to.rank < from.rank;

  final _Direction direction;
  final int value;
  final bool valueIsFile;
  if (diagonal) {
    direction = advancing ? _Direction.advance : _Direction.retreat;
    value = toFileNum;
    valueIsFile = true;
  } else if (from.rank == to.rank) {
    direction = _Direction.traverse;
    value = toFileNum;
    valueIsFile = true;
  } else {
    direction = advancing ? _Direction.advance : _Direction.retreat;
    value = (to.rank - from.rank).abs();
    valueIsFile = false;
  }

  final disambig = _disambiguate(pieces, piece);

  return (
    human: _format(language, color, type, fromFileNum, direction, value, valueIsFile, disambig),
    wxf: _formatWxf(type, fromFileNum, direction, value, disambig),
  );
}

enum _Direction { advance, retreat, traverse }

enum _Disambig { front, rear }

/// File index (0 = Red far-left) → that side's 1..9 file number.
int _fileNumber(int file, PieceColor color) => color == PieceColor.red ? 9 - file : file + 1;

_Disambig? _disambiguate(List<BoardPiece> pieces, BoardPiece moving) {
  final sameFile = pieces
      .where((p) =>
          p.color == moving.color &&
          p.type == moving.type &&
          p.position.file == moving.position.file)
      .toList();
  if (sameFile.length != 2) return null;
  final front = sameFile.reduce((a, b) => _isFronter(moving.color, a, b) ? a : b);
  return front.position.rank == moving.position.rank ? _Disambig.front : _Disambig.rear;
}

bool _isFronter(PieceColor color, BoardPiece a, BoardPiece b) => color == PieceColor.red
    ? a.position.rank > b.position.rank
    : a.position.rank < b.position.rank;

const Map<PieceType, String> _wxfLetter = {
  PieceType.king: 'K',
  PieceType.advisor: 'A',
  PieceType.elephant: 'E',
  PieceType.horse: 'H',
  PieceType.rook: 'R',
  PieceType.cannon: 'C',
  PieceType.pawn: 'P',
};

String _formatWxf(
  PieceType type,
  int fromFileNum,
  _Direction direction,
  int value,
  _Disambig? disambig,
) {
  final letter = _wxfLetter[type]!;
  final dirSym = switch (direction) {
    _Direction.advance => '+',
    _Direction.retreat => '-',
    _Direction.traverse => '=',
  };
  if (disambig != null) {
    return '${disambig == _Disambig.front ? '+' : '-'}$letter$dirSym$value';
  }
  return '$letter$fromFileNum$dirSym$value';
}

String _format(
  String language,
  PieceColor color,
  PieceType type,
  int fromFileNum,
  _Direction direction,
  int value,
  bool valueIsFile,
  _Disambig? disambig,
) {
  switch (language) {
    case 'vi':
      return _formatVi(type, fromFileNum, direction, value, disambig);
    case 'zh':
      return _formatZh(color, type, fromFileNum, direction, value, disambig);
    default:
      return _formatEn(type, fromFileNum, direction, value, valueIsFile, disambig);
  }
}

const Map<PieceType, String> _nameEn = {
  PieceType.king: 'King',
  PieceType.advisor: 'Advisor',
  PieceType.elephant: 'Elephant',
  PieceType.horse: 'Horse',
  PieceType.rook: 'Rook',
  PieceType.cannon: 'Cannon',
  PieceType.pawn: 'Pawn',
};

String _formatEn(
  PieceType type,
  int fromFileNum,
  _Direction direction,
  int value,
  bool valueIsFile,
  _Disambig? disambig,
) {
  final piece = _nameEn[type]!;
  final verb = switch (direction) {
    _Direction.advance => 'advances',
    _Direction.retreat => 'retreats',
    _Direction.traverse => 'traverses',
  };
  final valuePart = valueIsFile ? 'to $value' : '$value';
  if (disambig != null) {
    final where = disambig == _Disambig.front ? 'Front' : 'Rear';
    return '$where ${piece.toLowerCase()} $verb $valuePart';
  }
  return '$piece $fromFileNum $verb $valuePart';
}

const Map<PieceType, String> _nameVi = {
  PieceType.king: 'Tướng',
  PieceType.advisor: 'Sĩ',
  PieceType.elephant: 'Tượng',
  PieceType.horse: 'Mã',
  PieceType.rook: 'Xe',
  PieceType.cannon: 'Pháo',
  PieceType.pawn: 'Tốt',
};

String _formatVi(
  PieceType type,
  int fromFileNum,
  _Direction direction,
  int value,
  _Disambig? disambig,
) {
  final piece = _nameVi[type]!;
  final dir = switch (direction) {
    _Direction.advance => 'tiến',
    _Direction.retreat => 'thoái',
    _Direction.traverse => 'bình',
  };
  final origin = disambig != null ? (disambig == _Disambig.front ? 'trước' : 'sau') : '$fromFileNum';
  return '$piece $origin $dir $value';
}

const Map<PieceColor, Map<PieceType, String>> _nameZh = {
  PieceColor.red: {
    PieceType.king: '帥',
    PieceType.advisor: '仕',
    PieceType.elephant: '相',
    PieceType.horse: '傌',
    PieceType.rook: '俥',
    PieceType.cannon: '炮',
    PieceType.pawn: '兵',
  },
  PieceColor.black: {
    PieceType.king: '將',
    PieceType.advisor: '士',
    PieceType.elephant: '象',
    PieceType.horse: '馬',
    PieceType.rook: '車',
    PieceType.cannon: '砲',
    PieceType.pawn: '卒',
  },
};

const List<String> _chineseNumerals = ['', '一', '二', '三', '四', '五', '六', '七', '八', '九'];

String _formatZh(
  PieceColor color,
  PieceType type,
  int fromFileNum,
  _Direction direction,
  int value,
  _Disambig? disambig,
) {
  final piece = _nameZh[color]![type]!;
  final dir = switch (direction) {
    _Direction.advance => '進',
    _Direction.retreat => '退',
    _Direction.traverse => '平',
  };
  String num(int n) => color == PieceColor.red ? _chineseNumerals[n] : '$n';
  if (disambig != null) {
    return '${disambig == _Disambig.front ? '前' : '後'}$piece$dir${num(value)}';
  }
  return '$piece${num(fromFileNum)}$dir${num(value)}';
}
