# Pofuduk — Project Status

_Last updated: 2026-11-14_

## Environment
- Dev machine: Windows 11, no Xcode. Swift 6.4.2 toolchain installed → only `PofudukCore` can be built and tested here (`scripts\swift-core.cmd test`).
- iOS app is built and tested by GitHub Actions (`macos-latest`, Xcode 26.6) on every push to the private repo `onurercan88/pofuduk`. Pushes that only change `.md` files are skipped.

## Phase checklist
### Phase 1 — Architecture ✅
- [x] PRD, ARCHITECTURE, ROADMAP, API_INTEGRATIONS, PRIVACY, DEVELOPMENT
- [x] Core models (weather, place, alerts, character, briefing) + provider protocols
- [x] Environment inspection

### Phase 2 — Visual MVP 🟡 (builds + tests pass in CI; visuals not yet reviewed)
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

### Phase 9+ — not started
See ROADMAP.md.

## Known limitations
- MGM: no authorized machine-readable source yet → the app shows "unavailable" + an official link. The exact warning-page URL still needs checking.
- Provider licences (WeatherAPI, Open-Meteo commercial use) not yet validated.
- Turkish TTS needs a tr-TR voice installed on the device or simulator. Without one, subtitles are shown instead.
