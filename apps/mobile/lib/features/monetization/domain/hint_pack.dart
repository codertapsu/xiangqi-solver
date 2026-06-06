/// A purchasable hint pack. `productId` MUST match the Google Play product id
/// and the backend's `HINT_PACKS` map (the server decides the hint count).
class HintPack {
  const HintPack({
    required this.productId,
    required this.hints,
    required this.priceVnd,
  });

  final String productId;
  final int hints;

  /// Documentation / mock-mode fallback price. The REAL price shown at runtime
  /// comes from Google Play (ProductDetails.price), set per-country in Console.
  final int priceVnd;

  /// e.g. "49,000₫" — used only in mock mode or before Play products load.
  String get priceVndLabel {
    final s = priceVnd.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '$buf₫';
  }
}

/// The packs offered in the app. Prices come from Play Console at runtime;
/// the hint counts are authoritative server-side.
const List<HintPack> kHintPacks = [
  HintPack(productId: 'hints_20', hints: 20, priceVnd: 19000),
  HintPack(productId: 'hints_60', hints: 60, priceVnd: 49000),
  HintPack(productId: 'hints_150', hints: 150, priceVnd: 99000),
];

int? hintsForProduct(String productId) {
  for (final p in kHintPacks) {
    if (p.productId == productId) return p.hints;
  }
  return null;
}
