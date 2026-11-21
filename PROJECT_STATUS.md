# Pofuduk — Project Status

_Last updated: 2026-11-19_

## Environment
- Dev machine: Windows 11, no Xcode. Swift 6.4.2 → `PofudukCore` builds and tests here (`scripts\swift-core.cmd test`); console demo with live data via `.\scripts\pofuduk.cmd Ankara --ses` (Turkish voice "Microsoft Tolga").
- Repo `onurercan88/pofuduk` is **public** (since 2026-11-15; free CI). GitHub Actions (`macos-latest`, Xcode 26.6) builds and tests the app on every push except `.md`-only ones. It also takes screenshots and records the guided tour video (artifact `screenshots`).
- TestFlight: `.github/workflows/testflight.yml` (manual run) ✅ works. Membership active (individual), App ID `com.pofuduk.app`, App Store Connect app "Pofuduk: Konuşan Hava Durumu", secrets set. Archive is unsigned; export signs for App Store (no registered device needed). First build 0.1.0 (2) uploaded 2026-11-15.

## Phase checklist
### Phase 1 — Architecture ✅
- [x] PRD, ARCHITECTURE, ROADMAP, API_INTEGRATIONS, PRIVACY, DEVELOPMENT
- [x] Core models (weather, place, alerts, character, briefing) + provider protocols
- [x] Environment inspection

### Phase 2 — Visual MVP ✅ (visuals reviewed via CI screenshots + tour video)
- [x] `WeatherSummaryEngine` (thresholds, rain likely/possible, intensity from amounts only, wind, UV, swing, stale) — tested
- [x] `CharacterPersonalityEngine` (friendly/playful/calm, warnings first, serious mode, demo/stale disclosure) — tested
- [x] `SubtitleTrack` + `SentenceSegmenter` — tested
- [x] Demo data (`MockWeatherData`, always labelled "Örnek veri")
- [x] XcodeGen `project.yml`, App shell, DI container, coordinator
- [x] Character: cloud body, 11 moods, blink, speaking mouth, sunglasses/umbrella/scarf, weather effects, Reduce Motion
- [x] Home: header, hero temp, character, subtitle bubble with word highlight, play/pause/stop/replay, sound toggle, transcript, hourly, tomorrow, advice, MGM status, demo scenario picker, source footer
- [x] `SpeechService` (AVSpeechSynthesizer, one utterance per sentence, interruption pause)
- [x] App unit tests (6, HomeViewModel) + UI smoke test (1) — pass in CI on an iOS simulator
- [x] Compile on Xcode 26.6 (CI)
- [x] Visual review: CI saves screenshots of 6 scenarios in light mode and 3 in dark mode (artifact `screenshots`). Fixed the overlapping outlines in the cloud body and the scarf position.
- [x] Turkish TTS confirmed on the CI simulator: the highlighted word moves forward from the real `willSpeakRange` callbacks.
- [ ] Turkish speech listened to on a real device
- [ ] App icon artwork

### Phase 3 — Weather integration ✅
- [x] Provider terms checked (WeatherAPI: commercial OK on free; Open-Meteo: non-commercial only)
- [x] `HTTPClient` abstraction + URLSession implementation (works on iOS and Windows)
- [x] `OpenMeteoProvider` (WMO codes, local-time parsing, UV from the current hour) — fixture-tested; live call checked from Windows
- [x] `WeatherAPIProvider` (condition codes, rain/snow probability, astro times, key never logged) — fixture-tested
- [x] `WeatherProviderFallbackEngine` (WeatherAPI → Open-Meteo)
- [x] `CachedWeatherRepository` (30-min freshness, offline stale fallback ≤ 6 h, still flagged stale) + file cache
- [x] Keychain key store (DEBUG env-var seeding); app runs live by default, demo only via launch argument
- [x] Error UI (error mood, honest unavailable briefing, retry card); attribution + disclaimer footer
- [ ] Exact WeatherAPI disclaimer wording (check before release)
- [x] Simulator screenshot showing live Open-Meteo data (CI `live-light.png`)
- [ ] Polish: the subtitle sentence transition slides in from the bottom edge and briefly overlaps the progress dots; switch to a small offset + fade

