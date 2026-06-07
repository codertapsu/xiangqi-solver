# Publishing to Google Play — step-by-step

> Companion to [MONETIZATION.md](MONETIZATION.md). This is the end-to-end guide to take the app
> from its current **test-wired** state to a live Play listing. The code is monetization-complete;
> publishing is mostly replacing test identifiers with real ones and satisfying Play policy.
> **Not legal advice** — review the policy/Data-Safety/privacy items with someone qualified.

> **⚠️ Hints are now DEVICE-LOCAL.** The server-side hint wallet, AdMob **SSV**, and server-side IAP
> validation were **removed**. A rewarded ad credits +1 hint in the client callback; a confirmed Play
> purchase credits the pack's hints locally; the client spends one hint per cloud analysis. **No SSV
> callback to configure, no Play Developer service account needed for hints, no `WALLET_*` env.** The
> backend only protects the analysis endpoints with a per-IP throttle + a per-device daily cap
> (`x-device-id`, `RATE_LIMIT_DEVICE_*`). Any step below mentioning **SSV**, a **server wallet/account
> token**, `WALLET_ENABLED`, `/api/ads/ssv`, `/api/accounts/register`, `/api/iap/validate`, or a
> **Play Developer service account** is **obsolete** — skip it. The bundle id, keystore, AdMob ids,
> network config, privacy policy, IAP product creation, and Data Safety steps still apply.

## Already done in the codebase (you don't re-do these)

- **Final bundle id** `com.codertapsu.xiangqi_solver` (gradle namespace + applicationId; Kotlin package).
- **Shared upload keystore cloned** into `android/key.properties` + `android/app/upload-keystore.jks`
  (same `upload` key as the other codertapsu apps; gitignored). Release signing wired in `build.gradle.kts`.
- **Real AdMob ids wired**: manifest app-id `ca-app-pub-6124263664453069~3920691029`; rewarded unit
  `ca-app-pub-6124263664453069/8730164575` (Android) in `ad_helper.dart`; iOS stays on Google's test unit;
  `kUsingRealAds = true`.
- **Local hint wallet** (`SharedPreferences`): 10 free on install; rewarded ad → +1; purchase → +pack;
  one spent per cloud analysis. Ads are always offered (test units until `kUsingRealAds = true`); no SSV.
- **Network policy**: release is HTTPS-only **except** a scoped cleartext exception for the current HTTP
  backend host (`res/xml/network_security_config.xml`); debug allows any LAN/emulator host.
- **`BACKEND_URL` default** points at the live backend `http://103.157.205.175:3000` (override per build).
  The app sends an `x-device-id` header so the backend can rate-limit per device.
- **Privacy policy LIVE**: <https://codertapsu-web.web.app/xiangqi-solver/privacy> (generated from
  `codertapsu-web/apps.json`; in-app link in Settings → Privacy). The shared `app-ads.txt` already covers it.
- **UMP consent** gathered before ad init (`consent_manager.dart`); billing permission; wallet/ads/IAP UI.
- A verified **release AAB builds** (`flutter build appbundle --release`).
- **Dev mock mode** — run with `--dart-define=MOCK_MONETIZATION=true` to demo the wallet/ads/store UI with
  dummy data (local balance, instant 'watch ad'/'buy'), no AdMob/Play needed. Default off; never ship it on.

## Release checklist (overview)

