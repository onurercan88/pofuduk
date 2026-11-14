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

### Phase 4+ — not started
See ROADMAP.md.

## Known limitations
- MGM: no authorized machine-readable source yet → the app shows "unavailable" + an official link. The exact warning-page URL still needs checking.
- Provider licences (WeatherAPI, Open-Meteo commercial use) not yet validated.
- Turkish TTS needs a tr-TR voice installed on the device or simulator. Without one, subtitles are shown instead.
