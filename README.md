# Pofuduk ☁️

A talking weather companion for iOS. A cute cloud character explains the weather in natural Turkish speech, with subtitles that match the speech word for word, advice, clothing tips, travel weather, rain notifications and a morning briefing.

## Highlights
- **Briefings from real data only:** rain likely vs possible, "heavy" only from rain amounts, wind, UV, stale and demo data disclosed.
- **Character:** 11 moods, weather looks (sunglasses, umbrella, scarf), weather effects, Reduce Motion support.
- **Speech:** Turkish voice choice and speed. Subtitles follow the real speech callbacks, so they always match.
- **Questions by text or voice:** a Turkish question parser with follow-up context, no LLM.
- **Features:** "Bugün Ne Giysem?", "Seyahat Hava Durumu", "Yağmur Başlamadan Haber Ver", "Pofuduk Günaydın".
- **MGM official warnings:** matcher and CAP parser are ready. Turned off until MGM grants access (see API_INTEGRATIONS.md).
- **Privacy:** When In Use location only, no accounts, everything stored on the device, "Verilerimi sil".

## Repository layout
| Path | What |
|---|---|
| `PofudukCore/` | Swift Package: all domain logic + tests (builds on macOS, iOS, Windows) |
| `Pofuduk/` | SwiftUI app (MVVM), generated Xcode project via `project.yml` (XcodeGen) |
| `Tests/UnitTests`, `Tests/UIAutomationTests` | App view-model, icon and UI/accessibility tests |
| `.github/workflows/ios.yml` | CI: core tests, app build + tests on an iPhone simulator, screenshots, icon |

## Build & run
See **DEVELOPMENT.md**. Short version:
```bash
brew install xcodegen && xcodegen generate && open Pofuduk.xcodeproj
```
Core tests anywhere Swift runs: `cd PofudukCore && swift test` (Windows: `scripts\swift-core.cmd test`).

## Configuration
| Setting | Where | Default |
|---|---|---|
| WeatherAPI key (optional) | Debug: scheme environment variable `WEATHERAPI_KEY` → Keychain. Release: backend proxy (planned) | none → Open-Meteo |
| MGM warning feed | `MGMWarningFeedURL` in `project.yml` (only with written MGM permission) | empty → "unavailable" + official link |
| Demo mode | launch argument `-pofuduk.demoScenario sunny\|rainyAfternoon\|stormy\|snowy\|cloudy\|windy` | live data |

## Documents
PRD · ARCHITECTURE · ROADMAP · API_INTEGRATIONS · PRIVACY · NOTIFICATIONS · DEVELOPMENT · PROJECT_STATUS · RELEASE_CHECKLIST · APP_STORE_METADATA
