# Publishing to Google Play — end-to-end guide

Ship **Quân Sư Cờ Tướng / Xiangqi Strategist** (`com.codertapsu.xiangqi_solver`) to
the Google Play Console. Targets Play's 2026 baseline: target API 35 (Android 15),
AAB delivery, Play App Signing, Data Safety, AdMob + UMP consent.

> ✦ This is a **process** guide, not a copy-paste recipe. Read each section, confirm
> the assumptions for your account, and replace placeholders with real values. **Not
> legal advice** — review the policy / Data-Safety / GPLv3 items with someone qualified.

> **Companion docs:** [MONETIZATION.md](MONETIZATION.md) (hint economics),
> [ON_DEVICE_ENGINE.md](ON_DEVICE_ENGINE.md) (the GPLv3 engine), and the live
> backend env reference in `apps/backend/.env.example`.

> **⚠️ Historical note — the server-wallet era is gone.** Earlier drafts described a
> server-side hint wallet, AdMob **SSV**, and server-side **IAP validation**
> (`WALLET_ENABLED`, `/api/ads/ssv`, `/api/iap/validate`, a Play Developer service
> account). All of that was **removed**: hints are now **device-local** and the
> backend only meters abuse with rate limits. If you find any of those terms in old
> notes, ignore them — this document is the current source of truth.

---

## 0. Prerequisites & toolchain

- [ ] **Google Play Console** account (one-time $25) with Owner/Admin access.
- [ ] **Upload keystore** stored somewhere recoverable **outside** the repo — losing
      it locks you out of future updates (§2). *(Already provisioned for this app.)*
- [ ] **AdMob account** with the app registered and banner/rewarded/app-open ad units.
      *(Real IDs are already wired — §5.)*
- [ ] **Privacy policy URL** (required: the app uses the Advertising ID + uploads
      screenshots). *(Already live — §10.)*
- [ ] **A reachable backend** at the URL the app ships with (§7).
- [ ] **Toolchain:** Flutter ≥ 3.44, **JDK 21**, Android SDK platform 36.

```sh
flutter doctor -v
flutter --version            # ≥ 3.44.x
java -version                # 21.x  (NOT 26 — Gradle 9.1 rejects JDK 26)
```

> ⚠️ **Use JDK 21**, not the system JDK 26. Gradle 9.1.0 doesn't support JDK 26;
> Flutter normally auto-selects the Android Studio bundled JBR (21). If `JAVA_HOME`
> points at 26, `flutter build` fails. Confirm with `flutter doctor -v` (Java section).

---

## 1. What's already done in this repo

Listed so you don't re-do it and so a reviewer knows what the release expects.

| Concern | State | Where |
|---|---|---|
| Application ID | `com.codertapsu.xiangqi_solver` (namespace + applicationId) | `android/app/build.gradle.kts` |
| AGP / Gradle / Kotlin | 9.0.1 / 9.1.0 / 2.3.20 | `android/settings.gradle.kts`, `gradle-wrapper.properties` |
| `compileSdk` / `targetSdk` / `minSdk` | 36 / 35 / 26 | `android/app/build.gradle.kts` |
| Release signing | shared `upload` key wired (`key.properties` + `app/upload-keystore.jks`, gitignored) | §2 |
| R8 minify + resource shrink | **ON**, with keep rules + native debug symbols | §9, `proguard-rules.pro` |
| Dynamic app name + full i18n (vi/en) | Vietnamese-first; launcher + UI localized | §3 |
| AdMob App ID + real ad units | `…~3920691029` + real banner/rewarded/app-open | §5 |
| Device-local hint wallet + install-grant | no server wallet/SSV/IAP-validation | §4 |
| On-device GPLv3 engine | `libpikafish.so` ships; NNUE downloaded at runtime | §8 |
| Network security config | release allows cleartext to the one HTTP backend host | §7 |
| Privacy policy | LIVE on codertapsu-web | §10 |
| Version | `1.0.0+2` (`versionName 1.0.0`, `versionCode 2`) | `pubspec.yaml` |

