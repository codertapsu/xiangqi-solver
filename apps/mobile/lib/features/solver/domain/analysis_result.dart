import 'dart:convert';

import 'package:equatable/equatable.dart';

import 'best_move.dart';
import 'board_state.dart';

/// Status of one of the two pipeline providers (vision or engine).
class ProviderStatus extends Equatable {
  const ProviderStatus({required this.provider, required this.ok});

  final String provider;
  final bool ok;

  factory ProviderStatus.fromJson(Map<String, dynamic> json) {
    return ProviderStatus(
      provider: json['provider'] as String? ?? 'unknown',
      ok: json['ok'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {'provider': provider, 'ok': ok};

  @override
  List<Object?> get props => [provider, ok];
}

/// The complete analysis returned by the backend.
///
/// Mirrors the shared `AnalysisResult` contract exactly. [bestMove] is nullable
/// because the engine may fail or the position may be terminal.
class AnalysisResult extends Equatable {
  const AnalysisResult({
    required this.analysisId,
    required this.board,
    required this.bestMove,
    required this.explanation,
    required this.warnings,
    required this.engine,
    required this.vision,
    this.candidates = const [],
  });

  final String analysisId;
  final BoardState board;
  final BestMove? bestMove;

  /// Ranked candidate moves when MultiPV > 1 (empty otherwise); index 0 = best.
  final List<BestMove> candidates;
  final String explanation;
  final List<String> warnings;
  final ProviderStatus engine;
  final ProviderStatus vision;

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    final rawBestMove = json['bestMove'];
    return AnalysisResult(
      analysisId: json['analysisId'] as String? ?? '',
      board: BoardState.fromJson(
        (json['board'] as Map).cast<String, dynamic>(),
      ),
      bestMove: rawBestMove is Map
          ? BestMove.fromJson(rawBestMove.cast<String, dynamic>())
          : null,
      candidates: (json['candidates'] as List<dynamic>? ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => BestMove.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
      explanation: json['explanation'] as String? ?? '',
      warnings: (json['warnings'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      engine: ProviderStatus.fromJson(
        (json['engine'] as Map? ?? const {}).cast<String, dynamic>(),
      ),
      vision: ProviderStatus.fromJson(
        (json['vision'] as Map? ?? const {}).cast<String, dynamic>(),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'analysisId': analysisId,
    'board': board.toJson(),
    'bestMove': bestMove?.toJson(),
    'candidates': candidates.map((c) => c.toJson()).toList(growable: false),
    'explanation': explanation,
    'warnings': warnings,
    'engine': engine.toJson(),
    'vision': vision.toJson(),
  };

  /// Pretty-printed JSON of the extracted board, for the Result screen.
  String prettyBoardJson() {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(board.toJson());
  }

  @override
  List<Object?> get props => [
    analysisId,
    board,
    bestMove,
    candidates,
    explanation,
    warnings,
    engine,
    vision,
  ];
}