### Phase 4 — Location ✅ (CI: builds, 12 VM + 1 UI tests pass; permission sheet screenshot reviewed)
- [x] `LocationResolver` policy: explain first, When In Use only, IP only on explicit opt-in, never silent fallback — tested
- [x] `LocationPreference` persisted (UserDefaults; only the user's choice, never GPS fixes)
- [x] Offline list of 81 provinces with Turkish-aware search; district/city search via MapKit (TR only)
- [x] `WeatherAPIIPLocationProvider` (approximate, offered only when a WeatherAPI key exists) — tested
- [x] `CoreLocationProvider`: one-shot ~1 km fix, reverse geocoding in Turkish, place time zone
- [x] Permission explanation sheet, denied/unavailable alternatives with a Settings link, picker, "Yaklaşık konum" badge
- [x] No weather is shown or spoken until a location exists (no hard-coded Istanbul in live mode)
- [x] Subtitle transition polish (small offset + fade)
- [x] Network: one retry on transport errors; failure reason shown in the retry card; transport error codes logged (no URLs)
- [ ] Live-data CI screenshot is best-effort: on 2026-11-14 the GitHub macOS runner could not reach api.open-meteo.com (app −1001 timeouts; host curl failed too). The app showed the correct honest error. Likely IP throttling of shared runners → another reason for WeatherAPI + backend proxy in production.
- [ ] Real-device test of the permission prompt, GPS fix and district search (not possible in CI)

### Phase 5 — Turkish voice & conversation ✅ (CI: 75 core, 16 VM, 1 UI tests pass; ask bar screenshot reviewed)
- [x] `WeatherQueryParser`: deterministic Turkish (dates, weekdays, weekend, day parts, "saat 17.00", provinces with case suffixes, topics) — tested
- [x] `WeatherIntentResolver` + `ConversationManager`: follow-ups inherit date/day part/city; 10-minute context; reset on location change — tested
- [x] `ForecastDateResolver`: weekend/weekday rules, midnight, other time zones, DST, provider coverage — tested
- [x] `WeatherAnswerEngine`: overview, temperature (day/part/hour), rain/timing, umbrella, wind, UV, basic clothing, going out; honest "no forecast yet" outside range; natural "Bu akşam / Bu sabah"
- [x] `WeatherQueryService` (asks about another province fetch that province's forecast)
- [x] `ConversationViewModel` + AskBar (suggestions, text, send); answers spoken via the same TTS + subtitle pipeline
- [x] Microphone: Speech framework tr-TR, permission asked on first tap, on-device recognition required where supported, server use disclosed, 10 s auto-stop, listening/thinking moods
- [ ] District-level questions ("Kaş'ta") fall back to the current place (the answer names the place); geocoding in questions comes in Phase 9
- [ ] Turkish voice selection UI and speech-rate setting → Phase 11 (settings)
- [ ] Real-device test of the microphone (simulator CI covers only the logic, using a stub recognizer)

### Phase 6 — Clothing recommendations ✅ (CI: 83 core, 17 VM, 1 UI tests pass; detail screen screenshot reviewed)
- [x] `ClothingRecommendationEngine`: deterministic, configurable `ClothingRules` (felt-temperature bands, layering spread, wind chill, active hours); uses actual temp, feels-like, wind/gusts, rain (likely vs possible; snow → boots), UV, and the morning/evening spread
- [x] Explains "why" (each reason tied to a data point); no hourly data → no advice
- [x] Added to the main briefing only when noteworthy (cold, hot, layers, chill, wind, likely rain); one sentence, no umbrella/UV repetition
- [x] Conversation "ne giysem?" uses the engine
- [x] Home card + detail screen (today/tomorrow, items, reasons, "Pofuduk anlatsın", non-medical disclaimer)
- [x] Tests: hot, cold, windy, rainy, large morning/evening difference, mild day not noteworthy, no data, tomorrow + briefing

### Phase 7 — Weather notifications ✅ (CI: 96 core, 20 VM, 1 UI tests pass)
- [x] `RainNotificationEngine`: rain/snow soon (user lead time + probability threshold), heavy rain (amounts only), thunderstorm, strong wind, tomorrow's temperature change, verified MGM warnings; 6 h trust horizon; never from stale forecasts; source in every message
- [x] Quiet hours (wrap midnight); only orange/red official warnings break through (time-sensitive)
- [x] Dedup via delivery log (delivered → never re-sent; pending → replaced by newer forecast)
- [x] Per-category preferences, lead time, threshold, quiet hours (settings screen via bell button)
- [x] Permission asked only when the user enables notifications; denied → explained + Settings link
- [x] `UNUserNotificationCenter` scheduling; `BGAppRefreshTask` best-effort refresh using the last coarsened place (no background location)
- [x] Demo data never schedules notifications
- [x] NOTIFICATIONS.md: local vs backend/APNs comparison; PRIVACY.md updated
- [ ] Real-device check of delivery and background refresh (can't be verified in simulator CI)
- [ ] Time-sensitive delivery needs the Time Sensitive Notifications entitlement (release setup)

### Phase 8 — Morning briefing "Pofuduk Günaydın" ✅ (CI: 105 core, 24 VM, 1 UI tests pass)
- [x] `MorningBriefingEngine`: greet once per day between the chosen time and noon; morning start temp → afternoon peak, rain by time of day (likely vs possible), wind, UV, clothing, MGM warnings first (serious tone), demo/stale disclosure
- [x] Settings: on/off, 07:00 / 07:30 / 08:00 / 08:30 / custom, speak automatically or text only, text-notification alternative, location shortcut (reached from the bell → "Pofuduk Günaydın")
- [x] Greeting when the app opens or returns from the background in the morning; sleepy-to-awake animation
- [x] Optional morning notification at the chosen time from the latest daily forecast (not sent if the forecast would be >18 h old at delivery; source + time stated; deduplicated; quiet hours don't apply because the user chose the time)
- [x] Demo data follows the container clock (deterministic tests)

### Phase 9 — Travel weather "Seyahat Hava Durumu" ✅ (CI: 113 core, 27 VM, 1 UI tests pass; travel screen not yet screenshotted)
- [x] `TravelWeatherSummaryEngine`: departure → return days (max 7) in the destination's time zone; comparison with origin ("İstanbul'dan biraz daha serin"); rain by time of day; wind; later days in one line each; packing advice from the clothing engine; "less certain" note from day +3; missing days stated; time-zone difference stated
- [x] `DestinationResolver`: offline province match + Apple geocoding (districts, cities abroad)
- [x] `TravelWeatherService` (origin failure doesn't block the destination), `TravelWeatherViewModel`, travel screen (search, dates, summary, daily rows, packing, "Pofuduk anlatsın"), home card
- [x] Conversation: "Yarın Bursa'ya gideceğim", "Hafta sonu Antalya'ya gitmek istiyorum", "İstanbul'dan Ankara'ya yolculuk" → travel answer; unknown destination → honest prompt
- [x] No route or road information is ever claimed (footnote on the screen)
- [ ] Saved trips (future feature per spec)

### Phase 10 — MGM official warnings ✅ code / ⛔ live data blocked on MGM permission (CI: 122 core, 32 VM, 1 UI tests pass)
- [x] Investigation: no documented/authorized MGM feed; legal notice requires prior permission; MeteoAlarm excludes Turkey (details in API_INTEGRATIONS.md, with a draft request to MGM)
- [x] `WeatherAlertMatcher` (active, ≥ yellow, province/district, sorted by severity) — tested: none, yellow, orange, red, expired, not yet valid, another province, district
- [x] `CAPWarningParser` (CAP 1.2, Turkish info preferred, awareness level / severity) — tested
- [x] `ConfiguredMGMWarningProvider` + `MGMAlertRepository`: off until an authorized feed URL is configured; a failure is "unavailable" with the official page (verified URL)
- [x] Banner (level text + distinct shape per level, validity, "+N"), detail screen (level, hazard, area, start/end, description, official source, "forecasts are never warnings" note), warning mode for any verified warning, warnings first in briefings, MGM notifications (Phase 7)
- [ ] **Blocked externally:** live warnings need written permission and a feed from MGM

### Phase 11 — Personality & personalization ✅ (CI: 126 core, 35 VM, 1 UI tests pass; settings screen not yet screenshotted)
- [x] `UserPreferences` (style: Samimi/Şakacı/Sakin, Kısa/Ayrıntılı, speech rate 0.8–1.25×, Turkish voice, subtitle size), stored on device only
- [x] Style/length change tone only; facts identical across styles; no humour during storms or orange/red warnings; short briefings keep current conditions, rain and strong wind — tested
- [x] Voice picker (installed tr-TR voices, best quality first; help text if none installed), speed slider, "Sesi dene"
- [x] Subtitle size (Dynamic Type styles, still scales with iOS text size) for the bubble and transcript
- [x] Settings screen (gear): Pofuduk, Ses, Altyazılar, Konum, Bildirimler, Pofuduk Günaydın, units (°C, km/sa), language (Türkçe), data sources, privacy, "Verilerimi sil" (confirmation; clears cache, location, notifications + log, morning, preferences, sound, conversation), Hakkında
- [x] Character reaction: tapping idle Pofuduk → happy (celebrating in playful style); tapping while speaking → pause/resume

### Phase 12 — Quality & release prep ✅ (CI: 130 core incl. 4 integration [+1 opt-in live], 36 VM + icon, 5 UI incl. accessibility audit — all pass)
- [x] Integration tests (provider → fallback → cache → briefing → subtitles; conversation over WeatherAPI; notifications + morning); opt-in live test (`POFUDUK_LIVE_TESTS=1`, passes from Windows)
- [x] UI tests: home controls, typed question → answer, settings, clothing + travel screens
- [x] Apple accessibility audit passes. It found and we fixed: accent contrast, the night theme with dark text, the demo badge, decorative text without Dynamic Type, and the clipped question field. Contrast is skipped only for content covered by the ask bar (logged).
- [x] Hero temperature scales with Dynamic Type; character animation 30 fps
- [x] Security, performance, error-handling and privacy reviews (RELEASE_CHECKLIST.md); `PrivacyInfo.xcprivacy`
- [x] App icon rendered from the character in CI (opaque 1024 px) and added to the asset catalog
- [x] README.md, RELEASE_CHECKLIST.md, APP_STORE_METADATA.md (Turkish metadata, keywords, privacy label, screenshot plan)
- [ ] Before release (see RELEASE_CHECKLIST.md): confirm with Open-Meteo that a free, ad-free release counts as non-commercial; Apple developer account/signing; real-device checks; MGM permission (optional; the app works with the official link meanwhile); WeatherAPI only with the backend proxy

### After Phase 12 (2026-11-15)
- [x] Windows console demo (`PofudukDemo` + `scripts\pofuduk.cmd`): live Open-Meteo briefing, clothing, notification plan, Q&A, `--ses` with Tolga
- [x] CI guided tour recording (`DemoTourUITests`, skipped in normal runs; step capped at 15 min, non-blocking)
- [x] Bug fixed: an answer asked while the briefing was speaking stayed at "hazırlanıyor" (AVSpeechSynthesizer drops utterances queued during `stopSpeaking`). Now `speak()` waits up to ~1 s for the stop to complete. Covered by fast `SpeechServiceTests` (real synthesizer; started and finished events). The tour video confirms it.
- [x] Reduce Motion / still renders freeze with open eyes
- [x] Docs: DEVICE_TESTING.md (iPhone test guide, TestFlight setup), Open-Meteo and MGM request drafts (API_INTEGRATIONS.md)
- [x] TestFlight upload (build 0.1.0 (2))
- [x] Real-iPhone test (3 internal testers via TestFlight; voice questions work)

### Device feedback (2026-11-19)
- [x] Cloudy weather showed the rainy character: look now = weather now (+ rain within 1 h); words keep the rest-of-day outlook (`outlookTheme`)
- [x] "Cloudy" while raining: Open-Meteo current precipitation amount overrides a dry weather code
- [x] Default speech ~7% faster
- [x] Time-of-day briefing: afternoon = rest of day, evening/night = tonight's low + tomorrow
- [x] Lip sync from the spoken word's letters (`LipSync`); storm = umbrella hat + nervous (not angry) face; windy = kite
- [x] Cross-check current conditions with Apple WeatherKit (capability enabled, entitlement, attribution, CI entitlement check) — see API_INTEGRATIONS.md
- [x] Verify on device that WeatherKit answers (owner: all good, 2026-11-19)
- [x] Refresh left the bubble at "hazırlanıyor" → refresh speaks; 4 s watchdog shows text if speech never starts
- [x] Tap reactions (glasses toss, umbrella twirl, hat flip, dance + giggle on a separate synthesizer)

### App Store 1.0 (started 2026-11-19)
- [x] Decisions: WeatherKit as primary forecast (licence blocker gone), GitHub Pages for privacy/support, Turkey only, version 1.0.0
- [x] `AppleWeatherProvider` + `AppleWeatherSnapshotBuilder` (tested); cross-check skipped when Apple is already the source
- [x] Privacy/support pages in `docs/` (GitHub Pages)
- [x] GitHub Pages live (https://onurercan88.github.io/pofuduk/), CI green (5201a7f), TestFlight 1.0.0 uploaded (run 44586219944)
- [ ] Device check of the WeatherKit forecast on 1.0.0 (not done before submission)
- [x] Store screenshots: `store-screenshots.yml` (iPhone 17 Pro Max, 1320×2868); chosen 6 in `store-screenshots/` (gitignored)
- [x] App Store Connect: description, keywords, promo text, URLs, review notes, subtitle, categories (Weather/Lifestyle), content rights, age rating 4+, free, Türkiye only, App Privacy "Data Not Collected" (published)
- [x] Screenshots attached (6.9" slot; required 6.1"/6.3" slot uses them scaled), copyright + review contact (owner), build 7 attached, age rating incl. new Shared Location/Dating questions, release: automatic after approval
- [x] Submitted for App Review 2026-11-19 (1.0.0 build 7) — "Waiting for Review"

### Device layout check (2026-11-20)
- [x] `device-matrix.yml`: 6 iPhone sizes × normal/XXXL/AX5; no crashes or faults; TestFlight build 7: 0 crashes
- [x] Fixed: page clipped on both edges on 375 pt iPhones (SE, mini); header/hero/clothing at accessibility text sizes; lightning flash showed a box on wide screens
- [x] 1.0.0 approved and live in Türkiye (2026-11-20). 1.0.1 (build 8, layout fixes) submitted for App Review 2026-11-21 — "Waiting for Review", automatic release after approval
- [ ] New TestFlight build with the above, then re-test on device

## Known limitations
- MGM: no authorized machine-readable source → the app shows "unavailable" + the official page (https://www.mgm.gov.tr/meteouyari/turkiye.aspx, verified).
- Licences: WeatherAPI terms were checked (commercial OK on the free plan). Open-Meteo's free API is non-commercial, so a confirmation email is pending.
- Turkish TTS needs a tr-TR voice on the device or simulator. Without one, subtitles are shown instead.
- UI tests run slowly while the app is speaking (XCUITest waits for an idle app), so speech is covered by unit-level tests instead.