A verified **release AAB builds** (`flutter build appbundle --release`) and **launches
clean on a real device** (R8 enabled — see §9).

---

## 2. App identity, signing & versioning

### 2.1 Application ID (fixed at first upload)
`com.codertapsu.xiangqi_solver` — set in `android/app/build.gradle.kts` (`namespace` +
`applicationId`). It **cannot change** after the first upload. A localized app *name*
("Quân Sư Cờ Tướng") is NOT an id change (§3).

### 2.2 Upload key & Play App Signing
Play App Signing is the model: you sign the AAB with an **upload key**; Google re-signs
with the **app signing key** it manages.

This app already has the shared codertapsu `upload` key wired:
- `android/app/upload-keystore.jks` — the keystore (gitignored).
- `android/key.properties` — `storePassword` / `keyPassword` / `keyAlias` / `storeFile`
  (gitignored).
- `android/app/build.gradle.kts` reads `key.properties`: present → release is signed
  with the upload key; absent → release falls back to the **debug** key (so a local
  build still works, but Play would reject it).

**To provision from scratch** (only if the shared key is unavailable):
```sh
keytool -genkey -v -keystore ~/keys/xiangqi-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
Then create `android/key.properties` with the four properties above. **Back the
keystore up** somewhere recoverable — you cannot rotate it without a Play support
ticket. On first AAB upload, Play enrols you in Play App Signing automatically; record
the upload cert SHA-1/SHA-256 from **Setup → App integrity → App signing**.

> Verify a built AAB/APK is NOT debug-signed before uploading:
> `keytool -printcert -jarfile <artifact>` (CN should be your upload key, not
> "Android Debug").

### 2.3 Versioning
`pubspec.yaml` `version: <name>+<code>` is the source of truth (Flutter maps it to
`versionName`+`versionCode`). **`versionCode` must strictly increase on every upload**,
even to internal tracks. Currently `1.0.0+2`. Bump the `+N` for each new upload.

---

## 3. App name & localization (Vietnamese-first)

**Dynamic launcher icon + name** (chosen by the **in-app App-language**, not the
device locale):

| App language | App name | Launcher icon |
|---|---|---|
| Vietnamese (primary market) | **Quân Sư Cờ Tướng** | red |
| Everything else | **Xiangqi Strategist** | (English) |

Already wired — full details + "how to add a variant" in
**[APP_ICON_VARIANTS.md](APP_ICON_VARIANTS.md)**:
- Two `<activity-alias>` launcher entries (`.LauncherVi` default-enabled,
  `.LauncherEn`), each with a fixed label + its own adaptive icon; the app enables
  the one matching `settings.appLanguage` at startup / on background (never live).
- `res/values/strings.xml` → `app_name_vi` / `app_name_en` (fixed, locale-independent).
- The in-app title uses `AppLocalizations.appTitle` via `MaterialApp.onGenerateTitle`.
- A backend `APP_ICON_VARIANT` (`auto`|`vi`|`en`) can override which bundled variant
  shows (Android can't apply a runtime-downloaded icon — new art needs a release).

**UI localization (Flutter gen_l10n):** the whole UI is translated — `lib/l10n/app_en.arb`
(template) + `app_vi.arb`, generated into `lib/l10n/gen/`. The app follows the device
locale among {vi, en} and **falls back to Vietnamese** for any other language. Users can
override it in **Settings → Language → App language** (System / Tiếng Việt / English).
To add a language later: drop a translated `app_<code>.arb`, add `<code>` to
`kSupportedLanguageCodes` (`lib/core/l10n/locale_providers.dart`), add a
`res/values-<code>/strings.xml` for the native overlay/notification strings, and
run `flutter gen-l10n`. (A localized *launcher icon/name* is a separate, optional
step — see [APP_ICON_VARIANTS.md](APP_ICON_VARIANTS.md).)

**In the Play Console store listing** (separate from the launcher label):
- Set the **default listing language to Vietnamese (vi-VN)** (primary market), then
  **add English (en-US)**.
- Title per language: **"Quân Sư Cờ Tướng"** (vi-VN), **"Xiangqi Strategist"** (en-US)
  — Play's title is per-language, ≤ 30 chars.
- For en-US discoverability, lean on **"Chinese Chess / Xiangqi"** in the
  short/long description (Western users search "Chinese Chess" far more than "Xiangqi").
- Localize the **in-app product** names/descriptions to vi-VN too (§6).

First-version release-notes ("What's new") drafts for both languages are in the
[Appendix](#appendix--v100-release-notes-whats-new).

---

## 4. Monetization model — device-local hints

Understand this before the Data Safety form and the verification checklist, because it
removes a lot of what older guides assumed.

- **Hints live ONLY on the device** (`SharedPreferences`). There is **no server
  balance**, no SSV callback, no IAP-validation endpoint to deploy or keep durable. A
  backend restart loses nothing hint-related.
- **Earning hints:** a rewarded ad credits +1 in the client callback; a confirmed Play
  purchase credits the pack's hints locally (no server verification).
- **Spending hints:** the client spends 1 hint per **cloud** analysis (board reading on
  our key, or our cloud engine). Fully on-device + own-key analysis is free. With the
  user's **own** OpenAI key it's metered at 1 hint per N analyses (`HINTS_OWN_KEY_DIVISOR`).
- **Install-grant (anti-abuse):** on first launch the app calls `POST /api/hints/claim`
  with a reinstall-stable `x-device-id`; the backend seeds the starting balance
  (`HINTS_FREE_ON_INSTALL`, default 10) and records the device so uninstall+reinstall
  doesn't re-grant. A manual **"Hint Grants"** allowlist (`grants.json` in
  `HINTS_DATA_DIR`) lets you comp a specific device — users can copy their Device ID
  from **Settings → Privacy → Device ID** and send it to support.
- **Server-side cost guard:** the only abuse protection is the per-IP throttle
  (`RATE_LIMIT_*`) + a per-device daily cap (`RATE_LIMIT_DEVICE_*`, keyed by
  `x-device-id`). Tune these to bound your OpenAI spend (§7).

See [MONETIZATION.md](MONETIZATION.md) for the per-pack economics.

---

## 5. AdMob & UMP consent

### 5.1 IDs (already wired)
| Item | Value | File |
|---|---|---|
| AdMob **App ID** (manifest meta-data) | `ca-app-pub-6124263664453069~3920691029` | `AndroidManifest.xml` |
| Banner unit (Android) | `ca-app-pub-6124263664453069/1354234833` | `lib/features/monetization/data/ad_helper.dart` |
| Rewarded unit (Android) | `ca-app-pub-6124263664453069/8730164575` | same |
| App-open unit (Android) | `ca-app-pub-6124263664453069/9041153161` | same |

> The `~` separator is an **App ID**; the `/` separator is an **ad unit ID**. iOS units
> are still Google sample IDs (ship iOS only after wiring real ones).

### 5.2 Which formats show — driven by the backend, not a build flag
There is no `kUsingRealAds`/`kAdsEnabled` constant to flip. `GET /api/config` returns
feature flags the client honors at runtime:
- `FEATURE_USE_REAL_ADS` (env) → **use real ad units vs Google test units.** Default
  `false`. **Set it `true` on the production backend** so the live app serves real ads.
- `FEATURE_BANNER_ADS` (default `true`) — banners are the primary format (top of Home +
  Settings).
- `FEATURE_REWARDED_ADS` (default `false`) and `FEATURE_APP_OPEN_ADS` (default `false`)
  — enable per your monetization plan.

> ⚠️ Keep `FEATURE_USE_REAL_ADS=false` while testing. Real impressions on your own
> devices are **invalid traffic** and can get the AdMob account suspended. If you must
> see live fills, register your device as an AdMob **test device**.

### 5.3 UMP consent
`mobile_ads_provider.dart` + `consent_manager.dart` gather UMP consent before ad init.
Author the actual messages in **AdMob → Privacy & messaging**: a **GDPR (EEA/UK)**
message and a **US states** message; publish both. When consent can't be obtained, ads
don't load and the banner collapses to `SizedBox.shrink()` — by design.

---

## 6. In-app products (hint packs)

Create three **Consumable** products so they can be re-purchased after being consumed.
The **product IDs must exactly match** `kHintPacks` in
`lib/features/monetization/domain/hint_pack.dart` (a mismatch means the pack won't load).

**Monetize → Products → In-app products → Create product** (×3):

| Product ID (exact) | Suggested name (localize vi-VN) | Hints | Base price (VND) |
|---|---|---|---|
| `hints_20` | 20 lượt gợi ý | 20 | ₫19,000 |
| `hints_60` | 60 lượt gợi ý | 60 | ₫49,000 |
| `hints_150` | 150 lượt gợi ý | 150 | ₫99,000 |

For each: set the exact Product ID (immutable), add a localized name + description, set
the VND base price (review per-country pricing), and **Activate**. The hint **count is
client-side** (`hintsForProduct()` maps id → hints), so only the **ID string** must
align. These are handled by `in_app_purchase` (no server validation).

> **License testers** (test purchases without being charged): Play Console → **Setup →
> License testing** → add tester Google accounts. They must also be on the track's
> testers list to install the build.

---

## 7. Backend deployment & environment

The same backend serves dev and prod via `apps/backend/.env` (validated by
`env.validation.ts`). For **production** set at least:

```sh
# Real board reading + engine
AI_PROVIDER=openai                 # or gemini (drop-in); requires the matching key
OPENAI_API_KEY=<secret>            # gpt-5.4 by default
# GEMINI_API_KEY=<secret>          # if AI_PROVIDER=gemini (GEMINI_MODEL=gemini-3.5-flash)
ENGINE_PROVIDER=pikafish           # server-side engine (or fairy-stockfish — see MONETIZATION.md)
PIKAFISH_BINARY_PATH=<path>        # + PIKAFISH_NNUE_PATH for the net

