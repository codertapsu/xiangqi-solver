import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import '../../../core/remote_config/remote_config_provider.dart';
import '../domain/hint_pack.dart';
import '../monetization_config.dart';
import 'wallet_providers.dart';

/// Opens the "get more hints" sheet (watch an ad, or buy a pack).
Future<void> showGetMoreHintsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const GetMoreHintsSheet(),
  );
}

/// Bottom sheet where the user tops up hints — by watching a rewarded ad or
/// buying a pack.
///
/// Layout notes (this widget has a history of layout crashes, so keep them):
///  - The content is a [SingleChildScrollView] so it adapts to short screens and
///    large accessibility font scales instead of overflowing.
///  - The [Column] uses [CrossAxisAlignment.stretch], so every child is laid out
///    with a TIGHT, bounded width. That is deliberate: the app theme makes
///    [FilledButton] full-width (`minimumSize: Size.fromHeight(48)` →
///    width = infinity), and a full-width button laid out with an UNBOUNDED width
///    (which is what a [Row] does to its non-flex children) throws "BoxConstraints
///    forces an infinite width". So every button is a direct, full-width child of
///    the stretch column — never a child of a [Row].
///  - Each pack is itself a full-width button whose label is a [Row]; that inner
///    Row inherits the button's bounded width, so its [Expanded] title is safe.
class GetMoreHintsSheet extends ConsumerStatefulWidget {
  const GetMoreHintsSheet({super.key});

  @override
  ConsumerState<GetMoreHintsSheet> createState() => _GetMoreHintsSheetState();
}

class _GetMoreHintsSheetState extends ConsumerState<GetMoreHintsSheet> {
  bool _watchingAd = false;

  /// Whether to offer rewarded ads — backend-controlled (a capped loss-leader,
  /// so off by default). Mock mode always offers them for dev.
  bool get _rewardedOn =>
      kUseMockMonetization || ref.read(remoteConfigProvider).rewardedAds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_rewardedOn && !kUseMockMonetization) {
        ref.read(rewardedAdServiceProvider).load();
      }
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Watch a rewarded ad; credit +1 hint LOCALLY when the reward is earned.
  Future<void> _watchAd() async {
    if (kUseMockMonetization) {
      ref.read(walletProvider.notifier).add(1);
      _snack('Mock: +1 hint (no real ad).');
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() => _watchingAd = true);
    final shown = await ref.read(rewardedAdServiceProvider).show(
      onEarned: () {
        ref.read(walletProvider.notifier).add(1);
        _snack(l10n.hintsAdReward);
      },
    );
    if (mounted) setState(() => _watchingAd = false);
    if (!shown) _snack(l10n.hintsNoAdReady);
  }

  /// Buy a consumable pack; hints are credited LOCALLY when Play confirms the
  /// purchase (via BillingService.onPurchased, wired in the wallet provider).
  Future<void> _buy(String productId) async {
    if (kUseMockMonetization) {
      ref.read(walletProvider.notifier).add(hintsForProduct(productId) ?? 0);
      _snack('Mock: purchased.');
      return;
    }
    await ref.read(billingServiceProvider).buy(productId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final balance = ref.watch(walletProvider);
    final billing = ref.read(billingServiceProvider);
    final theme = Theme.of(context);

    final available = {for (final p in billing.products) p.id: p};

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Header ----
            Text(
              l10n.hintsGetMore,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              l10n.hintsBalance(balance),
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // ---- Watch an ad (+1 hint, credited locally) — backend-gated ----
            if (_rewardedOn) ...[
              FilledButton.tonalIcon(
                // Full-width via the stretch column — NOT inside a Row.
                onPressed: _watchingAd ? null : _watchAd,
                icon: _watchingAd
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ondemand_video_outlined),
                label: Text(l10n.hintsWatchAd),
              ),
              const SizedBox(height: 20),
            ],

            // ---- Buy a pack ----
            Text(l10n.hintsBuyPack, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final pack in kHintPacks)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PackButton(
                  hints: pack.hints,
                  // Real Play price when available; else the documented VND
                  // (mock mode, or before the products are configured).
                  price: available[pack.productId]?.price ?? pack.priceVndLabel,
                  onBuy: (kUseMockMonetization || available.containsKey(pack.productId))
                      ? () => _buy(pack.productId)
                      : null,
                ),
              ),
            if (!kUseMockMonetization && available.isEmpty)
              Text(
                l10n.hintsPacksUnavailable,
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

/// One purchasable pack, rendered as a full-width button. Because its parent
/// column stretches, the button gets a bounded width, so the inner [Row]'s
/// [Expanded] title is safe (no unbounded-width measurement).
class _PackButton extends StatelessWidget {
  const _PackButton({required this.hints, required this.price, required this.onBuy});

  final int hints;
  final String? price;
  final VoidCallback? onBuy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: onBuy,
      style: OutlinedButton.styleFrom(
        // minWidth 0 (width comes from the stretch column), fixed comfortable
        // height; never request an infinite width here.
        minimumSize: const Size(0, 56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        alignment: Alignment.centerLeft,
      ),
      // Only fixed-width icons sit beside the flexible middle. The hint count and
      // price are stacked inside an Expanded, so they wrap (the button grows
      // taller and the sheet scrolls) and can NEVER overflow horizontally — at
      // any font scale or screen width.
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.hintsPackTitle(hints), style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  price ?? '—',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
