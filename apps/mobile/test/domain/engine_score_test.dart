import 'package:flutter_test/flutter_test.dart';
import 'package:xiangqi_solver/features/solver/domain/engine_score.dart';

void main() {
  group('EngineScore.tryParse', () {
    test('reads pawns and mates', () {
      expect(EngineScore.tryParse('+0.27')!.pawns, 0.27);
      expect(EngineScore.tryParse('-1.40')!.pawns, -1.40);
      expect(EngineScore.tryParse('mate 3')!.mateIn, 3);
      expect(EngineScore.tryParse('Mate -2')!.mateIn, -2);
    });

    test('rejects empty or unknown text', () {
      expect(EngineScore.tryParse(''), isNull);
      expect(EngineScore.tryParse('  '), isNull);
      expect(EngineScore.tryParse('n/a'), isNull);
      expect(EngineScore.tryParse('mate'), isNull);
    });
  });

  test('verdict thresholds', () {
    EvalVerdict v(String s) => EngineScore.tryParse(s)!.verdict;
    expect(v('+0.10'), EvalVerdict.even);
    expect(v('-0.34'), EvalVerdict.even);
    expect(v('+0.50'), EvalVerdict.slightEdge);
    expect(v('+1.50'), EvalVerdict.advantage);
    expect(v('+3.00'), EvalVerdict.winning);
    expect(v('-0.50'), EvalVerdict.slightlyWorse);
    expect(v('-1.50'), EvalVerdict.worse);
    expect(v('-3.00'), EvalVerdict.losing);
    expect(v('mate 2'), EvalVerdict.mate);
    expect(v('mate -2'), EvalVerdict.mated);
  });

  test('share is 0.5 when even, monotonic, and clamped', () {
    double share(String s) => EngineScore.tryParse(s)!.share;
    expect(share('0'), closeTo(0.5, 1e-9));
    expect(share('+1.00'), greaterThan(share('+0.50')));
    expect(share('-1.00'), lessThan(0.5));
    expect(share('+50'), 0.97);
    expect(share('-50'), 0.03);
    expect(share('mate 1'), 0.97);
    expect(share('mate -1'), 0.03);
  });

  test('signedPawns formats with a sign and two decimals', () {
    expect(EngineScore.tryParse('0.2')!.signedPawns, '+0.20');
    expect(EngineScore.tryParse('-1.4')!.signedPawns, '−1.40');
    expect(EngineScore.tryParse('mate 3')!.signedPawns, '');
  });
}
