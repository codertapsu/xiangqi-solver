import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/utils/logger.dart';

/// Thin wrapper around `in_app_purchase` for consumable hint packs.
///
/// Local-only model (matches the reference apps): [init] queries the products
/// and subscribes to the purchase stream; [buy] starts a purchase; when Play
/// reports a product as `purchased`, [onPurchased] fires with the product id so
/// the caller can credit hints LOCALLY, and the purchase is completed. There is
/// no server-side receipt verification.
class BillingService {
  BillingService({InAppPurchase? iap}) : _iapOverride = iap;

  static const AppLogger _log = AppLogger('Billing');
  final InAppPurchase? _iapOverride;

  // Lazy: simply constructing the service must NOT touch InAppPurchase.instance,
  // which eagerly registers the platform and auto-connects to Play (and throws
  // off-device). Resolved on first real use (init/buy), or injected for tests.
  InAppPurchase get _iap => _iapOverride ?? InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _sub;
  final Map<String, ProductDetails> _products = {};

  /// Called (on the device) when a product is successfully purchased/restored.
  void Function(String productId)? onPurchased;
  void Function(String message)? onError;

  Future<bool> isAvailable() => _iap.isAvailable();

  List<ProductDetails> get products {
    final list = _products.values.toList();
    list.sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
    return list;
  }

  ProductDetails? product(String productId) => _products[productId];

  /// Idempotent setup. Returns false if IAP is unavailable on this device.
  Future<bool> init(Iterable<String> productIds) async {
    if (!await _iap.isAvailable()) return false;
    _sub ??= _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) => onError?.call('$e'),
    );
    final resp = await _iap.queryProductDetails(productIds.toSet());
    for (final p in resp.productDetails) {
      _products[p.id] = p;
    }
    if (resp.notFoundIDs.isNotEmpty) {
      _log.warn('Play products not found (create them in Play Console): ${resp.notFoundIDs}');
    }
    return true;
  }

  Future<void> buy(String productId) async {
    final details = _products[productId];
    if (details == null) {
      onError?.call('That pack isn\'t available right now.');
      return;
    }
    // Consumable so packs can be re-bought. autoConsume=true is the standard path.
    await _iap.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: details),
      autoConsume: true,
    );
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final purchase in list) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          onPurchased?.call(purchase.productID);
          if (purchase.pendingCompletePurchase) await _iap.completePurchase(purchase);
        case PurchaseStatus.error:
          onError?.call(purchase.error?.message ?? 'Purchase failed.');
          if (purchase.pendingCompletePurchase) await _iap.completePurchase(purchase);
        case PurchaseStatus.canceled:
          if (purchase.pendingCompletePurchase) await _iap.completePurchase(purchase);
        case PurchaseStatus.pending:
          break;
      }
    }
  }

  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
  }
}
