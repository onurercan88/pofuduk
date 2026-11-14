# Pofuduk — Project Status

_Last updated: 2026-11-14_

## Environment
- Dev machine: Windows 11, no Xcode. Swift 6.4.2 toolchain installed → only `PofudukCore` can be built and tested here (`scripts\swift-core.cmd test`).
- iOS app layer (SwiftUI/AVFoundation) has **not been compiled yet**. It needs macOS + Xcode, or the GitHub Actions workflow (`.github/workflows/ios.yml`, which also needs a git repo + push).

## Phase checklist
### Phase 1 — Architecture ✅
- [x] PRD, ARCHITECTURE, ROADMAP, API_INTEGRATIONS, PRIVACY, DEVELOPMENT
- [x] Core models (weather, place, alerts, character, briefing) + provider protocols
- [x] Environment inspection

### Phase 2 — Visual MVP 🟡 (code written; iOS build unverified)
- [x] `WeatherSummaryEngine` (thresholds, rain likely/possible, intensity from amounts only, wind, UV, swing, stale) — tested
- [x] `CharacterPersonalityEngine` (friendly/playful/calm, warnings first, serious mode, demo/stale disclosure) — tested
- [x] `SubtitleTrack` + `SentenceSegmenter` — tested
- [x] Demo data (`MockWeatherData`, always labelled "Örnek veri")
- [x] XcodeGen `project.yml`, App shell, DI container, coordinator
- [x] Character: cloud body, 11 moods, blink, speaking mouth, sunglasses/umbrella/scarf, weather effects, Reduce Motion
- [x] Home: header, hero temp, character, subtitle bubble with word highlight, play/pause/stop/replay, sound toggle, transcript, hourly, tomorrow, advice, MGM status, demo scenario picker, source footer
- [x] `SpeechService` (AVSpeechSynthesizer, one utterance per sentence, interruption pause)
- [x] App unit tests (HomeViewModel) + UI smoke test — **not run**
- [ ] Compile and run in iOS simulator (blocked: needs a Mac/CI)
- [ ] App icon artwork

### Phase 3+ — not started
See ROADMAP.md.

## Known limitations
- MGM: no authorized machine-readable source yet → the app shows "unavailable" + an official link. The exact warning-page URL still needs checking.
- Provider licences (WeatherAPI, Open-Meteo commercial use) not yet validated.
- Turkish TTS needs a tr-TR voice installed on the device or simulator. Without one, subtitles are shown instead.