# Cost guard (hints are device-local; THIS is what bounds spend)
RATE_LIMIT_TTL=60
RATE_LIMIT_LIMIT=30                # per-IP requests / TTL
RATE_LIMIT_DEVICE_WINDOW_SECONDS=86400
RATE_LIMIT_DEVICE_LIMIT=1000       # analyses / device / day

# Install-grant storage (persist this dir; it's the anti-reinstall ledger + Hint Grants)
HINTS_DATA_DIR=./data              # installs.json + grants.json
HINTS_FREE_ON_INSTALL=10
HINTS_OWN_KEY_DIVISOR=3

# Remote feature flags served by GET /api/config (tunable WITHOUT an app release)
FEATURE_BANNER_ADS=true
FEATURE_REWARDED_ADS=false
FEATURE_APP_OPEN_ADS=false
FEATURE_USE_REAL_ADS=true          # ← MUST be true in prod to serve real ad units
FEATURE_UI_LICENSES=true           # ← see GPLv3 note in §8
ONDEVICE_ENABLED=true
ONDEVICE_NET_URL=https://github.com/official-pikafish/Networks/releases/download/master-net/pikafish.nnue
ONDEVICE_NET_BYTES=50760458
ONDEVICE_VISION_MODEL=gpt-5.4
```

Deployment requirements:
- **Reachable host:** the backend must be internet-reachable at the URL the app ships
  with. The default is `http://103.157.205.175:3000` (plain HTTP, no TLS yet).
