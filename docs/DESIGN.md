# Design system — "Sơn Mài" (v1.1)

The UI design for **Quân Sư Cờ Tướng / Xiangqi Strategist**: what was wrong with the
1.0 interface, the concept that replaces it, the tokens it is built from, and how each
screen applies them. Code lives in `apps/mobile/lib/app/theme/` (tokens and themes) and
`apps/mobile/lib/core/widgets/` (shared components).

---

## 1. What the 1.0 UI got wrong

Audited on an Android 16 emulator against the 1.0.0+6 release build.

| Area | Problem |
|---|---|
| Colour | A raw `ColorScheme.fromSeed(red)` produced muddy pink surfaces that share nothing with the red-and-gold app icon. |
| Home | Five cards of equal weight and no primary action. Solver Mode had three controls for one on/off state (a switch *and* Start *and* Stop). |
| Home | The privacy notice (six lines) permanently took the best space on every launch. |
| Home | The real "analyze a screenshot" feature was labelled *Try it (test mode)*. |
| Home | The banner ad sat at the top of the scroll view with a large dead gap under it. |
| Solver Mode | With no overlay permission, Start sent the user to system settings and stopped; they had to come back and press Start a second time. |
| Result | **The board was never drawn.** The answer — a move on a board — appeared only as text plus developer chips (`UCI: h2e2`, `Từ: (7,2)`). |
| Result | A provider "pipeline" panel (`mock`, engine names) and a multi-screen raw JSON dump of every piece. |
| Result | Loading was a bare spinner, even though the board is recognized seconds before the move. Errors were text with no way to retry. |
| History | Rows showed analysis IDs, UCI and provider names; a past result could not be reopened. |
| Settings | Everyday choices (your side, language) and expert ones (API key, engine tuning) in one flat stack; no theme choice; no app version. |
| In-game overlay | Stock Material colours (Google grey panel, blue crop button, lime-green result text). |
| Store | The feature graphic used an unrelated teal-to-purple gradient, and its tagline was cut off mid-word. |

---

## 2. Concept

**Sơn mài** is Vietnamese lacquer painting: cinnabar red, black lacquer and gold leaf on
a polished surface. It is exactly the palette of the app icon — a cinnabar field, a gold
coin bearing 帥, gold auspicious clouds — so the UI grows out of the brand instead of
fighting it.

- **Light theme — rice paper:** warm paper surfaces, cinnabar ink for actions and red
  pieces, bronze-gold accents.
- **Dark theme — black lacquer:** deep warm-black surfaces with **gold leaf** as the
  primary accent and cinnabar for the red side.

### Principles

1. **Board first.** A move is shown on a board, as an arrow, oriented to the side the
   user plays. Text supports the picture.
2. **One primary action per screen.** Home: start Solver Mode (Android) or analyze a
   screenshot. Result: understand the move.
3. **Plain language.** UCI, FEN, provider names and raw JSON move behind *Technical
   details*; nothing is removed.
4. **Calm and premium.** Generous spacing, one accent at a time, motion that explains.
5. **Accessible.** WCAG AA contrast for text, 48 dp touch targets, layouts that survive
   200 % text, and a spoken description of the board's best move.

---

## 3. Tokens

### Colour

| Role | Light (rice paper) | Dark (black lacquer) |
|---|---|---|
| `primary` / `onPrimary` | Cinnabar `#B3261E` / white | Gold leaf `#E9BE62` / `#3A2900` |
| `primaryContainer` | `#FFDAD5` | `#563F00` |
| `secondary` | Bronze `#7C5A0E` | Cinnabar light `#FFB4A9` |
| `secondaryContainer` | Pale gold `#F8E2B0` | `#7A1D16` |
| `tertiary` (positive, "jade") | `#2F6B53` | `#96D4B6` |
| `surface` | `#FBF7F1` | `#15100D` |
| `surfaceContainerLow … Highest` | `#F6EFE6` → `#E6D9CA` | `#1E1714` → `#39302A` |
| `onSurface` / `onSurfaceVariant` | `#221A15` / `#574840` | `#EFE4DA` / `#D4C3B6` |
| `outlineVariant` | `#DDCDBF` | `#4D4038` |
| `error` | `#BA1A1A` | `#FFB4AB` |

Brand extras (`AppPalette` theme extension, `AppPalette.of(context)`): `gold` (fills,
icons), `goldText` (gold that is readable as text on paper), `cinnabar`, `ink`, `jade`,
the hero gradient (icon red → orange in light, lacquer → cinnabar glow in dark) with its
`onHero` colours, and the board colours below.

### Board

| Token | Light | Dark |
|---|---|---|
| Board face | warm wood gradient `#F3DCA8` → `#E7C488` | dimmed wood `#CBA66C` → `#B88F55` |
| Grid lines | `#5E3B1C` | `#3E2610` |
| River text 楚河 漢界 | `#7A5230` | `#4C2F15` |
| Red piece | cream face, cinnabar ring and glyph `#B3261E` | same |
| Black piece | cream face, ink ring and glyph `#231C18` | same |
| Best-move arrow | gold `#D99A1E` with a dark keyline | gold `#F2C14E` |
| Candidate arrows | jade, 60 % opacity | jade light |

### Typography

- **Be Vietnam Pro** (SIL OFL) for all UI text — designed for Vietnamese diacritics.
  Weights 400 / 500 / 600 / 700, bundled.
