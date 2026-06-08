# Dynamic launcher icon + name (per-language)

The app shows a different **launcher icon and name** depending on the in-app
**App-language** setting (Settings → Language → App language), not the device
language. Vietnamese → **Quân Sư Cờ Tướng** (red icon); everything else →
**Xiangqi Strategist** (English icon).

> **Why not just use the device locale?** Android resolves the launcher
> label/icon from the APK at install time by *device* locale — it can't read an
> in-app setting. So we use **activity-aliases** (one launcher entry per variant)
> and enable the matching one at runtime.

---

## How it works (the moving parts)

| Layer | What it does | File(s) |
|---|---|---|
| **Manifest** | `MainActivity` is `exported=false`, NOT a launcher. One `<activity-alias>` per variant (each a launcher entry with a FIXED label + its own icon). Exactly one is `android:enabled` at a time; VI is the default. | `android/app/src/main/AndroidManifest.xml` |
| **Strings** | Fixed, **locale-independent** launcher names (`app_name_vi`, `app_name_en`, …). NOT overridden per-locale (no `values-vi` copy). | `res/values/strings.xml` |
| **Icons** | One **adaptive icon** per variant (`mipmap-anydpi-v26/ic_launcher_<v>.xml`) = a foreground + a background colour. `minSdk=26`, so ONLY the adaptive icon is ever shown. | `res/mipmap-anydpi-v26/`, `res/mipmap-*/`, `res/values/ic_launcher_background_*.xml` |
| **Native switch** | `setAppIcon(variant)` enables the matching alias + disables the others via `PackageManager.setComponentEnabledSetting(..., DONT_KILL_APP)`. Idempotent. | `MainActivity.kt`, `Constants.kt` |
| **Flutter trigger** | `appIconVariantProvider` resolves the variant (backend override → else in-app language). The app root applies it **at startup and on app-background**, never live. | `core/platform/app_icon_provider.dart`, `app/app.dart`, `core/platform/*native_solver*` |
| **Backend override** | `APP_ICON_VARIANT` (`auto`\|`vi`\|`en`) → `features.appIcon.variant` → `RemoteConfig.appIconVariant`. Picks among the **bundled** variants. | `apps/backend/.env`, `config/*`, mobile `RemoteConfig` |

### When does the icon actually switch?
- The **in-app UI** flips language **instantly**.
- The **launcher icon + name** are reconciled **at next launch** and **when the
  app goes to the background** (`AppLifecycleState.paused`) — **never while the
  user is mid-interaction**. So the toggle never flashes/relocates the icon (or
  risks a launcher restart) during use; the icon is correct the next time the
  user looks at the home screen.
- The switch is **idempotent** (Dart de-dup + native check): an unchanged variant
  never crosses the channel or touches the launcher.

### Caveats (inherent to the technique)
- On mainstream launchers (Pixel, Samsung One UI) the icon updates **in place**.
  A few aggressive OEM launchers (MIUI/ColorOS/FuntouchOS — common in Vietnam)
  may briefly **relocate** the icon on a component change. This is unavoidable
  with activity-aliases, regardless of *when* we toggle.
- Moving LAUNCHER off `MainActivity` is a one-time migration: an existing
  **pinned home-screen shortcut** to `.MainActivity` may break on update (the
  app-drawer entry is fine).

---

## Naming convention

- **Vietnamese = the base / unsuffixed set** (kept as-is): `ic_launcher.png`,
  `ic_launcher_round.png`, `ic_launcher_foreground.png`, `ic_launcher_background`.
  The VI alias (`ic_launcher_vi.xml`) references those base names.
- **Every other variant = `<v>`-suffixed**, e.g. for `en`:
  - `ic_launcher_en_foreground.png` — the adaptive **foreground** (the one that matters).
  - `ic_launcher_en.png`, `ic_launcher_en_round.png` — legacy full icons, **API < 26 only** (unused at `minSdk=26`; safe to include or omit).
  - `ic_launcher_background_en` — the background colour.
  - `ic_launcher_en.xml` — the adaptive icon.

> Only the **adaptive foreground + background colour** are shown on real devices
> (minSdk 26). The full `ic_launcher_<v>.png` / `_round.png` are never displayed.

