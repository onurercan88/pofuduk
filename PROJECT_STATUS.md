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
- [ ] Visual review of the screen (no screenshots yet)
- [ ] Turkish speech heard on a real device (CI simulator has no audio check)
- [ ] App icon artwork

### Phase 3+ — not started
See ROADMAP.md.

## Known limitations
- MGM: no authorized machine-readable source yet → the app shows "unavailable" + an official link. The exact warning-page URL still needs checking.
- Provider licences (WeatherAPI, Open-Meteo commercial use) not yet validated.
- Turkish TTS needs a tr-TR voice installed on the device or simulator. Without one, subtitles are shown instead.
