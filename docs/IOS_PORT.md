# Porting to iOS & publishing to the App Store — findings + plan

Bring **Quân Sư Cờ Tướng / Xiangqi Strategist** (`com.codertapsu.xiangqi_solver`)
to Apple's App Store. This is a **port assessment + plan**, not a step-by-step recipe:
it records what reuses cleanly, what is **impossible on iOS**, the alternatives for each
blocker, and a phased path to submission.

> ✦ **Bottom line:** you can ship a high-quality iOS app, but it must be a *different
> product shape* than Android — a **cloud "analyse a board image" app**, not the live
> **Solver Mode** assistant. The floating overlay over other apps and on-demand screen
> capture have **no iOS equivalent**, and the on-device engine is blocked twice over
> (technical + licence). Everything else ports cleanly.

> **⚠️ Not legal advice.** The licensing (GPLv3) and App Review guideline calls here are
> engineering judgement informed by precedent — confirm the load-bearing ones with
> someone qualified before submitting.

> **Companion docs:** [PUBLISHING.md](PUBLISHING.md) (the Android/Play guide this mirrors),
> [MONETIZATION.md](MONETIZATION.md) (device-local hint economics),
> [ON_DEVICE_ENGINE.md](ON_DEVICE_ENGINE.md) (the GPLv3 engine that stays Android-only),
> [APP_ICON_VARIANTS.md](APP_ICON_VARIANTS.md) (the dynamic name/icon that does **not** port).

---

## 0. Status & verdict

- **Backend (NestJS): 100 % reusable**, zero changes for iOS to function. The one fix it
  wants — TLS — benefits Android too.
- **Flutter Dart layer: ~90 % reusable.** The platform abstraction already degrades
  gracefully off-Android (`NoopNativeSolver`), so the cloud path works on iOS in principle.
- **Native layer: greenfield.** There is **no `ios/` directory** — the project was created
  Android-only (`.metadata` lists only `root` + `android`). Step zero is
  `flutter create --platforms=ios .`.
- **Effort: ~3–4 weeks** of focused work for a cloud-only iOS app (excl. Apple enrolment
  lead time + review cycles). The Solver-Mode replacement itself is only a few days (§4).

---

## 1. Reusability — what ports vs what doesn't

| Area | Android today | iOS | Effort |
|---|---|---|---|
| NestJS backend | HTTP/JSON REST | **Reuse unchanged** (needs TLS — §3.3) | none (app-side) |
| Cloud vision → best move | `analyzeScreenshot(File)` | **Works as-is** | none |
| Riverpod / go_router / Dart logic | — | **Ports 1:1** | none |
| gen_l10n localization | ARB → AppLocalizations | **Works** + Info.plist config | low |
| AdMob | real Android units | Re-platform: iOS app, units, ATT | medium |
| In-app purchases | Play Billing | StoreKit (already wired transitively) | low–medium |
| Device-id anti-abuse | MediaDrm (reinstall-stable) | Keychain UUID (weaker) | low |
| **Solver Mode (overlay + capture)** | core UX | **❌ IMPOSSIBLE** — reframe (§4) | few days |
| **On-device Pikafish engine** | ships in APK | **❌ DOUBLE-BLOCKED** — drop on iOS (§3.2) | — |
| Dynamic launcher **name** | values-vi swap | **❌ no runtime rename** — device-locale only (§5) | low |
| Dynamic launcher **icon** | activity-alias | ⚠️ partial (forced system alert) | optional |

---

## 2. The three blockers (with alternatives)

### 2.1 Solver Mode — overlay over other apps + on-demand capture → no iOS equivalent

Two iOS limits stack here, both OS-level sandbox policy with **no workaround**:

1. **No floating widget over other apps.** iOS isolates each app's window layers — there is
   no `SYSTEM_ALERT_WINDOW` / `TYPE_APPLICATION_OVERLAY` equivalent for third-party apps.
2. **No silent on-demand frame grab of another app.** ReplayKit is *user-initiated,
   always-indicated, continuous* broadcast only — it cannot quietly capture a single frame
   of another app on a button tap. And `userDidTakeScreenshotNotification` only fires while
   **our** app is foregrounded, so it is useless for a game running in another app.

→ **This is the headline finding. The full alternative — a Share-Extension "push" flow — is
§4, because it defines the iOS product.**

