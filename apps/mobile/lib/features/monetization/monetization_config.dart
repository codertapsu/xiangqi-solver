// Hints are stored and managed entirely on the device (local wallet). Earned by
// watching a rewarded ad (+1) or bought as a consumable pack; spent one per
// cloud analysis. There is NO server-side wallet, account, AdMob SSV, or
// purchase verification — the device owns this data.
//
// The free-hints-on-install COUNT is backend-driven (`HINTS_FREE_ON_INSTALL`
// → remote config `freeHintsOnInstall`, default 10), so it is NOT a const here.

/// Dev-only "dummy data" mode: the "watch ad" and "buy pack" actions credit
/// hints instantly WITHOUT a real AdMob ad or Google Play purchase, so you can
/// exercise the wallet UI on an emulator with no Play account / ad fill.
///
/// Enable with: `flutter run --dart-define=MOCK_MONETIZATION=true`.
/// Default false. NEVER ship a release with this on.
const bool kUseMockMonetization = bool.fromEnvironment(
  'MOCK_MONETIZATION',
  defaultValue: false,
);
