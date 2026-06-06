# Monetization — hints, ads, IAP, and licensing

> **⚠️ Current architecture: hints are DEVICE-LOCAL.** As of the local-wallet
> refactor, hints live entirely on the user's device (`SharedPreferences`) — there
> is **no server-side wallet, account, AdMob SSV, or purchase verification**. A
> rewarded ad credits **+1 hint in the client `onUserEarnedReward` callback**; a
> Play purchase credits the pack's hints locally when the `purchaseStream` reports
> `PurchaseStatus.purchased`; the client spends one hint per cloud analysis. The
> backend no longer meters hints — it only protects the (paid) analysis endpoints
> with a **per-IP throttle + a per-device daily cap** (`x-device-id` header,
> `DeviceRateLimitGuard`). Any text below describing a *server wallet*, *SSV*, or
> *server-side IAP validation* is **historical** and no longer applies; the
> **economics and licensing still hold**.

A **hint** = one cloud board analysis (one OpenAI vision call billed to us).
New installs get **10 free hints** ([kFreeHintsOnInstall]); users earn more by
watching rewarded ads or buying hint packs. This doc captures the economics, the
licensing decision, and the (current, local) architecture.

> Not legal/financial advice. Confirm cost against the live OpenAI dashboard,
> verify the CC0 net's status in writing, and have an IP lawyer sign off before a
> commercial launch.

## Cost basis (GPT‑5.4 vision)

~**$0.0113 (~300 VND) per hint** (range $0.0098–$0.0128). Output tokens dominate
(15$/M output vs 2.50$/M input on a ~2,128-input / ~400-output call). `gpt-5.4-mini`
would be ~$0.0040/hint — a future lever if its board-reading accuracy holds up.

## Ads (rewarded) — a capped loss-leader

At Vietnam rewarded eCPM (~$2–3 → **~$0.002/view, ~52 VND**), one ad earns far
less than one hint costs (true break-even ≈ **6–8 ads per hint**). Policy:
**1 ad = 1 hint** as a bounded subsidy that drives engagement and pushes users to
IAP. (Local model: the reward is credited client-side in `onUserEarnedReward`; there
is no SSV. A determined user can edit the local counter — the backend's per-device
daily cap, not the wallet, is what bounds OpenAI cost.)

## IAP — repriced packs (decision: stay on gpt‑5.4)

The originally-proposed packs (100/9,000₫, 500/49,000₫) **lose money** — after Play's
15% fee they net only ~78–85 VND/hint vs the ~300 VND cost. Repriced to ~2–2.7× cost
(`HINT_PACKS` in `wallet.constants.ts`):

| Product id | Hints | Price (₫) | Net/hint after 15% |
|---|---|---|---|
| `hints_20` | 20 | 19,000 | ~810₫ (~2.7×) |
| `hints_60` | 60 | 49,000 | ~694₫ (~2.3×) |
| `hints_150` | 150 | 99,000 | ~561₫ (~1.9×) |

Hint **counts** live in the client (`kHintPacks` in `hint_pack.dart`) and are credited
locally on a confirmed purchase. Confirm the per-country VND prices in Play Console the
day you list.

## "Use our key" on-device (#3) — there is no secure client-side key

Any OpenAI key shipped or served to the app is extractable and would fund unbounded
spend. So **"use our service (our key)" routes through the backend** (which holds the
key + enforces the wallet) — i.e. Cloud mode. The Flutter setting:
- **Use our service (our key)** → Cloud path, consumes a server hint, **hides** the
  personal-key field.
- **Use my own key** → on-device direct vision, the user pays, no wallet/ads/IAP.

Never offer a third "our key, on device" option.

## Licensing decision (engine + net)