### 2.2 On-device Pikafish engine → blocked technically AND by licence

Two independent blockers, either fatal:

1. **Technical:** the engine runs as a **subprocess** (`Process.start()` in
   `uci_engine_client.dart`, exec'ing a bundled ELF located via `nativeLibraryDir`). Apple
   forbids fork/exec of any bundled or downloaded executable (**Guideline 2.5.2**). The
   shipped artifact is also an Android/Linux aarch64 ELF — not an iOS format.
2. **Licence:** the app is GPLv3 *only because* it bundles Pikafish. Linking a GPLv3 binary
   into an App Store app is the well-known FSF/VLC incompatibility (Apple's DRM + standard
   EULA add restrictions GPLv3 forbids).

**Alternative (recommended): iOS is cloud-only, no bundled engine.** This is already the
default — on-device is hard-gated to Android in `engine_net_provider.dart` (off-Android →
`EngineNetUnsupported`) and the default `engineLocation` is `cloud`. Because the iOS binary
never bundles Pikafish, **the GPLv3 obligation never attaches to iOS at all** — the licence
conflict simply disappears. (The NNUE net is downloaded *data*, fine under 2.5.2, but iOS
has no on-device engine to feed it to, so it's moot.)

> If on-device on iOS were ever required: re-architect the engine as an **in-process static
> library / `.xcframework`** driven over FFI — never a subprocess — and switch to a
> permissively-licensed engine (e.g. CC0 Fairy-Stockfish) to avoid the GPL conflict. Large
> effort; not for v1.

### 2.3 Cleartext HTTP backend → blocked by App Transport Security

The backend is `http://103.157.205.175:3000` — a bare IP, no TLS. iOS **ATS blocks cleartext
HTTP by default**, so on iOS the cloud path (the *only* analysis path) and hint-grant calls
would silently fail. An ATS exception for a bare **IP literal** is harder and more
rejection-prone than for a hostname, and a global `NSAllowsArbitraryLoads=true` is the single
thing App Review scrutinises most.

**Alternative (recommended): add TLS, drop cleartext everywhere.** Put the backend behind a
real hostname + valid cert (Caddy / nginx + Let's Encrypt, or front with Cloudflare for free
TLS + a DNS name), then point `BACKEND_URL` at `https://…`. Both that URL and `ONDEVICE_NET_URL`
are already `--dart-define` / remote-config overridable (`app_constants.dart`
`String.fromEnvironment('BACKEND_URL')`; net URL via `/api/config`), so **no Dart changes** —
the iOS release just builds against the https origin. This also lets **Android drop its
cleartext `network_security_config` exception** — a net win for both platforms.

> *Interim stopgap only:* give the IP a hostname (DuckDNS / nip.io) and add a scoped
> `NSExceptionDomains` entry — but TLS is the real fix and you want it before review regardless.

---

## 3. The Solver-Mode replacement — iOS capture flow (the load-bearing design)

### 3.1 The irreducible truth

iOS will **never** let our app read another app's pixels on demand. So the Xiangqi board
image can only enter our pipeline **one way: a screenshot the *user* takes and explicitly
hands to us** — either **pushed** via the share sheet or **pulled** by us from Photos with
permission. The Android model ("our app on top, we grab the game") **inverts** on iOS to
"the game is on top, the user screenshots it, then pushes it into us." Every design decision
reduces to minimising the friction of that one hand-off; the analysis pipeline itself
(`POST /api/analysis/screenshot`) is already platform-agnostic and unchanged.

### 3.2 Recommended flow — Share Extension PUSH (≈2 taps, 1 app switch)

1. User is in the Xiangqi game → **takes a screenshot** (hardware gesture, not a tap).
2. The screenshot thumbnail pops up bottom-left → **long-press it** (long-press jumps
   straight to the share sheet, skipping the Markup editor a normal tap opens).
3. **Tap "Quân Sư Cờ Tướng"** in the share sheet → our app opens with the board already
   loaded and the best move computing; the result renders on the existing `ResultPage`.

This is as close to the Android FAB idea as iOS physically permits, and it needs **zero
permissions** (no Photos prompt to deny) — the least friction *and* the lowest rejection risk.

### 3.3 Why the result can't show *inside* the share sheet (and why that's fine)

iOS caps app extensions at **~120 MB** of memory. Booting a second Flutter engine there
(plus decoding a multi-MB screenshot) is fragile and risks the OS killing it (Flutter's own
docs advise against extension UI under 100 MB; debug builds already exceed 120 MB). The only
alternative — reimplementing the solver, backend contract, hint-wallet, and l10n in native
Swift — forks the product into two languages. The sole UX win would be removing *one app
switch* (not even a tap). **Not worth it.** The extension stays a thin native shim and
deep-links into the real app.

### 3.4 Architecture (the Dart side is basically ready)

The integration is tiny because the cloud path is already platform-neutral. The single target
is **`analyzeScreenshot(File)` at `solver_providers.dart:550`** — the *exact* method the
existing gallery picker already feeds (`home_page.dart:159-175`).

1. **Native Swift Share Extension** — a thin `ShareViewController` (no compose UI;
   `isContentValid → true`). Info.plist declares
   `NSExtensionActivationRule → NSExtensionActivationSupportsImageWithMaxCount = 1` so a
   shared screenshot (`public.image`) activates it. Its only job: write the image into the
   App Group container, then `openURL` the host app.
2. **App Group** `group.com.codertapsu.xiangqi_solver` — App Groups capability on **both** the
   Runner and the extension target; same `CUSTOM_GROUP_ID` build setting on both.
3. **Custom URL scheme** — `ShareMedia-com.codertapsu.xiangqi_solver` registered in the Runner
   Info.plist so the extension can relaunch the app.
4. **`receive_sharing_intent`** plugin in the Runner — `getInitialMedia()` (cold start) +
   `getMediaStream()` (warm).
5. **Dart adapter (the whole integration):** on each delivered path, verify the file exists
   and is under `AppConstants.maxUploadBytes`, then emit it onto the **same**
   `SolverModeNotifier.analyzeRequests` broadcast stream Android uses (`~solver_providers.dart:293`).
   The existing `HomePage` subscription (`home_page.dart:47-50` → `_handleAnalyzeRequest`,
   `121-125`) then runs `analyzeScreenshot(File(path))` → `_openResult()`. This **inherits the
   single-fire contract and the single-`/result`-on-stack guard for free.**

`nativeSolverProvider` already returns `NoopNativeSolver` off-Android, so the iOS source is
purely additive. The overlay `updateOverlay` calls in `_apply` are no-ops when
`native.isSupported` is false, so only the in-app `ResultPage` matters on iOS. **No backend,
no `AnalysisNotifier` changes.**

### 3.5 Secondary flow — "Analyse latest screenshot" FAB (Photos PULL)

Inside the app, a FAB that auto-loads the **newest screenshot** (`photo_manager`, Screenshots
album) → one tap to solve. Catch: auto-loading needs **full Photos access**
(`NSPhotoLibraryUsageDescription`), which users can deny and review eyes for least-privilege
(Guideline 5.1.1). Keep PUSH primary; request access lazily on FAB tap; fall back to **PHPicker**
(no prompt) when access is Limited/denied. Never block core functionality on Photos access.

### 3.6 App Review risk — LOW, with precedent

The dominant risk is **not** cheating/fairness — it's **Guideline 4.3 (saturated category /
thin engine wrapper).** Apple's "cheating" language targets developers gaming the App Store,
not apps that assist players, and a user-supplied static image triggers none of the 2.5.x
"interference" clauses. Strong live precedent: **Chessvision.ai** ("share screenshots directly
from other apps"), **"Chess Cheat – AI Solver"** (imports Chess.com screenshots, uses "cheat"
in its name, 4+), **Chess Move – Stockfish Engine** (identical cloud-engine architecture) — all
approved. De-risk by:

- **User-supplied-image model only** — no ReplayKit, no overlay, no programmatic capture.
- **Frame as analysis / study / training** (Education or Productivity), not "beat your live
  opponent." (Soft risk — "Chess Cheat" passed with overt framing — but conservative for a
  first submission.)
