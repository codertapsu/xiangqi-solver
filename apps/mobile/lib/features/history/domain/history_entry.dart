import 'package:equatable/equatable.dart';

import '../../solver/domain/analysis_result.dart';

/// A compact, persistable record of a past analysis.
///
/// Never stores image bytes. Since 1.1 it keeps the full [result] (board,
/// moves, warnings — a few KB) so History can redraw the board and reopen the
/// analysis; entries written by 1.0 have no [result] and list as text only. The
/// optional [screenshotPath] is retained only when the user has opted into local
/// screenshot storage.
class HistoryEntry extends Equatable {
  const HistoryEntry({
    required this.analysisId,
    required this.timestamp,
    required this.aiProvider,
    required this.engineProvider,
    required this.bestMoveUci,
    required this.bestMoveHuman,
    required this.confidence,
    required this.sideToMove,
    this.screenshotPath,
    this.result,
  });

  final String analysisId;
  final DateTime timestamp;
  final String aiProvider;
  final String engineProvider;
  final String? bestMoveUci;
  final String? bestMoveHuman;
  final double confidence;
  final String sideToMove;
  final String? screenshotPath;

  /// The complete analysis (null for entries saved before 1.1).
  final AnalysisResult? result;

  /// Builds an entry from a fresh [AnalysisResult].
  factory HistoryEntry.fromResult(
    AnalysisResult result, {
    DateTime? timestamp,
    String? screenshotPath,
  }) {
    return HistoryEntry(
      analysisId: result.analysisId,
      timestamp: timestamp ?? DateTime.now(),
      aiProvider: result.vision.provider,
      engineProvider: result.engine.provider,
      bestMoveUci: result.bestMove?.uci,
      bestMoveHuman: result.bestMove?.human,
      confidence: result.board.confidence,
      sideToMove: result.board.sideToMove.wireValue,
      screenshotPath: screenshotPath,
      result: result,
    );
  }

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      analysisId: json['analysisId'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      aiProvider: json['aiProvider'] as String? ?? 'unknown',
      engineProvider: json['engineProvider'] as String? ?? 'unknown',
      bestMoveUci: json['bestMoveUci'] as String?,
      bestMoveHuman: json['bestMoveHuman'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      sideToMove: json['sideToMove'] as String? ?? 'unknown',
      screenshotPath: json['screenshotPath'] as String?,
      result: _resultFrom(json['result']),
    );
  }

  /// A stored result, or null when absent or unreadable (one bad entry must not
  /// take the whole history list down).
  static AnalysisResult? _resultFrom(Object? raw) {
    if (raw is! Map) return null;
    try {
      return AnalysisResult.fromJson(raw.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
    'analysisId': analysisId,
    'timestamp': timestamp.toIso8601String(),
    'aiProvider': aiProvider,
    'engineProvider': engineProvider,
    'bestMoveUci': bestMoveUci,
    'bestMoveHuman': bestMoveHuman,
    'confidence': confidence,
    'sideToMove': sideToMove,
    'screenshotPath': screenshotPath,
    if (result != null) 'result': result!.toJson(),
  };

  @override
  List<Object?> get props => [
    analysisId,
    timestamp,
    aiProvider,
    engineProvider,
    bestMoveUci,
    bestMoveHuman,
    confidence,
    sideToMove,
    screenshotPath,
    result,
  ];
}
