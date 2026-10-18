import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_theme.dart';
import '../../domain/board_piece.dart';
import '../../domain/solver_enums.dart';

/// A from → to pair to draw as an arrow on [XiangqiBoard].
class BoardArrow {
  const BoardArrow({required this.from, required this.to});

  final BoardPosition from;
  final BoardPosition to;

  @override
  bool operator ==(Object other) =>
      other is BoardArrow && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// The traditional glyph for a piece: 帥仕相傌俥炮兵 for Red, 將士象馬車砲卒 for Black.
String pieceGlyph(PieceColor color, PieceType type) => switch ((color, type)) {
  (PieceColor.red, PieceType.king) => '帥',
  (PieceColor.red, PieceType.advisor) => '仕',
  (PieceColor.red, PieceType.elephant) => '相',
  (PieceColor.red, PieceType.horse) => '傌',
  (PieceColor.red, PieceType.rook) => '俥',
  (PieceColor.red, PieceType.cannon) => '炮',
  (PieceColor.red, PieceType.pawn) => '兵',
  (PieceColor.black, PieceType.king) => '將',
  (PieceColor.black, PieceType.advisor) => '士',
  (PieceColor.black, PieceType.elephant) => '象',
  (PieceColor.black, PieceType.horse) => '馬',
  (PieceColor.black, PieceType.rook) => '車',
  (PieceColor.black, PieceType.cannon) => '砲',
  (PieceColor.black, PieceType.pawn) => '卒',
};

/// A Xiangqi board with pieces and an optional best-move arrow.
///
/// Uses the engine's canonical coordinates (file 0..8, rank 0..9, rank 0 = Red's
/// home row). [flipped] puts Black at the bottom, so the board matches the
/// screenshot of a player who plays Black. The arrow draws itself in when
/// [move] changes; [candidates] are drawn faintly underneath it.
class XiangqiBoard extends StatefulWidget {
  const XiangqiBoard({
    super.key,
    required this.pieces,
    this.move,
    this.candidates = const [],
    this.flipped = false,
    this.showCoordinates = true,
    this.animateMove = true,
    this.semanticsLabel,
  });

  final List<BoardPiece> pieces;
  final BoardArrow? move;
  final List<BoardArrow> candidates;
  final bool flipped;
  final bool showCoordinates;
  final bool animateMove;

  /// What a screen reader announces for the whole board.
  final String? semanticsLabel;

  /// Width / height of the board including its margin.
  static double aspectRatio({bool showCoordinates = true}) {
    final m = _margin(showCoordinates);
    return (8 + 2 * m) / (9 + 2 * m);
  }

  static double _margin(bool showCoordinates) => showCoordinates ? 0.95 : 0.6;

  @override
  State<XiangqiBoard> createState() => _XiangqiBoardState();
}

class _XiangqiBoardState extends State<XiangqiBoard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _arrow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: widget.animateMove ? 0 : 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animateMove && widget.move != null) _arrow.forward();
  }

  @override
  void didUpdateWidget(covariant XiangqiBoard old) {
    super.didUpdateWidget(old);
    if (widget.move != old.move) {
      if (widget.animateMove) {
        _arrow.forward(from: 0);
      } else {
        _arrow.value = 1;
      }
    }
  }

  @override
  void dispose() {
    _arrow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final margin = XiangqiBoard._margin(widget.showCoordinates);
    final geometry = _BoardGeometry(margin: margin, flipped: widget.flipped);
    final board = AspectRatio(
      aspectRatio: XiangqiBoard.aspectRatio(showCoordinates: widget.showCoordinates),
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _BoardPainter(
            palette: palette,
            geometry: geometry,
            pieces: widget.pieces,
            move: widget.move,
            showCoordinates: widget.showCoordinates,
          ),
          foregroundPainter: _ArrowPainter(
            palette: palette,
            geometry: geometry,
            move: widget.move,
            candidates: widget.candidates,
            progress: _arrow,
          ),
        ),
      ),
    );
    return Semantics(
      label: widget.semanticsLabel,
      image: true,
      excludeSemantics: true,
      child: board,
    );
  }
}

/// Maps board points to canvas pixels for a given size.
class _BoardGeometry {
  const _BoardGeometry({required this.margin, required this.flipped});