- **LXGW WenKai TC Bold** (SIL OFL), subset to the 18 glyphs the board needs
  (帥仕相傌俥炮兵 將士象馬車砲卒 楚河漢界) — 11 KB — so pieces have a brush-written look
  that matches the icon's 帥 on every device.
- Material 3 type scale; headings and titles bold with tightened letter spacing; the
  move headline is `headlineMedium` (Be Vietnam Pro Bold).

### Shape, space, motion

- Radii: cards 20, sheets 28 (top), buttons and fields 14, chips 10, pills fully round.
- Spacing on a 4 dp grid; page gutters 20; section gaps 24.
- Cards are flat: tonal fill plus a 1 px `outlineVariant` hairline in light mode.
- Motion: 200 ms (state), 350 ms (arrow draw-in, result reveal), standard easing.
  The best-move arrow draws from origin to target when a result appears.

---

## 4. Components

| Component | Where | Notes |
|---|---|---|
| `XiangqiBoard`, `PieceToken` | Result, History, Home, sheets | CustomPainter: grid, palaces, river text, point markers, file numbers, pieces, highlighted from/to points, animated arrow, faint candidate arrows. Flips for Black. Exposes a semantics label. `PieceToken` paints one piece disc. |
| Move headline | Result | Side-to-move token, Best / Option N badge, the localized move ("Pháo 2 bình 5"), WXF code and depth. |
| `EvalMeter` | Result | Red/Black bar plus plain words ("Red is slightly better", "Black mates in 3") from the engine score, for the side to move. `EngineScore` parses the score. |
| `SolverHero`, `ShareHero` | Home | Gradient card: title over a status pill, side picker, one Start/Stop button (Android) or *Choose a photo* (iOS). |
| `SideTokenPicker` | Home, Settings | Two piece-disc tokens (帥 Red, 將 Black) instead of coloured dots; wraps at large text. |
| `ActionTile`, `SectionHeader` | Home, Settings | Grouped cards replace stacks of identical cards. |
| `Callout` | Result warnings, Settings cost hint | Tinted inline notice with icon; info / warning / error / success tones. |
| Technical details | Result | Collapsed panel: screenshot, providers, confidence, UCI, score, FEN, explanation and the board JSON. UCI, FEN and JSON copy on tap. |
| `HistoryCard` | History, Home | Mini board with arrow, side token, relative time, move, WXF and score. |
| `HintBalanceChip` | Home app bar | Gold coin with the hint balance; turns red at zero. |
| `EmptyState` | History, Result | Icon in a tinted circle, title, message, optional action. |

---

## 5. Screens

**Home (Android).** App bar with the app name, the hint coin, History and Settings.
The Solver Mode hero is the primary action; below it *Analyze a screenshot* (the old
"test" card, now a first-class action) and the latest result as a small board with its
arrow — or, before the first analysis, three numbered *How it works* steps. A one-line
privacy note links to the full notice. The banner ad is anchored at the bottom, outside
the content. On iOS the hero explains share-in and offers *Choose a photo*.

**First run.** A welcome sheet states what the app does and carries the full privacy
disclosure (with the policy link) and a *Get started* button. It shows once (also once
after updating from 1.0) and can be reopened from Settings → About.

**Solver Mode start.** If the overlay permission is missing, an explainer sheet names the
two permissions (display over other apps, screen capture) and what each is for. After
the user grants the overlay permission in system settings and returns, start-up
**continues automatically** to the screen-capture consent — no second press of Start.

**Result.** The move headline and evaluation meter, then the board (oriented to the side
that moved) with the best-move arrow; *Top moves* as rows that redraw the arrow when
tapped (when the engine returned more than one); warnings as a callout; *Technical
details* collapsed. While the engine is still thinking, the recognized board is already
on screen. Errors offer **Try again** (re-runs the same image) and, when out of hints,
**Get more hints**. A light haptic marks a finished analysis.

**History.** Cards with a mini board and arrow, the move, the side and a relative time.
Tapping opens the full result again (`/history/:id`). Swipe to delete one entry, with
*Undo*; *Clear* removes all after a confirmation. Entries saved by 1.0 (no board stored)
still list, as text, and open their old details.

**Settings.** Grouped: *Analysis* (who reads the board, where the engine runs, your own
key, the hint cost), *Game* (your side, capture area, move-notation language),
*Appearance* (theme: system / light / dark; app language), *Privacy* (store screenshots,
policy), *Advanced* (backend, providers, engine tuning — each behind its remote-config
flag) and *About* (version, welcome guide, licences and device ID behind their flags,
admin).

**Get more hints.** A gold-coin balance header and pack rows; layout rules from 1.0
(stretch column, no full-width buttons inside rows) are kept.

**In-game overlay.** Cinnabar analyze button with a gold ring; lacquer-black panels with a
gold hairline; gold result text, soft cinnabar for errors; a bronze crop button, a
cinnabar/ink side pill and a lacquer stop button. Its labels, the capture-area selector
and the Solver Mode notification follow the in-app language, not the phone's.

---

## 6. Accessibility checklist

- Text contrast ≥ 4.5:1 in both themes; gold is used for fills and icons on dark, bronze
  for text on light.
- The board announces the side to move and the move its arrow shows ("Xiangqi board,
  Red to move. The arrow shows Pháo 2 bình 5."); the mini boards in History are
  decorative for screen readers.
- Every icon-only button has a tooltip; touch targets are at least 48 × 48 dp.
- Verified at text scale 2.0 on Home, Result, Settings and the hints sheet.