- **Genuine native value** beyond an engine wrapper: board editor, position correction, move
  history/explanations, Vietnamese localization. (Mitigates 4.3.)
- **No competitor brand names/UI** in the app name, icon, or screenshots (5.2.1 / new 4.1c).
  The board position itself is game state (facts), not copyrightable.

---

## 4. Feature-by-feature iOS notes

### 4.1 Dependencies — every pub package supports iOS
No package in `pubspec.yaml` is Android-only; the Android-specific behaviour lives in *our*
Kotlin, not the deps. Per package:

- **Pure-Dart, zero config:** go_router, dio, flutter_riverpod, equatable, intl,
  cupertino_icons, flutter_localizations.
- **Foundation-backed, work as-is:** shared_preferences (NSUserDefaults), path_provider,
  flutter_secure_storage (Keychain), url_launcher.
- **`image_picker`** ✅ — but **requires `NSPhotoLibraryUsageDescription`** or auto-rejection.
- **`permission_handler`** is declared but **not imported anywhere**. On iOS it injects all
  permission usage-strings (rejection risk). **Recommendation: remove it from pubspec** (dead
  weight + risk); if kept, prune via Podfile `post_install` macros.
- Android-only transitives (flutter_plugin_android_lifecycle, jni) are simply absent from the
  iOS plugin set — harmless.

