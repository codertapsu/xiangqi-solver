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
New installs get **10 free hints** — the count is server-decided via
`POST /api/hints/claim` (`HINTS_FREE_ON_INSTALL`, default 10); users earn more by
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
daily cap, not the wallet, is what bounds OpenAI cost.) Rewarded ads are also
**gated off by default** by remote config (`ads.rewarded`, default false — banners
are the primary format), and real ad units only load when `ads.useReal` is flipped
server-side (default **false** → Google's test units, even on an offline fresh install).

## IAP — repriced packs (decision: stay on gpt‑5.4)

The originally-proposed packs (100/9,000₫, 500/49,000₫) **lose money** — after Play's
15% fee they net only ~78–85 VND/hint vs the ~300 VND cost. Repriced to ~2–2.7× cost
(`kHintPacks` in `lib/features/monetization/domain/hint_pack.dart`):

| Product id | Hints | Price (₫) | Net/hint after 15% |
|---|---|---|---|
| `hints_20` | 20 | 19,000 | ~810₫ (~2.7×) |
| `hints_60` | 60 | 49,000 | ~694₫ (~2.3×) |
| `hints_150` | 150 | 99,000 | ~561₫ (~1.9×) |

Hint **counts** live in the client (`kHintPacks` in `hint_pack.dart`) and are credited
locally when the `purchaseStream` reports `PurchaseStatus.purchased`/`restored`
(`BillingService.onPurchased` → `HintWalletNotifier.add`). The credit lands BEFORE
`completePurchase`, so a purchase delivered while the app was dead is re-surfaced by
the stream on the next launch. There is **no server receipt validation**. Confirm the
per-country VND prices in Play Console the day you list.

## "Use our key" on-device (#3) — there is no secure client-side key

Any OpenAI key shipped or served to the app is extractable and would fund unbounded
spend. So **"our key" board-reading ALWAYS routes through the backend** (which holds
the key + enforces the per-device rate cap). The Flutter setting is a 2×2 — AI-key
source (`ours`/`own`) × engine location (`cloud`/`onDevice`):
- **Use our service (our key)** → vision via our backend (1 hint), **hides** the
  personal-key field; the engine half can still run on-device.
- **Use my own key** → direct OpenAI vision from the device (the user pays OpenAI);
  paired with OUR cloud engine it costs 1 hint per `HINTS_OWN_KEY_DIVISOR` analyses,
  fully local (own key + on-device engine) costs nothing.

Never ship or serve the key itself to the device.

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

## Architecture (device-local wallet)

```
Flutter ──x-device-id──▶ POST /api/hints/claim ─▶ {hints, source}        (once, on first launch)
                          └─ installs.json ledger + grants.json allowlist (HINTS_DATA_DIR)
Flutter ──x-device-id──▶ POST /api/analysis/screenshot[/stream]
                          └─ per-IP throttle + DeviceRateLimitGuard (rolling per-device cap)
AdMob  ──onUserEarnedReward──▶ client credits +1 hint locally            (no SSV)
Play   ──purchaseStream "purchased"──▶ client credits the pack locally   (no receipt validation)
SharedPreferences ◀── hints.balance / hints.seeded / hints.ownKeyCounter
```

The balance lives in `SharedPreferences` (`HintWalletNotifier`,
`lib/features/monetization/presentation/wallet_providers.dart`) and is persisted on
every change. The server keeps **no per-user state** beyond the install ledger.

### Install grant — the anti-reinstall piece

The ONLY server-decided number is the **starting balance**: on first launch the app
calls `POST /api/hints/claim` (keyed by the stable `x-device-id` header, 8–256 chars)
and seeds the local wallet with the result (`apps/backend/src/modules/hints/`).
Priority, highest first:

1. **`grant`** — device is in the manual **`grants.json`** allowlist → its configured
   amount, on EVERY (re)install while listed. Hand-edited (or managed via the
   device-admin console), re-read on mtime change so edits apply WITHOUT a restart,
   and it wins over the ledger.
2. **`returning`** — device already in the **`installs.json`** ledger → **0**
   (reinstalling doesn't re-grant the free hints).
3. **`first_install`** — brand-new device → `HINTS_FREE_ON_INSTALL` (default **10**).

Both files live in `HINTS_DATA_DIR` (default `./data`) and are written atomically
(temp + rename). The ledger write **fails closed** — a failed persist rolls back and
returns a 5xx — and the client **never banks the free hints offline**: a failed claim
just re-claims on the next launch, so an airplane-mode reinstall can't farm hints
(hints are only spendable on cloud solves, which need the network anyway).

### Server-side cost bound

Hints are client-owned, so a tampered counter CAN mint local hints. What actually
bounds our OpenAI/engine spend is the cap on the paid analysis endpoints:
`DeviceRateLimitGuard` allows at most `RATE_LIMIT_DEVICE_LIMIT` (default **100**)
analyses per `RATE_LIMIT_DEVICE_WINDOW_SECONDS` (default **86 400** — daily) rolling
window per `x-device-id` (IP fallback), layered on the global per-IP throttler.
In-memory and per-instance — deliberately a soft cap, not per-user server state.

### Charge rules — charged by what ACTUALLY ran

The client routes each solve across the 2×2 (AI-key source × engine location) with
automatic fallback to OUR backend when the user's own resources fail, then charges
**only on a successful result**, by what **actually ran** — not the originally
selected mode (`AnalysisNotifier` in `solver_providers.dart`):

| What ran | Cost |
|---|---|
| OUR OpenAI key read the board (incl. own-key vision that fell back to our server) | **1 hint** |
| Own-key vision + OUR cloud engine (incl. on-device engine falling back to cloud) | **1 hint per `HINTS_OWN_KEY_DIVISOR`** (default 3; persisted counter) |
| Fully local (own key + on-device engine) | **0** |

An empty wallet surfaces `NO_HINTS` (the UI opens the "get more hints" sheet) before
anything runs; fallbacks that would cost a hint are only taken when the wallet can
afford them; and a fallback that turns a "free" run into a charged one is disclosed
as a warning on the result.

### Ads are remote-config gated

`GET /api/config` flags (client caches the last good value; safe defaults offline):
`ads.banner` (default **on** — the primary format), `ads.rewarded` (default **off** —
the loss-leader is opt-in), `ads.appOpen` (default **off**), and `ads.useReal`
(default **off** — Google's TEST units until the server flips it).

### Historical design (removed): server wallet, SSV, IAP validation

An earlier iteration kept hints server-side: anonymous accounts
(`POST /api/accounts/register` → Bearer token), a server-authoritative balance +
ledger (`WalletRepository.applyDelta`, SQLite-backed), AdMob **SSV**
(`GET /api/ads/ssv`, ECDSA-verified), Play purchase verification
(`POST /api/iap/validate` + a `@Cron` reconcile loop), and a `HintMeterInterceptor`
on the solve path. All of it was **removed** in the local-wallet refactor — those
endpoints and modules no longer exist. Rationale: hints are a soft currency, and the
per-device rate cap bounds the real cost without accounts, tokens, SSV HTTPS
plumbing, or Play service-account ops.

## Status

**Done (this repo):**
- ✅ Default model **GPT‑5.4** (backend + on-device).
- ✅ Backend **`hints` module** (replaced the wallet module): `POST /api/hints/claim`
  install grant behind `DeviceRateLimitGuard`, `installs.json` ledger + `grants.json`
  manual allowlist (atomic temp+rename writes, hot-reloaded grants, admin CRUD used
  by the device-admin console), `HINTS_FREE_ON_INSTALL` / `HINTS_DATA_DIR` /
  `RATE_LIMIT_DEVICE_*` env. Tested.

- ✅ **Flutter client** (`lib/features/monetization/`): **device-local wallet**
  (`HintWalletNotifier`, `SharedPreferences`, seeded once from the claim endpoint —
  no offline free-hint banking); **rewarded ads** (`RewardedAdService`, +1 credited
  in `onUserEarnedReward`, unit ids via `ad_helper.dart` — real Android units exist,
  selected by the remote-config `useRealAds` flag); **IAP** (`BillingService`,
  consumables credited locally from the `purchaseStream`); **wallet UI** (balance
  chip in the home app bar + "get more hints" sheet); the 2×2 mode setting
  (our-key/own-key × cloud/on-device, hides the key field for "our service"); an
  empty wallet surfaces `NO_HINTS` and opens the sheet. `MobileAds.initialize()` in
  `main.dart`; banner/rewarded/app-open formats gated by remote-config flags.

- ✅ **Release-ready Android config**: signing via `key.properties` (debug fallback);
  release allows cleartext only to the backend host (scoped
  `network_security_config.xml` exception); **UMP ad consent**
  (`consent_manager.dart`, gathered before ad init); billing permission; verified
  `flutter build appbundle --release`. **Dev mock mode** (`--dart-define=MOCK_MONETIZATION=true`)
  demos the wallet/ads/store UI with dummy data — no backend needed.

**📦 To publish:** follow **[PUBLISHING.md](PUBLISHING.md)** — most identifiers are now
real (bundle id `com.codertapsu.xiangqi_solver`, AdMob ids, shared upload keystore, live
privacy policy at `codertapsu-web.web.app/xiangqi-solver/privacy`). Remaining: Play Console
app + consumable products and the Data Safety form (no service account — purchases credit
locally).

**🌐 HTTP backend (current reality):** the backend runs over plain HTTP
(`http://103.157.205.175:3000`). Cloud analysis, the install-grant claim, and **IAP
purchases all work over HTTP today** (the release app reaches it via the scoped cleartext
exception above). With SSV gone, **nothing in the money flow requires HTTPS anymore** —
the old Firebase SSV bridge is obsolete. TLS scaffolding exists for when a domain is
ready (`apps/backend/release/Caddyfile` + the TLS section in `DEPLOY.md`). Ads ship on
Google's **test units** until the remote-config `ads.useReal` flag is flipped (rewarded
stays gated off by `ads.rewarded`; banners are the live format).

- ✅ **Commercial engine path** — the server engine takes `ENGINE_UCI_VARIANT`; set
  it to `xiangqi` and point the binary/net at **Fairy‑Stockfish + the CC0 net** for a
  commercially-clean solve. The **on-device engine is dropped from release builds**
  (GPLv3 .so + non-commercial net ship only in DEBUG via `src/debug/jniLibs/`; release
  AAB is ~56 MB and contains neither). On-device mode in release = BYO-key vision only.
- 🗑️ **Removed (historical):** the durable SQLite wallet, real Play Developer API
  verification (`PLAY_VERIFY_MODE`), the SSV verifier, and the no-double-charge
  reconcile loop all went with the server wallet — see *Historical design (removed)*
  above.

**To do (your inputs, not code):**
1. **Go live on ads + IAP** — create the Play consumable products
   (`hints_20`/`hints_60`/`hints_150`) with per-country VND prices; when ready, flip
   the remote-config `ads.useReal` (and optionally `ads.rewarded`) — the real AdMob
   Android units are already in `ad_helper.dart`. See **[PUBLISHING.md](PUBLISHING.md)**.
2. **Provide Fairy‑Stockfish + the CC0 net** for the server, and verify the
   `UCI_Variant`/`EvalFile` handshake against your build (the engine integration test
   self-skips without a binary). Ship the GPLv3 license text + a source offer.

## External inputs needed (from you)

- AdMob: already provisioned (app id + Android banner/rewarded/app-open units under
  `pub-6124263664453069`); your call is WHEN to flip `ads.useReal` / `ads.rewarded`
  in remote config. No SSV setup — rewards credit client-side.
- Play Console: create consumable products `hints_20` / `hints_60` / `hints_150` with
  per-country VND prices. No service account — purchases credit locally.
- Legal: confirm the CC0 net file status; decide hosting for the GPL engine source offer.