- **Pikafish is GPLv3.** Server-side use is fine and triggers **no** source disclosure
  (GPLv3 ≠ AGPL — running it isn't "distribution"). Bundling it in the APK **is**
  distribution and would force the whole app's source under GPLv3.
- **The stock `pikafish.nnue` is "no commercial use without permission"** — unusable
  in a monetized app, server or device.
- **Decision:** the monetized solve runs **server-side**; the on-device **bundled
  engine is dropped from the paid build** (on-device = your-own-key vision only). Use
  the **CC0 Fairy‑Stockfish Xiangqi net** server-side for a commercially-clean network
  (verify the exact net file's CC0 status in writing — the page's CC0 rule literally
  covers "2026+" nets).

## Architecture

```
Flutter ──register(deviceId)──▶ POST /api/accounts/register ─▶ {token, accountId, balance}
Flutter ──Bearer token──▶ POST /api/analysis/screenshot ─(WALLET_ENABLED)▶ spend 1 hint, solve, refund-on-fail
Google  ──signed SSV────▶ GET  /api/ads/ssv?...&custom_data=<accountId> ─▶ verify → credit (capped)
Flutter ──Bearer token──▶ POST /api/iap/validate {productId, purchaseToken} ─▶ verify(Play) → credit pack
Flutter ──Bearer token──▶ GET  /api/wallet ─▶ {balance}  (display only; server is authoritative)
```

Wallet balances mutate ONLY via `WalletRepository.applyDelta` (atomic, audited,
ref-deduped) — a tampered local counter can't mint hints.

### Money-safety: a charged purchase always gets credited

A user can be charged by Google but lose the network before the hints land. Both
failure halves are closed, and every credit path is idempotent (`iap:<orderId>`),
so retries can't double-credit:

- **Client never reached `/api/iap/validate`** (backend unreachable at purchase
  time). The client persists `{purchaseToken → productId}` to secure storage
  *before* calling validate (`AccountStore.addPendingPurchase`) and only clears it
  *after* a confirmed credit. On the next launch `WalletNotifier._retryPendingPurchases`
  re-sends each unconfirmed token. The Play purchase itself also stays unacknowledged
  (validate-before-`completePurchase`), so Google auto-refunds after 3 days if we
  truly never credit — the user is never charged for nothing.
- **Client reached the endpoint but Play verify failed** (transient Play API error).
  The controller records the token in `pending_purchases` *before* verifying and
  returns `IAP_PENDING` (not a hard `IAP_INVALID`) on failure. `PurchaseReconcileService`
  (`@Cron`, every 30 min) re-verifies each pending token against the Play Developer
  API, credits on success, and bumps an attempt counter (capped) otherwise.

## Status

**Done (this repo):**
- ✅ Default model **GPT‑5.4** (backend + on-device).
- ✅ Backend **`wallet` module**: anonymous accounts, server-authoritative balances +
  ledger, free-hint seeding (idempotent per device), atomic spend/refund, capped
  rewarded-ad credit with **real ECDSA SSV verification** (`admob-ssv.verifier.ts`,
  injectable key source, dev-bypass flag), IAP credit with a Play-verifier seam
  (sandbox default / `google` to wire), and a `HintMeterInterceptor` on the solve
  path gated by `WALLET_ENABLED`. Tested.

- ✅ **Flutter client** (`lib/features/monetization/`): anonymous account
  (`AccountStore`, secure storage) + server-authoritative balance (`WalletNotifier`,
  self-heals a stale token, in-flight register guard); **rewarded ads**
  (`RewardedAdService`, SSV `custom_data = accountId`, test ad units via
  `ad_helper.dart`); **IAP** (`BillingService`, consumables → validate with the
  backend BEFORE completing the purchase → wallet refresh); **wallet UI**
  (balance chip in the home app bar + "get more hints" sheet); the **Service**
  setting (our-key/own-key, hides the key field for "our service"); the account
  token is sent on Cloud solves (metering) and a `NO_HINTS` (402) opens the sheet.
  `MobileAds.initialize()` in `main.dart`; AdMob test app id in the manifest.

- ✅ **Release-ready Android config**: signing via `key.properties` (debug fallback);
  release builds are HTTPS-only (cleartext is debug-only); **UMP ad consent**
  (`consent_manager.dart`, gathered before ad init); billing permission; verified
  `flutter build appbundle --release`. **Dev mock mode** (`--dart-define=MOCK_MONETIZATION=true`)
  demos the wallet/ads/store UI with dummy data — no accounts/backend needed.

**📦 To publish:** follow **[PUBLISHING.md](PUBLISHING.md)** — most identifiers are now
real (bundle id `com.codertapsu.xiangqi_solver`, AdMob ids, shared upload keystore, live
privacy policy at `codertapsu-web.web.app/xiangqi-solver/privacy`). Remaining: Play Console
app + consumable products + service account, the Data Safety form, and the AdMob SSV bridge.

**🌐 HTTP backend + ads (current reality):** the backend runs over plain HTTP
(`http://103.157.205.175:3000`). Cloud analysis, the wallet, and **IAP purchases work over
HTTP today** (the release app reaches it via a scoped cleartext exception in
`network_security_config.xml`). Only the **AdMob SSV callback** needs HTTPS, so it's bridged
by a small **Firebase Cloud Function** (`codertapsu-web/functions/xiangqiAdSsv`) that forwards
Google's signed callback to the existing `/api/ads/ssv` — no backend change, one wallet. Ads
ship **off** (`kAdsEnabled=false`) until that function is deployed (needs Firebase **Blaze**);
the app is **purchases-only** until then. Full runbook: **[SSV_FIREBASE.md](SSV_FIREBASE.md)**.

- ✅ **Durable wallet** — `SqliteWalletRepository` (transactional WAL SQLite);
  enabled by `WALLET_DB_PATH=./data/wallet.db` (empty = in-memory for dev/tests).
  Tested incl. balance + dedupe surviving a restart.
- ✅ **Commercial engine path** — the server engine takes `ENGINE_UCI_VARIANT`; set
  it to `xiangqi` and point the binary/net at **Fairy‑Stockfish + the CC0 net** for a
  commercially-clean solve. The **on-device engine is dropped from release builds**
  (GPLv3 .so + non-commercial net ship only in DEBUG via `src/debug/jniLibs/`; release
  AAB is ~56 MB and contains neither). On-device mode in release = BYO-key vision only.
- ✅ **Real Play verification** — `PLAY_VERIFY_MODE=google` calls the Play Developer
  API (`google-auth-library`) to verify the purchase + read the orderId; fails closed
  without `PLAY_SERVICE_ACCOUNT_PATH`/`ANDROID_PACKAGE_NAME`. Sandbox stays the dev default.
- ✅ **No-double-charge guarantee** (see *Money-safety* above) — server-side
  `PurchaseReconcileService` (`@Cron` 30 min) re-verifies tokens charged-but-not-credited;
  client-side `AccountStore` pending-purchase persistence + `WalletNotifier` launch retry
  cover a backend that was unreachable at purchase time. Both credit idempotently. Tested.

**To do (your inputs, not code):**
1. **Flip to real ids** — AdMob rewarded unit + app id (manifest + `kUsingRealAds = true`
   in `ad_helper.dart`); create the Play products; set the prod env (`WALLET_ENABLED=true`,
   `WALLET_DB_PATH`, `PLAY_VERIFY_MODE=google` + service account). See **[PUBLISHING.md](PUBLISHING.md)**.
2. **Provide Fairy‑Stockfish + the CC0 net** for the server, and verify the
   `UCI_Variant`/`EvalFile` handshake against your build (the engine integration test
   self-skips without a binary). Ship the GPLv3 license text + a source offer.

## External inputs needed (from you)

- AdMob: app id + a **rewarded** ad unit id; enable **SSV** pointing at
  `https://<host>/api/ads/ssv`.
- Play Console: create consumable products `hints_20` / `hints_60` / `hints_150` with
  per-country VND prices; a service account for purchase verification.
- Legal: confirm the CC0 net file status; decide hosting for the GPL engine source offer.
