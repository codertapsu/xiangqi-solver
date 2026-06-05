import 'package:equatable/equatable.dart';

import '../../solver/domain/analysis_result.dart';

/// A compact, persistable record of a past analysis.
///
/// Stores METADATA ONLY (no image bytes) so the history list is cheap and
/// privacy-preserving. The optional [screenshotPath] is retained only when the
/// user has opted into local screenshot storage.
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
    );
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
  ];
}
