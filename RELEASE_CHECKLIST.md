# Pofuduk — Release Checklist

Status as of 2026-11-14. ✅ done · ⛔ blocker · ☐ to do.

## Blockers (must be resolved before App Store submission)
- ⛔ **Weather data licence:** the Open-Meteo free API is non-commercial only. Before a monetized release, do one of: buy Open-Meteo "API Standard", self-host, or use WeatherAPI only.
- ⛔ **WeatherAPI key:** must not ship in the binary. Build the backend proxy (ASP.NET Core, NOTIFICATIONS.md / spec §22), or ship Open-Meteo-only under a commercial plan.
- ⛔ **WeatherAPI disclaimer:** check the exact end-user disclaimer wording WeatherAPI's terms require, and replace the generic footer text with it.
- ⛔ **MGM warnings:** live data needs written permission and a feed. Until then the app shows "unavailable" plus the official link, which is acceptable to ship.
- ☐ Apple Developer account, bundle ID `com.pofuduk.app`, signing.

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
- ☐ Real-device checks: location permission flow, GPS + district search, microphone recognition, notification delivery, background refresh, morning notification, Turkish voices.
- ☐ Time Sensitive Notifications entitlement (only once official warnings are live).

## Assets & metadata
- ✅ Permission texts (Turkish): location, microphone, speech recognition (`project.yml`).
- ✅ App icon: rendered from the character by CI (`AppIcon-1024.png`, opaque) and committed to `AppIcon.appiconset`.
- ✅ App Store metadata draft and screenshot plan: APP_STORE_METADATA.md.
- ☐ Final marketing screenshots (6.7" and 6.1"), from live data once licensing is settled.
- ☐ Support URL, privacy policy URL (publish PRIVACY.md as a web page).