- **Cleartext exception:** because the backend is HTTP, the release manifest wires
  `res/xml/network_security_config.xml`, which permits cleartext to **that one host
  only** (everything else stays HTTPS-only). So an installed release reaches the default
  backend out of the box. **When you add TLS**, point `BACKEND_URL` at the `https://…`
  origin and delete the cleartext exception from `network_security_config.xml`.
- **Persist `HINTS_DATA_DIR`** on a durable volume — it's the reinstall ledger + the
  Hint Grants allowlist. A corrupt `installs.json` makes the backend refuse to boot
  (fail-closed), so back it up. (It's not security-critical — a wipe just re-grants the
  free hints once per device — but losing it is annoying.)
- **`GET /api/config` is exempt from the throttle** so a NAT full of devices can't 429
  the config fetch; the client falls back to cached/default flags on any outage.

---

## 8. GPLv3 / open-source obligations (the on-device engine)

**This app is distributed under GPLv3** because it bundles the Pikafish Xiangqi engine
(`android/app/src/main/jniLibs/arm64-v8a/libpikafish.so`, GPLv3). This has real release
obligations — don't skip them:

1. **Ship the license notice in-app.** The engine's GPLv3 notice + a written offer of
   source is registered via `LicenseRegistry` (`main.dart`) and surfaced on the OS
   **Open-source licenses** page. That page is reached from **Settings → Privacy →
   Open-source licenses**, which is **gated by `FEATURE_UI_LICENSES`** (default `false`).
   **For the compliant production build, set `FEATURE_UI_LICENSES=true`** (§7) so the
   notice is actually reachable.
