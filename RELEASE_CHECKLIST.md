# Pofuduk — Release Checklist

Status as of 2026-11-19. ✅ done · ⛔ blocker · ☐ to do.

## Blockers (must be resolved before App Store submission)
- ✅ **Weather data licence:** resolved 2026-11-19 by making Apple Weather (WeatherKit) the primary forecast source (commercial use allowed). Open-Meteo is only the last fallback when WeatherKit fails; the release is free, ad-free and has no in-app purchases. Earlier notes on Open-Meteo:
  - **Free, ad-free release without in-app purchases:** the free API (`api.open-meteo.com/v1/forecast`, already used) very likely qualifies as non-commercial use. Open-Meteo's terms name apps with subscriptions or ads as commercial. Confirm by email to info@open-meteo.com with a short description of the app before submission. CC BY 4.0 attribution is already shown in the app.
  - **If ads, subscriptions or a paid version are added:** switch to the paid "API Standard" plan (a separate endpoint plus an API key). The provider is its own layer in the code, so the change is small.
  - **Rate limits:** apply per IP. Each user's phone uses its own IP, and forecasts are cached for 30 minutes, so normal use is fine.
- ☐ **WeatherAPI (optional):** not needed for an Open-Meteo-only release. If used, its key must not ship in the binary: use the backend proxy (ASP.NET Core, NOTIFICATIONS.md / spec §22).
- ☐ **WeatherAPI disclaimer (only if WeatherAPI is used):** check the exact end-user disclaimer wording WeatherAPI's terms require, and replace the generic footer text with it.
- ⛔ **MGM warnings:** live data needs written permission and a feed. Until then the app shows "unavailable" plus the official link, which is acceptable to ship.
- ✅ Apple Developer account, unique bundle ID, App Store Connect API key (Admin) and GitHub secrets. Builds are signed and uploaded by `.github/workflows/testflight.yml` (manual run; see DEVICE_TESTING.md, Yol B).

## Quality (Phase 12)
- ✅ Unit tests: core engines (Windows + macOS CI). Integration tests: provider → briefing → subtitles, conversation, notifications/morning (fixtures). Live provider test is opt-in (`POFUDUK_LIVE_TESTS=1`).
- ✅ App tests: view models (location, speech, conversation, clothing, notifications, morning, travel, MGM, personalization). UI tests: home, typed question, settings, clothing/travel screens.
- ✅ Accessibility: automated `performAccessibilityAudit` on home; VoiceOver labels on the character, hourly items, banner, buttons; Dynamic Type (subtitles, hero temperature); Reduce Motion; warning severity shown with text + shape, not only colour; full transcript; app fully usable with sound off.
- ☐ Manual VoiceOver walkthrough on a device (all screens), largest accessibility text sizes, Bold Text, Increase Contrast.
- ✅ **Security review:**
  - no secrets in the repo
  - HTTPS only
  - API key read from the Keychain at request time, never logged
  - URLs with keys never logged; errors carry no URLs
  - no undocumented MGM endpoints or scraping
- ✅ **Performance review:**
  - character animation 30 fps, paused with Reduce Motion
  - weather effects are lightweight Canvas drawing
  - forecast cached for 30 minutes; one network retry
  - background refresh at most hourly (iOS decides)
- ✅ **Error handling review:** network, rate limit, missing key, bad response, no data, out of range, stale forecast, no location, permission denied (location, microphone, notifications), no Turkish voice. Each has an honest Turkish message and a fallback. `try?` is used only for best-effort work: cache I/O, audio session, sleeps, optional origin forecast, geocoding.
- ✅ **Privacy review:** PRIVACY.md is current. `PrivacyInfo.xcprivacy` declares no tracking, no collected data, and UserDefaults with reason CA92.1. Location is never stored except as the coarsened last place used for notifications. "Verilerimi sil" is available.
- ✅ Real-device checks via TestFlight (2026-11-19, 3 internal testers; owner confirmed everything works). Original list: location permission flow, GPS + district search, microphone recognition, notification delivery, background refresh, morning notification, Turkish voices.
- ☐ Time Sensitive Notifications entitlement (only once official warnings are live).

## Assets & metadata
- ✅ Permission texts (Turkish): location, microphone, speech recognition (`project.yml`).
- ✅ App icon: rendered from the character by CI (`AppIcon-1024.png`, opaque) and committed to `AppIcon.appiconset`.
- ✅ App Store metadata draft and screenshot plan: APP_STORE_METADATA.md.
- ✅ Store screenshots (6.9", demo data via `store-screenshots.yml`); submitted 2026-11-19.
- ✅ Support URL https://onurercan88.github.io/pofuduk/destek.html and privacy policy URL https://onurercan88.github.io/pofuduk/gizlilik.html (GitHub Pages from `docs/`; enable Pages once).
- ✅ Release decisions (2026-11-19): version 1.0.0, free, available in Turkey only (no EU → no DSA trader declaration needed).