### Adaptive foreground art rules
The foreground is a 108dp layer; only the central ~72dp "safe zone" is guaranteed
visible (launchers mask the rest into circle/squircle/etc.). Sizes per density:
mdpi **108px**, hdpi **162px**, xhdpi **216px**, xxhdpi **324px**, xxxhdpi **432px**.
Keep the logo inside the safe zone with transparent padding. If the foreground is
full-bleed (background baked in, like ours), set the background **colour** to the
art's edge colour so masked corners blend in.

---

## ➕ Add a new variant (worked example: `zh`)

1. **Artwork** — add to `android/app/src/main/res/`:
   - `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher_zh_foreground.png` (all 5).
   - *(optional, API <26 only)* `ic_launcher_zh.png` / `ic_launcher_zh_round.png`.

2. **Background colour** — `res/values/ic_launcher_background_zh.xml`:
   ```xml
   <resources><color name="ic_launcher_background_zh">#RRGGBB</color></resources>
   ```

3. **Adaptive icon** — `res/mipmap-anydpi-v26/ic_launcher_zh.xml`:
   ```xml
   <adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
     <background android:drawable="@color/ic_launcher_background_zh"/>
     <foreground android:drawable="@mipmap/ic_launcher_zh_foreground"/>
   </adaptive-icon>
   ```

4. **Launcher name** — `res/values/strings.xml` (locale-independent):
   ```xml
   <string name="app_name_zh">象棋军师</string>
   ```

5. **Manifest alias** — `AndroidManifest.xml`, beside the others (leave `enabled`
   off; the app enables it at runtime):
   ```xml
   <activity-alias
       android:name=".LauncherZh"
       android:enabled="false"
       android:exported="true"
       android:targetActivity=".MainActivity"
       android:label="@string/app_name_zh"
       android:icon="@mipmap/ic_launcher_zh"
       android:roundIcon="@mipmap/ic_launcher_zh"
       android:theme="@style/LaunchTheme">
       <intent-filter>
           <action android:name="android.intent.action.MAIN"/>
           <category android:name="android.intent.category.LAUNCHER"/>
       </intent-filter>
   </activity-alias>
   ```

6. **Native** — `Constants.kt`: add `const val VARIANT_ZH = "zh"` and
   `const val ALIAS_LAUNCHER_ZH = "LauncherZh"`. `MainActivity.kt`: add the
   `Constants.VARIANT_ZH -> Constants.ALIAS_LAUNCHER_ZH` branch in `setAppIcon`,
   and include `ALIAS_LAUNCHER_ZH` in the `listOf(...)` used by `setAppIcon` and
   `isAliasActive`.

7. **Flutter** — `core/platform/app_icon_provider.dart`: allow `'zh'` as a valid
   override/resolved variant. If you also ship a Chinese **UI**, add `zh` to
   `kSupportedLanguageCodes` (`core/l10n/locale_providers.dart`) and an
   `app_zh.arb`; otherwise the icon can be `zh` while the UI stays vi/en.

8. **Backend (optional)** — to let the server force `zh`, widen the enum in
   `apps/backend/src/config/env.validation.ts` (`APP_ICON_VARIANT`),
   `configuration.ts`, and the mobile `RemoteConfig` parsing.

9. **Verify** — `flutter build apk --release`, then confirm packaging:
   ```sh
   AAPT=$ANDROID_HOME/build-tools/<ver>/aapt2
   "$AAPT" dump resources build/app/outputs/flutter-apk/app-release.apk \
     | grep -i ic_launcher_zh
   ```
   You should see `mipmap/ic_launcher_zh`, `mipmap/ic_launcher_zh_foreground`,
   and `color/ic_launcher_background_zh`.

---

## Replacing placeholder artwork

The variants currently ship final art (VI "Quân Sư", EN "Strategist"). To change
a variant's art, just replace its `ic_launcher_<v>_foreground.png` in the 5
density buckets and (if needed) its `ic_launcher_background_<v>` colour — no code
changes. The simplest way to generate correct sizes is Android Studio's
**Image Asset Studio** (New → Image Asset → Launcher Icons (Adaptive)), then
rename its output to the `_<v>` convention.

> Note: the **Play Store** listing icon is a single 512×512 image uploaded in the
> Play Console — it is **not** per-language and is unrelated to these on-device
> variants.