2. **Keep `LICENSE-engine.md`** (repo root) — the full notice + the written offer of
   corresponding source (`github.com/official-pikafish/Pikafish`).
3. **The `.so` must stay git-tracked.** `.gitignore` ignores `*.nnue` but the `.so` is
   force-tracked; verify with `git ls-files …/jniLibs/` (must list `libpikafish.so`). A
   clean clone/CI must ship the binary, or both on-device mode AND the GPLv3 posture
   silently break.
4. **The NNUE net is downloaded at runtime** (from `ONDEVICE_NET_URL`, the
   non-commercial master-net) — it is NOT bundled, which keeps the non-commercial net
   out of the distributed app. Don't add it to the AAB.

> If you ever want a non-GPL app, you must remove the engine from the bundle (the
> earlier "server-side engine only" posture). As shipped, the app IS GPLv3 and you must
> honor it.

---

## 9. Build the release AAB

### 9.1 Pre-build checklist
1. `key.properties` present (§2) so the AAB is upload-key signed.
2. Backend reachable at the shipped `BACKEND_URL`, with `FEATURE_USE_REAL_ADS=true` and
   `FEATURE_UI_LICENSES=true` (§7, §8).
3. `versionCode` bumped above any prior upload (`pubspec.yaml`).
4. `JAVA_HOME` → JDK 21 (§0).

### 9.2 Build
```sh
cd apps/mobile
flutter clean
flutter pub get
flutter build appbundle --release
```
- **No `--dart-define`s are required.** `BACKEND_URL` defaults to the live backend, and
  the AI/engine providers default to the REAL ones (`openai` / `pikafish`).
- **Do NOT pass `--dart-define=AI_PROVIDER=mock`** (or `ENGINE_PROVIDER=mock`) — the
  backend honors an explicit `mock`, so that ships a build whose "our key" cloud
  analyses return a FAKE board/move. Mock is only for a deliberate demo build.
- **Never** build with `--dart-define=MOCK_MONETIZATION=true` for release — it fakes the
  wallet/ads/store.
- Output: `build/app/outputs/bundle/release/app-release.aab` — upload **this `.aab`**.

### 9.3 R8 + crash symbolication (already configured)
The release build runs **R8** (`isMinifyEnabled`/`isShrinkResources = true`) with
`android/app/proguard-rules.pro`, and bundles **native debug symbols**
(`ndk { debugSymbolLevel = "SYMBOL_TABLE" }`). The resulting AAB embeds:
- `BUNDLE-METADATA/.../obfuscation/proguard.map` → resolves Play's **"no deobfuscation
  file"** warning (de-obfuscates Kotlin/Java crashes).
- `BUNDLE-METADATA/.../debugsymbols/<abi>/*.so.sym` → resolves the **native debug
  symbols** warning.

Play associates both automatically — nothing to upload manually. *(Optional Dart-side
obfuscation: add `--obfuscate --split-debug-info=build/symbols` and archive
`build/symbols/` per build to de-obfuscate Dart stack traces.)*

> ⚠️ R8 keep rules are load-bearing: WorkManager/Room (pulled in via
> `google_mobile_ads → androidx.startup`) crash on launch under R8 full-mode without
> them. **Any plugin/dependency change must be re-verified with an on-device RELEASE
> launch** — a missing keep crashes ONLY the minified build, never debug (§9.4).