  final double margin;
  final bool flipped;

  double cell(Size size) => size.width / (8 + 2 * margin);

  Offset point(Size size, int file, int rank) {
    final c = cell(size);
    final x = flipped ? 8 - file : file;
    final y = flipped ? rank : 9 - rank;
    return Offset((margin + x) * c, (margin + y) * c);
  }

  Offset at(Size size, BoardPosition p) => point(size, p.file, p.rank);
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.palette,
    required this.geometry,
    required this.pieces,
    required this.move,
    required this.showCoordinates,
  });

  final AppPalette palette;
  final _BoardGeometry geometry;
  final List<BoardPiece> pieces;
  final BoardArrow? move;
  final bool showCoordinates;

  @override
  void paint(Canvas canvas, Size size) {
    final c = geometry.cell(size);
    _paintFace(canvas, size, c);
    _paintGrid(canvas, size, c);
    if (showCoordinates) _paintFileNumbers(canvas, size, c);
    _paintHighlights(canvas, size, c);
    for (final piece in pieces) {
      if (piece.file < 0 || piece.file > 8 || piece.rank < 0 || piece.rank > 9) continue;
      final isMoving = move != null && piece.position == move!.from;
      paintPieceDisc(
        canvas,
        geometry.at(size, piece.position),
        c * 0.45,
        palette: palette,
        color: piece.color,
        glyph: pieceGlyph(piece.color, piece.type),
        glow: isMoving,
      );
    }
  }

  void _paintFace(Canvas canvas, Size size, double c) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(c * 0.35));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.boardFaceTop, palette.boardFaceBottom],
        ).createShader(rect),
    );
    // A faint inner keyline gives the face a carved edge.
    canvas.drawRRect(
      rrect.deflate(c * 0.08),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, c * 0.025)
        ..color = palette.boardFrame.withValues(alpha: 0.25),
    );
  }

  void _paintGrid(Canvas canvas, Size size, double c) {
    final line = Paint()
      ..color = palette.boardLine
      ..strokeWidth = math.max(1, c * 0.035)
      ..strokeCap = StrokeCap.square;
    Offset p(int f, int r) => geometry.point(size, f, r);

    // Outer frame, a little outside the playing grid.
    final topLeft = p(geometry.flipped ? 8 : 0, geometry.flipped ? 0 : 9);
    final bottomRight = p(geometry.flipped ? 0 : 8, geometry.flipped ? 9 : 0);
    canvas.drawRect(
      Rect.fromPoints(topLeft, bottomRight).inflate(c * 0.14),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, c * 0.07)
        ..color = palette.boardLine,
    );

    for (var r = 0; r <= 9; r++) {
      canvas.drawLine(p(0, r), p(8, r), line);
    }
    for (var f = 0; f <= 8; f++) {
      if (f == 0 || f == 8) {
        canvas.drawLine(p(f, 0), p(f, 9), line);
      } else {
        // Inner files stop at the river.
        canvas.drawLine(p(f, 0), p(f, 4), line);
        canvas.drawLine(p(f, 5), p(f, 9), line);
      }
    }
    // Palaces.
    canvas
      ..drawLine(p(3, 0), p(5, 2), line)
      ..drawLine(p(5, 0), p(3, 2), line)
      ..drawLine(p(3, 7), p(5, 9), line)
      ..drawLine(p(5, 7), p(3, 9), line);

    // Start-point markers for cannons and pawns.
    const points = [
      (1, 2), (7, 2), (1, 7), (7, 7),
      (0, 3), (2, 3), (4, 3), (6, 3), (8, 3),
      (0, 6), (2, 6), (4, 6), (6, 6), (8, 6),
    ];
    final markPaint = Paint()
      ..color = palette.boardLine
      ..strokeWidth = math.max(1, c * 0.03)
      ..style = PaintingStyle.stroke;
    final gap = c * 0.09;
    final arm = c * 0.2;
    for (final (f, r) in points) {
      final o = p(f, r);
      for (final dx in const [-1, 1]) {
        // No marks outside the board edge.
        final screenFile = geometry.flipped ? 8 - f : f;
        if ((screenFile == 0 && dx < 0) || (screenFile == 8 && dx > 0)) continue;
        for (final dy in const [-1, 1]) {
          final corner = o + Offset(dx * gap, dy * gap);
          final path = Path()
            ..moveTo(corner.dx + dx * arm, corner.dy)
            ..lineTo(corner.dx, corner.dy)
            ..lineTo(corner.dx, corner.dy + dy * arm);
          canvas.drawPath(path, markPaint);
        }
      }
    }

    // River text, upright for the viewer: 楚河 on the left, 漢界 on the right.
    final riverTop = math.min(p(0, 4).dy, p(0, 5).dy);
    final riverMid = riverTop + c / 2;
    final left = p(geometry.flipped ? 8 : 0, 4).dx;
    final width = 8 * c;
    _paintRiverPair(canvas, '楚', '河', Offset(left + width * 0.25, riverMid), c);
    _paintRiverPair(canvas, '漢', '界', Offset(left + width * 0.75, riverMid), c);
  }

  /// Two river characters spread around [center]. Painted one at a time: the
  /// bundled glyph font is a subset with no space character, so a spaced string
  /// would render tofu boxes.
  void _paintRiverPair(Canvas canvas, String a, String b, Offset center, double c) {
    _paintRiverChar(canvas, a, center - Offset(c * 0.62, 0), c);
    _paintRiverChar(canvas, b, center + Offset(c * 0.62, 0), c);
  }

  void _paintRiverChar(Canvas canvas, String char, Offset center, double c) {
    final tp = TextPainter(
      text: TextSpan(
        text: char,
        style: TextStyle(
          fontFamily: AppTheme.pieceFontFamily,
          fontWeight: FontWeight.w700,
          fontSize: c * 0.62,
          height: 1,
          color: palette.boardRiverText,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  /// File numbers in each side's own counting: the side at the bottom reads
  /// 9 … 1 left to right, the side at the top 1 … 9 (as in "Pháo 2 bình 5").
  void _paintFileNumbers(Canvas canvas, Size size, double c) {
    final bottomSide = geometry.flipped ? palette.pieceBlack : palette.pieceRed;
    final topSide = geometry.flipped ? palette.pieceRed : palette.pieceBlack;
    for (var col = 0; col < 9; col++) {
      final x = (geometry.margin + col) * c;
      _paintLabel(canvas, '${9 - col}', Offset(x, size.height - c * 0.36), c, bottomSide);
      _paintLabel(canvas, '${col + 1}', Offset(x, c * 0.36), c, topSide);
    }
  }

  void _paintLabel(Canvas canvas, String text, Offset center, double c, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: c * 0.32,
          color: color.withValues(alpha: 0.72),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _paintHighlights(Canvas canvas, Size size, double c) {
    final m = move;
    if (m == null) return;
    final from = geometry.at(size, m.from);
    final to = geometry.at(size, m.to);
    // Where the piece leaves: a soft gold disc under it.
    canvas.drawCircle(from, c * 0.5, Paint()..color = palette.arrow.withValues(alpha: 0.22));
    // Where it lands: a gold ring (around a captured piece, or on an empty point).
    canvas
      ..drawCircle(to, c * 0.5, Paint()..color = palette.arrow.withValues(alpha: 0.18))
      ..drawCircle(
        to,
        c * 0.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, c * 0.07)
          ..color = palette.arrow,
      );
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) =>
      old.palette != palette ||
      old.geometry.flipped != geometry.flipped ||
      old.geometry.margin != geometry.margin ||
      old.move != move ||
      old.showCoordinates != showCoordinates ||
      !_samePieces(old.pieces, pieces);

  static bool _samePieces(List<BoardPiece> a, List<BoardPiece> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Paints one piece: a cream disc with a coloured ring and its glyph.
///
/// Shared by the board and by [PieceToken], so pieces look the same everywhere.
void paintPieceDisc(
  Canvas canvas,
  Offset center,
  double radius, {
  required AppPalette palette,
  required PieceColor color,
  required String glyph,
  bool glow = false,
}) {
  final side = color == PieceColor.red ? palette.pieceRed : palette.pieceBlack;
  if (glow) {
    canvas.drawCircle(
      center,
      radius * 1.18,
      Paint()
        ..color = palette.arrow.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.25),
    );
  }
  // Drop shadow.
  canvas.drawCircle(
    center + Offset(0, radius * 0.08),
    radius,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.12),
  );
  // Face.
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.35),
        radius: 1.05,
        colors: [palette.pieceFace, palette.pieceFaceEdge],
      ).createShader(Rect.fromCircle(center: center, radius: radius)),
  );
  // Outer ring and the thin inner ring.
  canvas
    ..drawCircle(
      center,
      radius * 0.94,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.11
        ..color = side,
    )
    ..drawCircle(
      center,
      radius * 0.76,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, radius * 0.035)
        ..color = side.withValues(alpha: 0.7),
    );
  final tp = TextPainter(
    text: TextSpan(
      text: glyph,
      style: TextStyle(
        fontFamily: AppTheme.pieceFontFamily,
        fontWeight: FontWeight.w700,
        fontSize: radius * 1.08,
        height: 1,
        color: side,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter({
    required this.palette,
    required this.geometry,
    required this.move,
    required this.candidates,
    required this.progress,
  }) : super(repaint: progress);

  final AppPalette palette;
  final _BoardGeometry geometry;
  final BoardArrow? move;
  final List<BoardArrow> candidates;
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final c = geometry.cell(size);
    final t = Curves.easeOutCubic.transform(progress.value);
    for (final cand in candidates) {
      if (cand == move) continue;
      _arrow(canvas, size, c, cand, palette.candidateArrow, null, width: 0.11, t: t);
    }
    final m = move;
    if (m != null) {
      _arrow(canvas, size, c, m, palette.arrow, palette.arrowKeyline, width: 0.16, t: t);
    }
  }

  void _arrow(
    Canvas canvas,
    Size size,
    double c,
    BoardArrow a,
    Color color,
    Color? keyline, {
    required double width,
    required double t,
  }) {
    if (t <= 0) return;
    final from = geometry.at(size, a.from);
    final to = geometry.at(size, a.to);
    final delta = to - from;
    final length = delta.distance;
    if (length == 0) return;
    final dir = delta / length;
    final head = c * 0.42;
    // The line ends where the head begins; the tip sits on the target point.
    final tip = from + delta * t;
    final base = tip - dir * head;
    final start = from + dir * (c * 0.18);
    final w = c * width;

    final shaft = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(base.dx, base.dy);
    final normal = Offset(-dir.dy, dir.dx);
    final headPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(base.dx + normal.dx * head * 0.62, base.dy + normal.dy * head * 0.62)
      ..lineTo(base.dx - normal.dx * head * 0.62, base.dy - normal.dy * head * 0.62)
      ..close();

    if (keyline != null) {
      canvas
        ..drawPath(
          shaft,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w + c * 0.07
            ..strokeCap = StrokeCap.round
            ..color = keyline,
        )
        ..drawPath(
          headPath,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = c * 0.07
            ..strokeJoin = StrokeJoin.round
            ..color = keyline,
        );
    }
    canvas
      ..drawPath(
        shaft,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..color = color,
      )
      ..drawPath(headPath, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter old) =>
      old.palette != palette ||
      old.move != move ||
      old.geometry.flipped != geometry.flipped ||
      old.geometry.margin != geometry.margin ||
      !_sameArrows(old.candidates, candidates);

  static bool _sameArrows(List<BoardArrow> a, List<BoardArrow> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A single piece disc as a widget — used for the side picker and badges.
class PieceToken extends StatelessWidget {
  const PieceToken({
    super.key,
    required this.color,
    this.type = PieceType.king,
    this.size = 32,
  });

  final PieceColor color;
  final PieceType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _TokenPainter(
          palette: AppPalette.of(context),
          color: color,
          glyph: pieceGlyph(color, type),
        ),
      ),
    );
  }
}

class _TokenPainter extends CustomPainter {
  _TokenPainter({required this.palette, required this.color, required this.glyph});

  final AppPalette palette;
  final PieceColor color;
  final String glyph;

  @override
  void paint(Canvas canvas, Size size) {
    paintPieceDisc(
      canvas,
      size.center(Offset.zero),
      size.shortestSide / 2 * 0.92,
      palette: palette,
      color: color,
      glyph: glyph,
    );
  }

  @override
  bool shouldRepaint(covariant _TokenPainter old) =>
      old.palette != palette || old.color != color || old.glyph != glyph;
}