1. ~~Create an AdMob account, register the Android app, create one Rewarded ad unit~~ — **DONE** (real ids wired).
2. In the Rewarded unit, enable Server-Side Verification (SSV) and set the callback to the **Firebase SSV function URL** (HTTPS) — see [SSV_FIREBASE.md](SSV_FIREBASE.md). (The backend `/api/ads/ssv` is HTTP, so Google can't call it directly; the function bridges it.)
3. ~~Fill `_RealUnits.rewardedAndroid` in ad_helper.dart~~ — **DONE** (`ca-app-pub-6124263664453069/8730164575`).
4. ~~Replace the AdMob APPLICATION_ID meta-data~~ — **DONE** (`ca-app-pub-6124263664453069~3920691029`).
5. ~~Flip kUsingRealAds = true~~ — **DONE**. Which ad formats actually SHOW is gated at runtime by the remote-config flags from `GET /api/config` (`FEATURE_BANNER_ADS` on; `FEATURE_REWARDED_ADS` / `FEATURE_APP_OPEN_ADS` off by default) — there is no `kAdsEnabled` build flag.
6. Create the app in Google Play Console (package name **`com.codertapsu.xiangqi_solver`**), choose Play App Signing, and download the signing details.
7. ~~Generate an upload keystore + key.properties~~ — **DONE** (shared codertapsu `upload` key cloned in; `build.gradle.kts` picks it up).
8. ~~Write + host a public Privacy Policy~~ — **DONE & LIVE**: paste <https://codertapsu-web.web.app/xiangqi-solver/privacy> into Play Console (App content > Privacy policy).
9. Complete the Data Safety form for THIS app's data (device id, screenshots, purchase/account data, AdMob).
10. Complete App access (login-free or provide a test login), Ads declaration (Yes), Content rating, Target audience, and the MediaProjection/overlay permission declarations.
11. Create the three consumable in-app products hints_20 / hints_60 / hints_150, set VND prices (19,000 / 49,000 / 99,000) per country, and activate them.
12. Create a Play Developer API service account, grant it access, and download its JSON key for server-side purchase verification.
13. Add license testers (Play Console account list) and internal testers so IAP and ads can be tested without real charges.
14. Stand up the production backend over HTTPS with WALLET_ENABLED=true, ADMOB_SSV_ALLOW_UNVERIFIED=false, PLAY_VERIFY_MODE=google (+ service-account wired), or keep sandbox/unverified ONLY for the test track.
15. Build the release AAB with --dart-define=BACKEND_URL=https://<your-host> (and any other dart-defines), signed by the upload key.
16. Upload the AAB to the Internal testing track, opt in as a tester, and run the full pre-launch verification checklist below.
17. Promote through Closed/Open testing as desired, then submit the Production release for review.


This guide takes the app from the current TEST-wired state to a live Play listing. The codebase is already monetization-complete; publishing is mostly about replacing test identifiers with real ones and satisfying Play policy.

**What is already wired (do not re-implement):**
- Backend wallet endpoints under the `/api` prefix: `POST /api/accounts/register`, `GET /api/wallet`, `GET /api/ads/ssv` (AdMob SSV), `POST /api/iap/validate`.
- Flutter client: anonymous account + secure-storage token, `RewardedAdService` (sends SSV `custom_data = accountId`), `BillingService` (validate-before-complete), wallet UI, `MobileAds.initialize()` in `main.dart`.
- Server-authoritative hint packs `hints_20 / hints_60 / hints_150` (counts live in `apps/backend/src/modules/wallet/wallet.constants.ts`).
- Real ECDSA SSV verification (`admob-ssv.verifier.ts`) and a Play-verifier seam (`play-purchase.verifier.ts`).

**The exact files/flags — most are DONE; what's left to flip for release:**
| Concern | File / location | State | Action left |
|---|---|---|---|
| Real ad units | `ad_helper.dart` | ✅ `kUsingRealAds = true`; real Android unit wired | none |
| AdMob App ID | `AndroidManifest.xml` (`…ads.APPLICATION_ID`) | ✅ `ca-app-pub-6124263664453069~3920691029` | none |
| Hint wallet | device-local (`SharedPreferences`) | ✅ ad → +1, purchase → +pack, spend per cloud solve | none (no server wallet) |
| Backend URL | `--dart-define=BACKEND_URL=…` (`app_constants.dart`) | ✅ default `http://103.157.205.175:3000` | switch to `https://…` when the backend gets TLS |
| Release signing | `android/key.properties` + `android/app/upload-keystore.jks` | ✅ shared `upload` key cloned in | none |
| Cleartext HTTP | `res/xml/network_security_config.xml` | ✅ release allows cleartext to the backend host only | remove the exception once the backend is HTTPS |
| AdMob SSV | — | ❌ removed (local rewards, no SSV) | nothing to configure |
| Backend abuse cap | `apps/backend/.env` (`RATE_LIMIT_DEVICE_*`) | ✅ per-IP throttle + per-device daily cap (default 100/day) | tune the limits for your traffic |

App identity (already set, confirm before first upload): `applicationId = com.codertapsu.xiangqi_solver`, `versionName/versionCode` from `pubspec.yaml` `version: 1.0.0+1`, `minSdk 26`, `targetSdk 35`, `compileSdk 36`.

> Note: the `~` separator is an AdMob **App ID**; the `/` separator is an **ad unit ID**. Do not swap them.


### 1a. Create the AdMob app
1. Go to https://apps.admob.com → **Apps → Add app → Android**. If the app is not yet on Play, select "No, it isn't listed yet" (you can link it to the Play listing after publishing).
2. After creation, copy the **App ID** — it looks like `ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY` (tilde). FILL IN: `<YOUR_ADMOB_APP_ID>`.

### 1b. Create the Rewarded ad unit
1. In the app → **Ad units → Add ad unit → Rewarded**.
2. Set the reward to **1 item** (the actual hint amount is decided server-side; AdMob's reward value is cosmetic). Save.
3. Copy the **Ad unit ID** — `ca-app-pub-XXXXXXXXXXXXXXXX/ZZZZZZZZZZ` (slash). FILL IN: `<YOUR_REWARDED_UNIT_ID_ANDROID>` (and `<…_IOS>` only if you ship iOS).

### 1c. Enable Server-Side Verification (SSV)
1. Open the Rewarded ad unit → **Server-side verification** section → enter the callback URL:
   `https://<YOUR_PUBLIC_HOST>/api/ads/ssv`
   This MUST be a public HTTPS URL reachable by Google. The route is `GET` and lives in `apps/backend/src/modules/wallet/ads.controller.ts`.
2. How the contract works (already implemented, for your verification): Google appends query params including `transaction_id`, `custom_data`, `key_id`, and `signature`. The client sets `custom_data = accountId` via `ServerSideVerificationOptions` in `rewarded_ad_service.dart`. The backend verifies the ECDSA-SHA256 signature against Google's published keys (`https://www.gstatic.com/admob/reward/verifier-keys.json`, fetched by `ssv-key-provider.ts`), then credits hints to the account in `custom_data`, capped at `MAX_AD_HINTS_PER_DAY` (3/24h). It always returns HTTP 200 so Google doesn't retry.
3. There is no SSV "secret" to paste anywhere — verification is signature-based, so the only AdMob-side value is the callback **URL**.

### 1d. Put the IDs into the app
- **Manifest App ID** — in `apps/mobile/android/app/src/main/AndroidManifest.xml`, replace:
  ```xml
  android:value="ca-app-pub-3940256099942544~3347511713"
  ```
  with your real `<YOUR_ADMOB_APP_ID>`. (The app crashes on launch if this meta-data is missing or malformed.)
- **Rewarded unit IDs** — in `apps/mobile/lib/features/monetization/data/ad_helper.dart`, set:
  ```dart
  static const rewardedAndroid = '<YOUR_REWARDED_UNIT_ID_ANDROID>';
  static const rewardedIos     = '<YOUR_REWARDED_UNIT_ID_IOS>'; // or leave placeholder if Android-only
  ```
  in `_RealUnits`.
- **Flip the flag** — set `const bool kUsingRealAds = true;` in the same file.

> Keep `kUsingRealAds = false` while developing. Showing real ads to yourself = invalid traffic and can get the AdMob account suspended. Use AdMob **test devices** (register your device's advertising ID under AdMob → Settings → Test devices) if you must see live-unit fills before launch.


### 2a. Create the app
1. https://play.google.com/console → **Create app**. App name, default language (set Vietnamese if VN is the primary market), App/Game = App, Free/Paid = **Free** (monetization is via IAP/ads).
2. Accept the developer program & US export declarations. The package name `com.codertapsu.xiangqi_solver` is fixed at first upload — it must match `applicationId` in `build.gradle.kts`.

### 2b. App signing (Play App Signing + your upload key)
Play App Signing is the default and recommended path: you sign the AAB with an **upload key**; Google re-signs with the **app signing key** it manages.
1. Generate an upload keystore (see §6 for the keytool command and `key.properties`).
2. On first AAB upload Play enrolls you in Play App Signing automatically using your upload key as the registered upload certificate.
3. **Record the SHA-1/SHA-256 of the upload cert** (Play Console → **Setup → App signing**). You'll need these if you later add Google sign-in, Firebase, or API key restrictions. Not required for the current feature set, but capture them now.

### 2c. Internal testing track (do this before Production)
1. **Testing → Internal testing → Create new release**.
2. Upload the signed AAB (§7). Internal testing has no review delay and is the right place to validate IAP + ads + SSV end to end.
3. Add testers by email list, copy the opt-in URL, and accept it on the test device's Google account. IAP and license-tester behavior only work for accounts on the testers/license-testers lists.

> Order matters: you generally must create at least one release (even internal) and complete the Data Safety + content forms before products and store listing can go fully active. Create the consumables (§5) as soon as the app exists; they don't need a published release but do need the app's billing to be set up.


Create three **in-app products** of type **Consumable** so they can be repurchased after being consumed. The product **IDs must exactly match** the server map in `wallet.constants.ts` and the `productId` the client sends to `POST /api/iap/validate` — a mismatch yields `IAP_UNKNOWN_PRODUCT`.

**Monetize → Products → In-app products → Create product** (×3):

| Product ID (exact) | Suggested name | Hints granted (server-side) | Base price (VND) |
|---|---|---|---|
| `hints_20` | 20 Hints | 20 | ₫19,000 |
| `hints_60` | 60 Hints | 60 | ₫49,000 |
| `hints_150` | 150 Hints | 150 | ₫99,000 |

Steps for each:
1. Set the **Product ID** exactly as above (it cannot be changed later).
2. Add a name + description (localize to vi-VN).
3. Set the price: enter the VND base price, then review per-country pricing. Confirm the VND figures the day you list — Play applies tax-inclusive rounding and the net-after-fee economics assume these prices (see `docs/MONETIZATION.md`).
4. **Activate** the product.

Notes:
- The hint **count is never trusted from the client** — the server maps `productId → hints` (`hintsForProduct()`), so the only thing that must align is the **ID string**. FILL IN nothing here besides the localized names/prices.
- These are managed by `in_app_purchase: ^3.2.3`. The client validates with the backend BEFORE calling `completePurchase`, and consumables are consumed so they can be bought again.


Production must move `PLAY_VERIFY_MODE` from `sandbox` to `google`. In `sandbox` the backend trusts the client's token (DEV ONLY — anyone could POST a fake token to mint hints). In `google` mode the backend calls the Play Developer API (`androidpublisher.purchases.products.get`) to confirm `purchaseState === 0` and return the real `orderId`. **The `google` path currently fails closed** (`play-purchase.verifier.ts` has a `TODO(prod)` and rejects until the Play Developer API client is wired) — wiring it is required before accepting real purchases.

### Create the service account
1. **Google Cloud Console** (https://console.cloud.google.com) → create/select a project → **Enable APIs → Google Play Android Developer API**.
2. **IAM & Admin → Service Accounts → Create service account** (e.g. `play-iap-verifier`). Create a **JSON key** and download it. FILL IN: store this as a secret on the backend host (e.g. `GOOGLE_SERVICE_ACCOUNT_JSON` / a mounted file path) — never commit it.
3. **Grant Play access:** Play Console → **Users and permissions → Invite new users** → add the service account email → grant at least **View financial data** and **Manage orders and subscriptions** (or the granular "View app information" + "Manage orders") for this app. (Older flow: Play Console → Setup → API access → link the GCP project and grant access to the service account.)
4. Wire the JSON into the backend's `PlayPurchaseVerifier` (the `// TODO(prod)` in `play-purchase.verifier.ts`) so `google` mode returns `{ valid: purchaseState === 0, orderId }`.

### License testers (test IAP without being charged)
- Play Console → **Setup → License testing** → add tester Google accounts. License testers get test purchases (no real charge, refundable) for products in non-production tracks.
- These accounts must also be on the **Internal testing** testers list to install the build.

> Until step 3/4 is done you can validate the full purchase UI in `PLAY_VERIFY_MODE=sandbox` on the internal track, but DO NOT ship Production in sandbox mode — it would let anyone mint paid hints.


### 5a. Privacy policy (required)
Host a public privacy policy and paste the URL in **Policy → App content → Privacy policy**. FILL IN: `<YOUR_PRIVACY_POLICY_URL>`. It must disclose: anonymous account/device-id handling, that **screenshots of the user's screen are captured and uploaded** to your backend for board analysis, use of **Google AdMob** (advertising/identifiers), and **Google Play Billing** purchases.

### 5b. Data Safety form (answer for THIS app)
**Policy → App content → Data safety.** Based on what this app actually does:
- **Device or other IDs** — *Collected*. A stable per-install `deviceId` is sent to `POST /api/accounts/register` (used to seed/track the hint wallet). AdMob also uses an advertising ID. Purpose: App functionality, Account management, Advertising/marketing.
- **Photos / app activity (screenshots)** — the app captures the screen via MediaProjection and **uploads the screenshot** to your backend for analysis. Declare this as user-content/photos collected and transmitted, purpose **App functionality**. State whether screenshots are stored or processed-and-discarded (match your backend's actual retention — confirm in `storage.service.ts` and state it honestly).
- **Purchase history** — IAP transactions (Google Play Billing). Purpose: App functionality.
- **In-app account (anonymous)** — token-based, no name/email. Declare an account is created.
- For each: indicate whether **encrypted in transit** (Yes — release builds are HTTPS-only) and whether users can request deletion.
- Declare **data shared with third parties**: Google AdMob (advertising), Google Play (billing). Your own backend is first-party processing, not "sharing."

> Be precise about screenshot retention. If the backend keeps images, you must say so; if it processes-and-discards, say that. Match the privacy policy and Data Safety answers to each other.

### 5c. Ads declaration
**App content → Ads → Yes, the app contains ads** (AdMob rewarded). Failing to declare ads is a common rejection.

### 5d. Target API level
Play requires a recent target API for new apps/updates. This app sets `targetSdk = 35` in `build.gradle.kts` (Android 15), which satisfies the current new-app target-API requirement as of 2026. `compileSdk = 36` and `minSdk = 26` (overlay needs API 26). Keep `targetSdk` at the latest Play-required level; bump if Play flags it.

### 5e. Permission justifications (sensitive permissions)
Play flags several permissions this app declares; prepare written justifications and, where prompted, a short screen-recording showing the in-app flow:
- **`SYSTEM_ALERT_WINDOW` (overlay)** — "Displays a small, clearly-labeled floating widget that shows the recommended Xiangqi move over the board. The overlay is user-initiated and dismissible; it is core to the solver UX."
- **MediaProjection (`FOREGROUND_SERVICE_MEDIA_PROJECTION` + `FOREGROUND_SERVICE`)** — "Captures the current screen, only after the user explicitly grants the system MediaProjection consent dialog (`MediaProjectionPermissionActivity`), to read the board position for analysis. A foreground service with type `mediaProjection` keeps the capture alive while solving; the persistent notification informs the user." Capture is started by a user action and not run silently.
- **`POST_NOTIFICATIONS`** — required for the foreground-service notification on Android 13+.
- **`WAKE_LOCK`** — keeps the capture/analysis pipeline alive during a solve.
- **`com.android.vending.BILLING`** — Google Play in-app purchases (hint packs).
- **`INTERNET`** — backend communication.

> Foreground-service-type and MediaProjection apps often get extra scrutiny. Emphasize that capture is explicit, user-initiated, scoped to producing a move suggestion, and never silent/background.


### 6a. Generate an upload keystore
Run (FILL IN the alias and passwords; store the file OUTSIDE the repo, e.g. `~/keystores/`):
```bash
keytool -genkey -v \
  -keystore ~/keystores/xiangqi-upload.jks \
  -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias xiangqi-upload
```
Back this file up securely — losing it means you can't ship updates with the same upload key (recoverable via Play upload-key reset, but disruptive). Never commit it.

### 6b. Create `apps/mobile/android/key.properties`
This file is already covered by `android/.gitignore` (`key.properties`, `**/*.keystore`, `**/*.jks`), so it won't be committed. Create it with:
```properties
storePassword=<YOUR_STORE_PASSWORD>
keyPassword=<YOUR_KEY_PASSWORD>
keyAlias=xiangqi-upload
storeFile=/Users/you/keystores/xiangqi-upload.jks
```
`storeFile` may be absolute or relative to `apps/mobile/android/`.

### 6c. Signing config (already implemented — just confirm)
`apps/mobile/android/app/build.gradle.kts` already reads `key.properties` and wires a `release` signing config:
- If `key.properties` exists → release is signed with your upload key.
- If it is absent → release falls back to the **debug** key so local `flutter build` still works.

**You must have a real `key.properties` present at build time for the store AAB.** A debug-signed AAB will be rejected by Play. Verify after build with:
```bash
# confirm the release artifact is NOT debug-signed
apksigner verify --print-certs <path-to-apk-or-extracted>  # or check via Play upload
```
No edits to `build.gradle.kts` are required; the signing plumbing is done.


### 7a. Pre-build checklist (release-only edits)
1. `kUsingRealAds = true` in `ad_helper.dart`, with real `_RealUnits` IDs (§1).
2. Real AdMob App ID in `AndroidManifest.xml` (§1).
3. `key.properties` present (§6).
4. Bump `version:` in `pubspec.yaml` if re-uploading (each AAB needs a higher `versionCode` = the `+N` suffix).

### 7b. HTTP / cleartext
The release backend is plain **HTTP** for now (`http://103.157.205.175:3000`, no TLS yet). The MAIN manifest wires `android:networkSecurityConfig="@xml/network_security_config"`, and `src/main/res/xml/network_security_config.xml` permits cleartext to **that one host only** (everything else stays HTTPS-only). So an installed RELEASE reaches the default backend out of the box — no dart-define needed. Debug builds widen this to any LAN/emulator host. **When the backend gets TLS**, point `BACKEND_URL` at the `https://…` origin and delete the cleartext exception from `network_security_config.xml`.

### 7c. Build the App Bundle
```bash
cd apps/mobile
flutter clean
flutter pub get
flutter build appbundle --release
```
- **No dart-defines are required.** `BACKEND_URL` defaults to the live backend, and the AI/engine providers default to the REAL ones (`openai` / `pikafish`).
- **Do NOT pass `--dart-define=AI_PROVIDER=mock`** (or `ENGINE_PROVIDER=mock`). The backend honors an explicit `mock`, so that ships a build whose "our key" cloud analyses return a FAKE board/move. Only use the mock providers for a deliberate demo build against a mock backend.
- Override only if you need to: `--dart-define=BACKEND_URL=https://<host>` once the backend has TLS, or `--dart-define=MY_SIDE=black` to flip the default side.
- Output: `apps/mobile/build/app/outputs/bundle/release/app-release.aab`. Upload **this `.aab`** to Play (not an APK).

### 7d. Build JDK
Per the project build notes, use **JDK 21** (not 26) for the APK/AAB toolchain, `compileSdk 36`. Ensure `JAVA_HOME` points at JDK 21 before building, or Gradle may fail.

> Tip: keep two run configs — a dev one with test ad units / `http://10.0.2.2:3000` / cleartext-debug, and the release command above. Never ship the test ad units.


The same backend serves dev and prod via env flags (`apps/backend/.env`, validated by `env.validation.ts`). Hints are **device-local** now, so there is **no** wallet / SSV / IAP-validation env to set (`WALLET_ENABLED`, `ADMOB_SSV_ALLOW_UNVERIFIED`, `PLAY_VERIFY_MODE` no longer exist). For the **Production** backend set:

```bash
AI_PROVIDER=openai             # real vision (gpt-5.4); requires OPENAI_API_KEY
OPENAI_API_KEY=<secret>
ENGINE_PROVIDER=pikafish       # real engine (server-side; see MONETIZATION.md)
PIKAFISH_BINARY_PATH=<path>    # + PIKAFISH_NNUE_PATH for the net
# Per-device abuse cap — the cost guard now that hints are device-local:
RATE_LIMIT_DEVICE_LIMIT=1000   # analyses / device / day (RATE_LIMIT_DEVICE_WINDOW_SECONDS)
# Remote feature flags served by GET /api/config (tunable without a release):
# FEATURE_BANNER_ADS, FEATURE_REWARDED_ADS, FEATURE_APP_OPEN_ADS,
# HINTS_FREE_ON_INSTALL, HINTS_OWN_KEY_DIVISOR, ONDEVICE_* — see .env.example.
```

Deployment requirements:
- **Reachable host**: the backend must be internet-reachable at the `BACKEND_URL` the app ships with (`http://103.157.205.175:3000` by default). HTTPS is recommended but not yet wired; when you add TLS, update `BACKEND_URL` + the cleartext exception (§7b).
- **No server wallet to persist**: hints live on the device (`SharedPreferences`). There is no server balance, SSV callback, or IAP-validation endpoint to deploy or make durable — a backend restart loses nothing hint-related.
- **Cost guard**: the only server-side abuse protection is the per-IP throttle (`RATE_LIMIT_*`, which now SKIPS `GET /api/config`) plus the per-device daily cap (`RATE_LIMIT_DEVICE_*`, keyed by `x-device-id`). Tune these for your traffic/budget — they bound OpenAI spend per device.


Run this against the **Internal testing** build (real ad units, real products, HTTPS backend) before promoting to Production.

**Identifiers / config:**
- [ ] `kUsingRealAds == true` and `_RealUnits` IDs are filled (no `0000…`).
- [ ] Manifest `APPLICATION_ID` is your real AdMob App ID (not `…3940256099942544~…`).
- [ ] AAB built with `--dart-define=BACKEND_URL=https://…` and signed by the **upload key** (not debug). Confirm in Play Console the upload is accepted and shows Play App Signing.
- [ ] `versionCode` is higher than any previously uploaded build.

**Ads / SSV:**
- [ ] Watching a rewarded ad credits hints on the SERVER (balance from `GET /api/wallet` increases), not just locally.
- [ ] Backend logs show `SSV: credited N hint(s)` with a valid signature (no `Rejected an SSV callback`).
- [ ] Daily cap works: the 4th ad in 24h does not add hints (`MAX_AD_HINTS_PER_DAY = 3`).
- [ ] `ADMOB_SSV_ALLOW_UNVERIFIED=false` in the environment that serves the SSV URL.

**IAP:**
- [ ] Each of `hints_20 / hints_60 / hints_150` shows the correct VND price and localized name in the in-app sheet.
- [ ] A test/license purchase validates via `POST /api/iap/validate` and credits the correct hint count (20 / 60 / 150).
- [ ] Re-buying the same consumable works (it was consumed) and a replayed token does NOT double-credit (ledger dedupe).
- [ ] Production env has `PLAY_VERIFY_MODE=google` with the service account wired (or a deliberate decision to stay on the test track).

**Wallet / metering:**
- [ ] New install seeds exactly 10 free hints once; reinstall on the same device does NOT re-grant.
- [ ] A Cloud solve spends exactly 1 hint; running out returns `NO_HINTS` (402) and opens the "get more hints" sheet.
- [ ] `WALLET_ENABLED=true` in production.

**Networking / permissions:**
- [ ] Release build reaches the backend over HTTPS (no "could not reach backend"); confirm cleartext is NOT enabled in the release manifest.
- [ ] MediaProjection consent dialog appears before capture; overlay shows the move; foreground-service notification appears on Android 13+.
- [ ] Permission justifications + (if requested) screen recording uploaded for SYSTEM_ALERT_WINDOW and MediaProjection.

**Policy:**
- [ ] Privacy policy URL set and reachable; Data Safety completed and consistent with the policy (device ID, screenshots, purchases, AdMob).
- [ ] Ads = Yes; content rating, target audience, and app access completed.
- [ ] Target API (targetSdk 35) accepted by Play with no warning.

**Durability (release blocker):**
- [ ] Wallet repository is DB-backed (NOT `InMemoryWalletRepository`) so paid balances survive a backend restart.