### 9.4 Smoke-test the release on a device (do this every release)
```sh
flutter build apk --release                                   # universal APK for testing
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb logcat -c
adb shell monkey -p com.codertapsu.xiangqi_solver -c android.intent.category.LAUNCHER 1
sleep 8
adb shell pidof com.codertapsu.xiangqi_solver && echo "ALIVE"  # empty = crashed
adb logcat -d | grep -iE "FATAL EXCEPTION|WorkDatabase|AndroidRuntime: .*E"
```
Expect `Displayed …/MainActivity` in logcat, a live PID, and **no** `FATAL` /
`WorkDatabase` lines. Then manually exercise: launch → Solver Mode (grant overlay +
MediaProjection) → analyze a board → buy/restore a test pack → settings/language toggle.

> **Signature mismatch installing over a Play build?** Once a device has a
> **Play-installed** copy (signed by Google's app-signing key), a locally built
> APK (signed by your *upload* key) can't replace it — `adb install` fails with
> `INSTALL_FAILED_UPDATE_INCOMPATIBLE`. Either `adb uninstall com.codertapsu.xiangqi_solver`
> first (wipes that build's data), **or** install a **debug** build — the `debug`
> buildType sets `applicationIdSuffix = ".dev"`, so `com.codertapsu.xiangqi_solver.dev`
> installs **side-by-side** with the Play release (no conflict, no data loss). The
> dynamic launcher-icon switch works under the `.dev` id too (the native code
> resolves the aliases against the namespace, not the applicationId).

---

## 10. Play Console: create app, listing & declarations

### 10.1 Create the app
**Create app** → default language **Vietnamese (vi-VN)**, name **"Quân Sư Cờ Tướng"**
(add an en-US listing titled "Xiangqi Strategist"), App, **Free**. Accept the developer
program + US export declarations. Package `com.codertapsu.xiangqi_solver` is fixed at
first upload.

### 10.2 Store listing (per language)
Title (≤30), short description (≤80), full description (≤4000), 512×512 icon, 1024×500
feature graphic, 2–8 phone screenshots. Provide both **vi-VN** (primary) and **en-US**.

### 10.3 App content / declarations
| Section | What to do |
|---|---|
| **Privacy policy** | Paste `https://codertapsu-web.web.app/xiangqi-solver/privacy`. Required (Advertising ID + screenshot upload). |
| **Ads** | **Yes** — the app contains ads (AdMob). |
| **Content rating** | Run the questionnaire (a chess analyzer rates broadly Everyone/PEGI 3). |
| **Target audience** | General audience (13+). The app does NOT set child-directed treatment. |
| **App access** | Login-free — the app works without an account. |
| **Government apps / Financial / Health** | No. |
| **Data safety** | §10.4. |
| **Advertising ID** | Declare it (the `AD_ID` permission is auto-merged by `google_mobile_ads`). |

### 10.4 Data Safety form
| Data type | Collected / shared | Notes |
|---|---|---|
| **Device or other IDs** | Collected (+ shared for ads) | Stable `x-device-id` (install-grant + per-device rate limit); AdMob Advertising ID. Purpose: App functionality, Fraud prevention, Advertising. |
| **Photos / screenshots** | Collected, transmitted | Screen captures are **uploaded to the backend** for board analysis, then to OpenAI (or directly to OpenAI with the user's own key). State retention honestly — match the backend's actual behavior (process-and-discard vs stored). Purpose: App functionality. |
| **Purchase history** | Collected | Google Play Billing (hint packs). Purpose: App functionality. |
| **No account / name / email** | — | The app has no login. |
| Encrypted in transit | Yes | Release is HTTPS-only except the one scoped cleartext backend host (§7); state when TLS lands. |
| Third-party sharing | AdMob (advertising), OpenAI/your backend (board reading) | Your backend is first-party processing; OpenAI is a processor — disclose it. |

> Be precise about **screenshot retention** and keep the privacy policy and Data Safety
> answers consistent with each other.

### 10.5 Permission justifications (sensitive permissions)
Prepare written justifications and, where prompted, a short screen recording of the flow.
This app declares:

| Permission | Justification |
|---|---|
| `SYSTEM_ALERT_WINDOW` (overlay) | A small, clearly-labeled floating button shows the recommended move over the board; user-initiated and dismissible; core to the solver UX. |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MEDIA_PROJECTION` | Screen capture runs only after the user grants the system MediaProjection consent dialog, to read the board for analysis; a foreground service (type `mediaProjection`) keeps the capture alive with a persistent notification. Never silent/background. |
| `POST_NOTIFICATIONS` | The foreground-service notification on Android 13+. |
| `WAKE_LOCK` | Keeps the capture/analysis pipeline alive during a solve. |
| `com.android.vending.BILLING` | Google Play in-app purchases (hint packs). |
| `INTERNET` | Backend + ads. |

> MediaProjection + overlay apps get extra scrutiny. Emphasize: capture is **explicit,
> user-initiated, scoped to producing a move suggestion, and never silent**.

### 10.6 Target API level
`targetSdk = 35` (Android 15) satisfies Play's current new-app requirement; `compileSdk
= 36`, `minSdk = 26` (overlay needs API 26). Bump `targetSdk` if Play later flags it.

---

## 11. Release tracks

Always promote in order — never push a fresh build straight to Production:

```
Internal testing → Closed (Alpha) → Open (Beta) → Production
```

1. **Internal testing → Create new release** → upload `app-release.aab` → add release
   notes (vi-VN + en-US) → **Save → Review → Start rollout**. No review delay; the right
   place to validate IAP + ads + the full solver flow. Add testers by email; opt in on a
   test device's Google account (license testers + internal testers).
2. After ≥24h clean, **Production → Create release → Add from library** (the same build).
   **Staged rollout**: start 10–20%, watch **Android vitals** (crash/ANR), then ramp.

> You generally must create at least one release and complete Data Safety + content forms
> before the listing/products go fully active. Create the consumables (§6) as soon as the
> app exists.

---

## 12. Pre-launch verification checklist

Run against the **Internal testing** build (real ad units via `FEATURE_USE_REAL_ADS=true`,
real products, the production backend) before promoting.

**Build / identity**
- [ ] AAB is **upload-key** signed (not debug); Play accepts it and shows Play App Signing.
- [ ] `versionCode` higher than any prior upload.
- [ ] R8 release **launches with no `WorkDatabase`/FATAL** on a real device (§9.4).
- [ ] AAB embeds `proguard.map` + native `*.so.sym` (no Play warnings on the new build).
- [ ] Manifest `APPLICATION_ID` is the real AdMob App ID (not `…3940256099942544~…`).

**App name / localization**
- [ ] Vietnamese-locale device shows **"Quân Sư Cờ Tướng"** in the launcher; other
      locales show **"Xiangqi Strategist"**.
- [ ] UI is Vietnamese on a vi device and English elsewhere; **Settings → App language**
      overrides live.

**Monetization**
- [ ] Fresh install seeds the free hints once; **reinstall on the same device does NOT
      re-grant** (install-grant working). A Hint-Grants `grants.json` entry comps a device.
- [ ] A cloud solve spends exactly 1 hint; running out shows the "get more hints" sheet.
- [ ] Each `hints_20 / hints_60 / hints_150` shows the right VND price + localized name;
      a license-test purchase credits the right count; re-buying works (consumable).
- [ ] Rewarded ad (if enabled) credits +1; banner shows real fills with
      `FEATURE_USE_REAL_ADS=true`.

**Engine / GPLv3**
- [ ] On-device mode downloads the net and computes a move; fallback to cloud works.
- [ ] **Settings → Privacy → Open-source licenses** is visible
      (`FEATURE_UI_LICENSES=true`) and shows the Pikafish GPLv3 notice.

**Networking / permissions**
- [ ] Release reaches the backend (cleartext exception works for the HTTP host).
- [ ] MediaProjection consent appears before capture; overlay shows the move; FGS
      notification appears on Android 13+.
- [ ] Permission justifications + (if requested) screen recording uploaded.

**Policy**
- [ ] Privacy policy URL set + reachable; Data Safety completed + consistent (device ID,
      screenshots, purchases, AdMob).
- [ ] Ads = Yes; content rating, target audience, app access done.
- [ ] Target API 35 accepted with no warning.

---

## 13. Post-release monitoring (first ~3 days)

```sh
adb shell dumpsys package com.codertapsu.xiangqi_solver | grep versionName
```
- **Play Console → Android vitals** — crash/ANR spikes (now de-obfuscated thanks to the
  bundled mapping + native symbols).
- **AdMob** — impressions on the new version; zero usually means the App ID or UMP
  consent is misconfigured, or `FEATURE_USE_REAL_ADS` is still `false`.
- **Backend** — OpenAI spend vs the per-device cap; `POST /api/hints/claim` rates;
  watch `HINTS_DATA_DIR` disk.

---

## 14. Common rejections / warnings (and the fix)

| Symptom | Fix |
|---|---|
| "No deobfuscation file" / "native debug symbols" warning | Non-blocking. The **next** AAB resolves both — R8 + `debugSymbolLevel` are on (§9.3). Old uploads keep the warning. |
| "Privacy policy required" | Advertising ID + screenshot upload ⇒ a policy URL is mandatory (§10.3). |
| "Data safety: undeclared data" | Declare Advertising ID (`AD_ID` permission), screenshots (uploaded), purchases (§10.4). |
| "Permission not justified" (overlay / MediaProjection) | Provide the §10.5 justifications + a screen recording; stress user-initiated, non-silent capture. |
| "Test ads in production" | Set `FEATURE_USE_REAL_ADS=true` on the prod backend (no build flag). |
| Launch crash on the release track only | A missing R8 keep — add it to `proguard-rules.pro` and re-run §9.4. |
| Cloud analysis returns a fake board | A `mock` provider shipped — rebuild without `--dart-define=*_PROVIDER=mock` (§9.2). |
| Target API < 35 | Confirm `targetSdk = 35`, rebuild. |

---

## 15. Rollback

1. **Halt rollout** if still <100% (Production → ⋮ → Halt rollout).
2. Otherwise ship a **higher `versionCode`** with the fix (`git revert`, bump `+N`,
   rebuild, upload, roll out).
3. Many issues are **server-side** and need NO app update: ad formats
   (`FEATURE_*_ADS`, `FEATURE_USE_REAL_ADS`), free-hint count (`HINTS_FREE_ON_INSTALL`),
   the licenses entry (`FEATURE_UI_LICENSES`), rate limits, and the AI model — all live
   in `GET /api/config` / backend `.env`. Change those first.
4. Never delete a failing AAB — Play keeps it for audit.

---

## Appendix — v1.0.0 release notes ("What's new")

Paste into the matching **listing language** (vi-VN gets Vietnamese, en-US gets English).
Plain text, ≤ 500 chars each.

**Vietnamese (vi-VN — default listing):**
```
Chào mừng đến với Quân Sư Cờ Tướng! 🎉

Quân sư cờ tướng trong túi của bạn — tìm ngay nước đi tốt nhất cho mọi thế cờ:
• Chụp bàn cờ từ bất kỳ ứng dụng nào và nhận gợi ý tức thì
• Chế độ Quân Sư: nút nổi phân tích bàn cờ ngay trên màn hình
• Công cụ cờ mạnh chỉ ra nước hay nhất kèm giải thích dễ hiểu
• Phân tích trên máy chủ, hoặc ngay trên thiết bị của bạn
• Có lượt gợi ý miễn phí khi cài đặt

Cảm ơn bạn đã dùng thử — chúc bạn thắng thật nhiều ván cờ!
```

**English (en-US):**
```
Welcome to Xiangqi Strategist! 🎉

Your Chinese Chess (Xiangqi) coach in your pocket — find the best move in any position:
• Capture the board from any app and get an instant suggestion
• Solver Mode: a floating button analyzes the board right on your screen
• A strong engine shows the best move with a clear explanation
• Analyze in the cloud or fully on your device
• Free hints to get you started

Thanks for playing — may your next move be the winning one!
```
```