### 4.2 Monetization

**AdMob** (`ad_helper.dart`): already has iOS branches, but iOS unit ids are **Google sample
units** and there is **no iOS AdMob app**. Need: register an iOS app under publisher
`pub-6124263664453069`, mint iOS banner/rewarded/app-open units, replace `_RealUnits` iOS ids,
add `GADApplicationIdentifier` + `SKAdNetworkItems` to Info.plist. The remote `useRealAds` flag
already gates test-vs-real per platform.

**App Tracking Transparency (ATT) is absent** and is **mandatory** since iOS 14.5 before AdMob
can use IDFA / SKAdNetwork. Either add the `app_tracking_transparency` package and call
`requestTrackingAuthorization()` in `mobile_ads_provider._init()` *before* `MobileAds.initialize`
(+ `NSUserTrackingUsageDescription`), **or** sidestep ATT entirely with non-personalized /
contextual ads only (no IDFA, no prompt — simpler, lower revenue).

**In-app purchases** (`billing_service.dart`): **zero Dart changes** — `in_app_purchase_storekit`
is already in the lock file; the abstract API targets StoreKit automatically. Need: recreate the
3 consumables (`hints_20k/60k/99k`) in **App Store Connect** with identical product ids; add a
StoreKit config file for local testing. No server receipt validation needed (wallet is
device-local). Apple mandates StoreKit for digital goods (**3.1.1**) — no external steering.

**Device-id install-grant** (`persistent_device_id`): has a Keychain-UUID iOS impl that survives
reinstall, but is **weaker** than Android MediaDrm (a wipe clears it; backup/restore differs).
The backend's per-IP + per-device `DeviceRateLimitGuard` backstops it, so it's acceptable. For
stricter binding, fork to set `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.

### 4.3 Networking
Backend is platform-agnostic HTTP/JSON+multipart — reuse unchanged. The only app-side issue is
ATS/cleartext (§2.3). No other hardcoded cleartext URLs; third-party calls are HTTPS.

### 4.4 Localization, app name, app icon

- **gen_l10n: ports unchanged** (pure Dart). One required addition: declare
  `CFBundleLocalizations = [en, vi]` in Info.plist (or `en.lproj`/`vi.lproj`), or a Vietnamese
  device reports `en` to Flutter and `localeResolutionCallback` wrongly defaults to English.
- **Per-device-locale launcher name:** set base `CFBundleDisplayName = "Xiangqi Strategist"`
  + `ios/Runner/vi.lproj/InfoPlist.strings` with `CFBundleDisplayName = "Quân Sư Cờ Tướng"`.
  Matches Android's device-locale naming.
- **❌ HARD LIMIT — no runtime app rename.** The in-app App-language setting that swaps the
  *launcher name* on Android (the activity-alias trick) **cannot** change the iOS home-screen
  name at runtime. On iOS the name is device-locale-driven only. `setAppIcon` is Android-gated
  and already no-ops on iOS.
- **Dynamic icon:** *partially* possible via `setAlternateIconName` — but it **always shows a
  system alert**, requires **pre-bundled flat PNG icon sets** (not adaptive layers), and can't
  rename the app. **Recommendation: drop the runtime icon toggle on iOS** — one device-locale
  primary icon (zero alerts). The backend `appIconVariant` override still works to *force* a
  bundled variant, but only among bundled icons and only with the alert.

---

## 5. Phased plan

**Phase 0 — Prerequisites (parallel, has lead time)**
- [ ] Enrol in **Apple Developer Program** ($99/yr) — start early, can take days.
- [ ] Stand up **TLS** on the backend (Cloudflare or Caddy/LE) → `https://` hostname.
- [ ] Create **App Store Connect** app record + bundle id (`com.codertapsu.xiangqi_solver`).

