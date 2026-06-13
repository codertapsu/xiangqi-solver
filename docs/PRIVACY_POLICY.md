# Privacy Policy — Xiangqi Solver

_Last updated: [DATE]. This is a DRAFT template — review it (ideally with a lawyer),
fill in the bracketed values, host it at a public URL, and paste that URL into Google
Play Console (App content → Privacy policy) and the in-app Settings/About._

> **Note:** the LIVE policy page (hosted on codertapsu-web) must be regenerated from
> this text whenever this file changes — this document is the source of truth.

**Developer:** [YOUR NAME / COMPANY]
**Contact:** [YOUR SUPPORT EMAIL]

Xiangqi Solver ("the app") helps you analyze a Chinese-chess (Xiangqi) board. This
policy explains what data the app handles and why.

## What we collect and why

- **Board screenshots / images you analyze.** When you use cloud analysis, the image of
  the board you choose to analyze is sent to our server, which forwards it to an AI
  provider (**OpenAI** or **Google**) for board recognition. Images are **processed in
  memory and not stored** on our server; they are used only to compute the move and are
  **not** used to identify you. If you use **"Use my own key"** mode, the image goes
  **directly from your device to OpenAI** and never touches our server.
- **Hint balance — stored on your device.** Your hint balance lives **only on your
  device** (in the app's local storage). There is **no account** and **no balance or
  transaction ledger on our server**. To prevent the one-time free-hint grant from being
  claimed repeatedly by reinstalling, our server keeps an **install-grant ledger** (plus
  any manual support grants) keyed by an opaque, randomly generated device identifier
  (not your name, email, or Google account). The same identifier is used for per-device
  rate limiting of our API.
- **Purchase information.** When you buy a hint pack, **Google Play** processes the
  payment (we never see your card details); purchased hints are credited locally on your
  device, and we do not receive or store your purchase details on our server.
- **Advertising data.** We show ads (banner, and optionally rewarded ads for extra
  hints) via **Google AdMob**, which may collect your device's advertising identifier
  and related data to serve and measure ads, subject to your consent (we show a consent
  form where required, e.g. in the EEA/UK).
- **Your own OpenAI API key (optional).** If you choose **"Use my own key"** mode, your
  key is stored **only on your device** (in the platform keystore) and used to call
  OpenAI directly. It is never sent to our server.
- **Analysis history (on your device).** If enabled, recent analysis screenshots are
  kept **only on your device** (a small, capped number of recent items); they are never
  uploaded for history purposes.
- **Diagnostic logs for failed requests.** When a cloud analysis fails, our server
  appends a diagnostic log entry (error metadata such as timestamps, error codes, and
  messages). These logs **never** contain the image itself or any API keys.

The app also requests screen-capture and overlay permissions **only** to capture the
board you point it at, with your explicit consent each session; captures are not taken
in the background.

## Third parties

- **OpenAI** and/or **Google** — board recognition (cloud analysis). See each provider's
  privacy policy.
- **Google AdMob** — ads. See Google's policy: https://policies.google.com/privacy
- **Google Play Billing** — purchases.

## Your choices

- Use **"Use my own key"** mode to avoid sending images to our server (the recognized
  board position — text, not the image — may still be sent to our server if you use our
  cloud engine), or the fully on-device mode to send nothing at all.
- Manage/reset your advertising id and ad personalization in Android settings; adjust ad
  consent via the in-app consent options where shown.
- Contact us at [YOUR SUPPORT EMAIL] to request deletion of your device identifier from
  our install-grant ledger.

## Children

The app is not directed to children under 13 (or the age of digital consent in your
region) and we do not knowingly collect their data.

## Changes

We may update this policy; material changes will be reflected by the "Last updated" date
above.

## Contact

[YOUR NAME / COMPANY] — [YOUR SUPPORT EMAIL]
