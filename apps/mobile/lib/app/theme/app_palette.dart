import 'package:flutter/material.dart';

/// Brand and board colours that Material's [ColorScheme] has no slot for.
///
/// Read it with `AppPalette.of(context)`. Both instances follow the "Sơn Mài"
/// concept in docs/DESIGN.md: rice paper + cinnabar ink (light) and black
/// lacquer + gold leaf (dark).
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.gold,
    required this.goldText,
    required this.cinnabar,
    required this.ink,
    required this.jade,
    required this.heroGradient,
    required this.onHero,
    required this.onHeroMuted,
    required this.heroSurface,
    required this.boardFaceTop,
    required this.boardFaceBottom,
    required this.boardFrame,
    required this.boardLine,
    required this.boardRiverText,
    required this.pieceFace,
    required this.pieceFaceEdge,
    required this.pieceRed,
    required this.pieceBlack,
    required this.arrow,
    required this.arrowKeyline,
    required this.candidateArrow,
  });

  /// Decorative gold (coins, rings, accents). Not for body text on paper.
  final Color gold;

  /// Gold that is readable as text/icons on the page surface.
  final Color goldText;

  /// Brand red — the red side, the analyze button, the hero.
  final Color cinnabar;

  /// The black side's ink.
  final Color ink;

  /// Positive / favourable states (evaluation in your favour, "ready").
  final Color jade;

  /// The Home hero card background.
  final Gradient heroGradient;

  /// Text and icons on [heroGradient].
  final Color onHero;
  final Color onHeroMuted;

  /// Translucent fills placed on top of [heroGradient] (pills, the side picker).
  final Color heroSurface;

  // ---- Board ----
  final Color boardFaceTop;
  final Color boardFaceBottom;
  final Color boardFrame;
  final Color boardLine;
  final Color boardRiverText;
  final Color pieceFace;
  final Color pieceFaceEdge;
  final Color pieceRed;
  final Color pieceBlack;

  /// The best-move arrow and its contrast keyline.
  final Color arrow;
  final Color arrowKeyline;

  /// Arrows for other candidate moves.
  final Color candidateArrow;

  static const AppPalette light = AppPalette(
    gold: Color(0xFFD9A441),
    goldText: Color(0xFF7C5A0E),
    cinnabar: Color(0xFFB3261E),
    ink: Color(0xFF231C18),
    jade: Color(0xFF2F6B53),
    heroGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      // The app icon's field: deep cinnabar into warm orange.
      colors: [Color(0xFF9E1515), Color(0xFFC62A1C), Color(0xFFE0611F)],
      stops: [0, 0.55, 1],
    ),
    onHero: Color(0xFFFFF8EE),
    onHeroMuted: Color(0xFFFFE0C4),
    heroSurface: Color(0x26FFF1DD),
    boardFaceTop: Color(0xFFF3DCA8),
    boardFaceBottom: Color(0xFFE7C488),
    boardFrame: Color(0xFF8A5A2B),
    boardLine: Color(0xFF5E3B1C),
    boardRiverText: Color(0xFF7A5230),
    pieceFace: Color(0xFFFFF6E3),
    pieceFaceEdge: Color(0xFFE8D2A6),
    pieceRed: Color(0xFFB3261E),
    pieceBlack: Color(0xFF231C18),
    arrow: Color(0xFFD99A1E),
    arrowKeyline: Color(0xCC3A2205),
    candidateArrow: Color(0x992F6B53),
  );

  static const AppPalette dark = AppPalette(
    gold: Color(0xFFE9BE62),
    goldText: Color(0xFFE9BE62),
    cinnabar: Color(0xFFE0533F),
    ink: Color(0xFF231C18),
    jade: Color(0xFF96D4B6),
    heroGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      // Black lacquer warming into a cinnabar glow.
      colors: [Color(0xFF241A16), Color(0xFF3A1A14), Color(0xFF6E1F16)],
      stops: [0, 0.6, 1],
    ),
    onHero: Color(0xFFFBEFE3),
    onHeroMuted: Color(0xFFE8CDB3),
    heroSurface: Color(0x1FE9BE62),
    boardFaceTop: Color(0xFFCBA66C),
    boardFaceBottom: Color(0xFFB88F55),
    boardFrame: Color(0xFF5B3A1B),
    boardLine: Color(0xFF3E2610),
    boardRiverText: Color(0xFF4C2F15),
    pieceFace: Color(0xFFF6EBD3),
    pieceFaceEdge: Color(0xFFD9C29A),
    pieceRed: Color(0xFFB3261E),
    pieceBlack: Color(0xFF231C18),
    arrow: Color(0xFFF2C14E),
    arrowKeyline: Color(0xCC2A1A06),
    candidateArrow: Color(0xB396D4B6),
  );

  /// The palette for [context]'s theme (falls back to [light]).
  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? light;

  @override
  AppPalette copyWith({
    Color? gold,
    Color? goldText,
    Color? cinnabar,
    Color? ink,
    Color? jade,
    Gradient? heroGradient,
    Color? onHero,
    Color? onHeroMuted,
    Color? heroSurface,
    Color? boardFaceTop,
    Color? boardFaceBottom,
    Color? boardFrame,
    Color? boardLine,
    Color? boardRiverText,
    Color? pieceFace,
    Color? pieceFaceEdge,
    Color? pieceRed,
    Color? pieceBlack,
    Color? arrow,
    Color? arrowKeyline,
    Color? candidateArrow,
  }) {
    return AppPalette(
      gold: gold ?? this.gold,
      goldText: goldText ?? this.goldText,
      cinnabar: cinnabar ?? this.cinnabar,
      ink: ink ?? this.ink,
      jade: jade ?? this.jade,
      heroGradient: heroGradient ?? this.heroGradient,
      onHero: onHero ?? this.onHero,
      onHeroMuted: onHeroMuted ?? this.onHeroMuted,
      heroSurface: heroSurface ?? this.heroSurface,
      boardFaceTop: boardFaceTop ?? this.boardFaceTop,
      boardFaceBottom: boardFaceBottom ?? this.boardFaceBottom,
      boardFrame: boardFrame ?? this.boardFrame,
      boardLine: boardLine ?? this.boardLine,
      boardRiverText: boardRiverText ?? this.boardRiverText,
      pieceFace: pieceFace ?? this.pieceFace,
      pieceFaceEdge: pieceFaceEdge ?? this.pieceFaceEdge,
      pieceRed: pieceRed ?? this.pieceRed,
      pieceBlack: pieceBlack ?? this.pieceBlack,
      arrow: arrow ?? this.arrow,
      arrowKeyline: arrowKeyline ?? this.arrowKeyline,
      candidateArrow: candidateArrow ?? this.candidateArrow,
    );
  }

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      gold: c(gold, other.gold),
      goldText: c(goldText, other.goldText),
      cinnabar: c(cinnabar, other.cinnabar),
      ink: c(ink, other.ink),
      jade: c(jade, other.jade),
      heroGradient: Gradient.lerp(heroGradient, other.heroGradient, t)!,
      onHero: c(onHero, other.onHero),
      onHeroMuted: c(onHeroMuted, other.onHeroMuted),
      heroSurface: c(heroSurface, other.heroSurface),
      boardFaceTop: c(boardFaceTop, other.boardFaceTop),
      boardFaceBottom: c(boardFaceBottom, other.boardFaceBottom),
      boardFrame: c(boardFrame, other.boardFrame),
      boardLine: c(boardLine, other.boardLine),
      boardRiverText: c(boardRiverText, other.boardRiverText),
      pieceFace: c(pieceFace, other.pieceFace),
      pieceFaceEdge: c(pieceFaceEdge, other.pieceFaceEdge),
      pieceRed: c(pieceRed, other.pieceRed),
      pieceBlack: c(pieceBlack, other.pieceBlack),
      arrow: c(arrow, other.arrow),
      arrowKeyline: c(arrowKeyline, other.arrowKeyline),
      candidateArrow: c(candidateArrow, other.candidateArrow),
    );
  }
}