**Phase 1 — Scaffold & build**
- [ ] `flutter create --platforms=ios .` in `apps/mobile` (won't touch `lib/` or `android/`);
      commit the new `ios/` tree.
- [ ] `cd ios && pod install`. Set `IPHONEOS_DEPLOYMENT_TARGET ≥ 13` (google_mobile_ads 8.x +
      in_app_purchase_storekit 0.4.x need a modern minimum).
- [ ] Remove unused `permission_handler` from pubspec.
- [ ] Verify the cloud flow works against the https backend.

**Phase 2 — iOS-gate the unsupported features**
- [ ] Hide the Solver Mode card in `home_page.dart` `_buildSolverModeCard` when
      `!nativeSolver.isSupported` (mirror `settings_page.dart`'s `SizedBox.shrink()`).
- [ ] Confirm on-device toggles stay hidden (already gated).
- [ ] Build the **Share Extension + App Group + URL scheme + `receive_sharing_intent` adapter**
      feeding `analyzeRequests` (§3.4). Add the optional Photos PULL FAB (§3.5).

**Phase 3 — Native config & Info.plist**
- [ ] `NSPhotoLibraryUsageDescription` (VI + EN), `CFBundleDisplayName` + `vi.lproj`,
      `CFBundleLocalizations`.
- [ ] `GADApplicationIdentifier`, `SKAdNetworkItems`, `NSUserTrackingUsageDescription`
      (if doing ATT).

**Phase 4 — Monetization provisioning**
- [ ] iOS AdMob app + real unit ids → replace `_RealUnits` iOS ids; wire ATT (or
      non-personalized).
- [ ] Recreate 3 consumables in App Store Connect (identical product ids); StoreKit config file.

**Phase 5 — Submit**
- [ ] TestFlight internal build; smoke-test cloud solve + IAP (sandbox) + ads (test units) +
      share-in (cold + warm delivery, dedupe).
- [ ] App Privacy questionnaire, screenshots, VI/EN descriptions; submit for review.

---

## 6. Submission checklist

- [ ] Apple Developer Program active; bundle id registered
- [ ] Backend on **HTTPS** (no ATS exception needed) — or scoped `NSExceptionDomains` if interim
- [ ] `ios/` scaffolded, deployment target ≥ 13, `pod install` clean
- [ ] Solver Mode card + on-device toggles **hidden** on iOS
- [ ] Share Extension (App Group + URL scheme) delivering to `analyzeRequests`; PULL FAB optional
- [ ] **Double-fire dedupe** verified (cold `getInitialMedia` + warm `getMediaStream`)
- [ ] `NSPhotoLibraryUsageDescription` present (localized)
- [ ] `CFBundleDisplayName` + `vi.lproj` + `CFBundleLocalizations`
- [ ] AdMob: iOS app, real units, `GADApplicationIdentifier`, `SKAdNetworkItems`
- [ ] ATT prompt + `NSUserTrackingUsageDescription` **or** documented non-personalized ads
- [ ] 3 consumable IAPs created in App Store Connect (matching ids)
- [ ] **No Pikafish binary in the iOS target** (avoids 2.5.2 + GPLv3)
- [ ] App Privacy "nutrition label" completed (data collection, IDFA, purchases)
- [ ] `permission_handler` removed (or macros pruned)
- [ ] Screenshots + VI/EN descriptions; framing = "analysis/training"; no competitor brand/UI

---

## 7. Must-verify-before-building (from the adversarial self-check)

These are plugin/OS-dependent claims to confirm on a real device, not assume:

1. **Double-delivery is the #1 correctness risk.** `receive_sharing_intent` can deliver the same
   image via *both* cold-start and warm-stream → two `analyzeScreenshot` calls. Our pipeline has
   a **hard single-fire contract** (the Android overlay code warns a second capture corrupts the
   upload — "Request aborted" — and double-charges a hint). **Dedupe by file path; test
   empirically.**
2. The "long-press skips Markup, ~2 taps" UX depends on current iOS screenshot-thumbnail
   behaviour — re-verify on the target iOS version before promising it in copy.
3. Pin the exact `receive_sharing_intent` version + API (`getInitialMedia` vs
   `getInitialMediaStream`, `SharedMediaFile` shape) against the pubspec-locked version.
4. Confirm a shared screenshot round-trips (PNG/HEIC) to a `File` under
   `AppConstants.maxUploadBytes`.
5. Test App Group + URL-scheme delivery end-to-end on hardware (extension writes, host receives).
6. The ~120 MB extension cap varies by device class — but the conclusion (don't host Flutter in
   the extension) holds regardless.

---

## 8. What is genuinely *lost* on iOS

Only one capability: the **live overlay-assist** (a floating FAB over another app + on-demand
capture). That is an **OS-level impossibility**, not something to engineer around. Everything
else is provisioning and config, not redesign. Ship iOS as a **cloud-only "Xiangqi analysis &
training" app**: reuse the backend (add TLS) and ~90 % of the Dart, drop Solver Mode and the
on-device engine (which also dissolves the GPLv3 problem), and replace live capture with the
Share Extension / Photos picker.

---

## 9. Implementation status — what is already in this repo

The iOS scaffold + the entire share-in pipeline are **implemented and build-verified**
(`flutter build ios --no-codesign` → `Runner.app` with `PlugIns/ShareExtension.appex`; all
Flutter tests green; `flutter analyze` clean). Toolchain used: Flutter 3.44.1, Xcode 26.5,
CocoaPods 1.16.2. iOS bundle id: **`com.codertapsu.xiangqiSolver`** (Apple bundle ids disallow
the `_` in the Android `applicationId`, so Flutter camel-cases it).

**Done (in-repo, verified to build):**
- `ios/` scaffolded (`flutter create --platforms=ios`), `IPHONEOS_DEPLOYMENT_TARGET = 13.0`,
  `pod install` clean (13 pods).
- Removed unused `permission_handler`; added `receive_sharing_intent` (1.8.1) +
  `app_tracking_transparency` (2.0.7) to `pubspec.yaml`.
- **Share-in flow:**
  - Dart adapter [`share_intake_provider.dart`](../apps/mobile/lib/features/solver/presentation/providers/share_intake_provider.dart)
    — iOS-only; dedupes cold+warm re-delivery; feeds paths to the home shell, which calls the
    same `analyzeScreenshot(File)` and navigates to `/result`. Inert (never emits) off iOS.
  - Native **Share Extension** target [`ios/ShareExtension/`](../apps/mobile/ios/ShareExtension)
    — a **self-contained** `SLComposeServiceViewController` (NO Flutter / NO plugin import, so it
    stays a true thin shim under the ~120 MB cap). It writes the image into the App Group and
    deep-links back via `ShareMedia-<bundle id>:share`, matching the exact payload
    `receive_sharing_intent` reads (UserDefaults suite `group.com.codertapsu.xiangqiSolver`, key
    `"ShareKey"`, JSON `[{path,mimeType,type}]`).
  - App Group entitlement on **both** targets; URL scheme registered in `Runner/Info.plist`;
    target wiring is reproducible via [`ios/tool/add_share_extension.rb`](../apps/mobile/ios/tool/add_share_extension.rb)
    (idempotent; uses the `xcodeproj` gem — re-run after any `flutter create` regeneration).
- **Solver Mode card hidden on iOS** ([`home_page.dart`](../apps/mobile/lib/features/solver/presentation/pages/home_page.dart));
  an iOS-only "Analyze a board photo" hint card explains the flow (localized `homeShareInTitle/Desc`).
- **Info.plist + l10n:** `CFBundleDisplayName`, `CFBundleLocalizations=[en,vi]`, `en.lproj`/`vi.lproj`
  `InfoPlist.strings` (Vietnamese name "Quân Sư Cờ Tướng"), `NSPhotoLibraryUsageDescription`,
  `NSUserTrackingUsageDescription` — all localized.
- **Monetization wiring:** ATT requested before `MobileAds.initialize`
  ([`mobile_ads_provider.dart`](../apps/mobile/lib/features/monetization/presentation/mobile_ads_provider.dart));
  `GADApplicationIdentifier` (placeholder = Google iOS **test** app id) + `SKAdNetworkItems`
  (Google set) in Info.plist; `ad_helper.dart` iOS units already branch (still on iOS test units).
  IAP needs no Dart change — `in_app_purchase_storekit` targets StoreKit automatically.
- **Android regression fix:** adding `receive_sharing_intent` (iOS-only need) broke the **Android**
  build — its old module compiles Java at target 11 but Kotlin at the JDK-21 default, which modern
  Kotlin rejects as "Inconsistent JVM-target". Fixed with `kotlin.jvm.target.validation.mode=warning`
  in [`android/gradle.properties`](../apps/mobile/android/gradle.properties) (D8/R8 dexes mixed
  class-file versions fine).

**Verified this session (simulators):**
- iOS (iPhone 15, iOS 18.6): `flutter build ios` (device **and** simulator) ✓; app installs +
  launches ✓; App Group `group.com.codertapsu.xiangqiSolver` resolves to a real shared container ✓;
  Vietnamese name/UI ✓; `ShareExtension.appex` embedded ✓; Solver Mode card absent.
- Android (emulator, API 37): builds green ✓; installs + launches (`…xiangqi_solver.dev`) ✓; Solver
  Mode card present + test banner ad loads ✓.
- `flutter analyze` clean; **83** tests pass, incl. 2 new platform-gating tests
  (iOS hides Solver Mode + shows the share-in card; Android the reverse).

**Design changes vs the original §3 plan (and why):**
- The Share Extension is **self-contained native**, not `import receive_sharing_intent`. Importing
  the plugin drags `Flutter.framework` into the extension (build error + the memory bloat we wanted
  to avoid). The thin shim replicates only the App-Group-write + redirect contract.
- The in-app PULL entry **reuses the existing `image_picker` pick-a-photo card** (PHPicker, no
  permission prompt) rather than adding `photo_manager` auto-latest — which would need **full**
  Photos access (a Guideline 5.1.1 review-risk flagged in §3.5). Auto-latest stays a documented
  optional enhancement.

**Remaining — external / console / device (cannot be done from the repo):**
1. **Apple Developer Program** enrollment; create the App ID with the **App Groups** capability
   (`group.com.codertapsu.xiangqiSolver`) and a provisioning profile (the `--no-codesign` build
   skips this; a real signed build needs it).
2. **Backend TLS** (§2.3) → point `BACKEND_URL` at `https://…` via `--dart-define` (no code change).
3. **AdMob:** create the iOS app → replace the placeholder `GADApplicationIdentifier` in
   `Runner/Info.plist` and the iOS unit ids in `ad_helper.dart` `_RealUnits`; paste Google's full
   SKAdNetwork list.
4. **App Store Connect:** create the 3 consumables **`hints_20` / `hints_60` / `hints_150`**
   (exact ids from `hint_pack.dart`); App Privacy questionnaire; screenshots; VI/EN descriptions.
5. **Verify on a real device** (cannot test here): the §7 list — especially (a) cold+warm
   **double-fire dedupe**, and (b) that the `ShareMedia-…:share` URL is delivered to the plugin
   under Flutter 3.44's **scene-based** lifecycle (`SceneDelegate`), since the plugin historically
   hooked `application(_:open:)`. If the share opens the app but no analysis fires, that URL
   forwarding is the thing to check first.
6. On each version bump, keep the ShareExtension `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`
   (set in `add_share_extension.rb`) in sync with the app version.
7. **App icon + name — FINAL DECISION: always the Vietnamese brand.** iOS uses the single
   **Vietnamese "Quân Sư" icon** (`ios/Runner/Assets.xcassets/AppIcon.appiconset`, supplied by the
   owner) with **no** runtime alternate-icon switching. The launcher **name is fixed to
   "Quân Sư Cờ Tướng" for every system language** — base `CFBundleDisplayName` plus both
   `en.lproj` and `vi.lproj` `InfoPlist.strings` all set the Vietnamese value (only the
   *permission* usage strings stay localized). Verified on the **English-language** simulator: the
   home screen shows "Quân Sư Cờ Tướng" with the brand icon. (This supersedes the earlier
   device-locale-name approach in §4.4.)
