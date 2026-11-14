# Pofuduk — Architecture

## Overview
```
PofudukCore/          Swift Package: pure Foundation. Builds and tests on macOS, iOS AND Windows.
  Models/             Weather, place, alert, character, briefing models
  Protocols/          Provider/repository contracts
  Engines/            Business engines (deterministic, configurable thresholds)
  Speech/             Sentence segmentation + subtitle state machine (no AVFoundation)
  DateTime/           Turkish time/date formatting, forecast date resolution
  Mock/               Deterministic sample data — previews, tests, labelled demo mode only
Pofuduk/              iOS app (SwiftUI, MVVM), generated Xcode project via XcodeGen (project.yml)
  App/                PofudukApp, AppCoordinator, DependencyContainer
  Core/Speech/        AVSpeechSynthesizer adapter (SpeechService)
  Data/Repositories/  Repository implementations (Demo now; WeatherAPI/Open-Meteo/MGM in Phase 3/10)
  Features/Home/      Home screen views + HomeViewModel
  Character/          Character rendering, accessories, weather effects (replaceable)
  DesignSystem/       Colours, gradients, typography, reusable components
backend/              (Later) ASP.NET Core Minimal API — optional, not required for MVP
```

## Key decisions
| Decision | Why |
|---|---|
| Domain logic lives in the `PofudukCore` SPM package | It is testable without a simulator, including on the Windows dev machine. It also keeps UI and logic apart. |
| Protocol names drop the `I` prefix (`WeatherProvider` = spec `IWeatherProvider`, likewise `WeatherRepository`, `LocationProvider`, `MGMWarningProvider`, `WeatherAlertRepository`) | Swift API design guidelines. |
| MVP character uses SwiftUI shapes + `TimelineView`/`Canvas` | No dependency, vector, supports Reduce Motion. |
| Future character assets: **Rive** preferred over Lottie | Rive has built-in state machines with inputs (mood, theme, speaking), which fits the interactive states. Lottie is linear timelines only. The swap point is `CharacterView(appearance:)`, which takes a `CharacterAppearance` value. |
| One `AVSpeechUtterance` per sentence | `didStart` gives exact sentence sync, `willSpeakRange` gives word highlight. Subtitles = the same strings → exact match. No timing estimates. |
| Engines use injected `Calendar`/`TimeZone`/`now` | Deterministic tests, and correct destination timezones. |
| Configurable thresholds (`WeatherThresholds`) | Interpretation can be tuned without touching the UI. |
| XcodeGen `project.yml` instead of committed `.pbxproj` | The project can be generated reproducibly, and the file is diff-friendly. |
| Swift 5 language mode for now | Lowers the risk of strict-concurrency errors that can't be verified on Windows. Move to Swift 6 once Mac CI exists. |

## Data flow (Home)
```
HomeViewModel ──► WeatherRepository.snapshot(for: Place) ──► WeatherSnapshot
      │                                                    (source, retrievedAt, expiresAt)
      ├──► WeatherSummaryEngine.analyze(snapshot, now) ──► WeatherAnalysis
      ├──► CharacterPersonalityEngine.briefing(analysis, style) ──► Briefing (sentences)
      │                                       └──► CharacterAppearance (mood + theme)
      └──► SpeechService.speak(sentences) ──callbacks──► SubtitleTrack (current sentence/word)
```

## Required engines (spec §28) — status in PROJECT_STATUS.md
WeatherSummaryEngine, ClothingRecommendationEngine, WeatherQueryParser, WeatherIntentResolver, WeatherAlertMatcher, CharacterPersonalityEngine, LocationResolver, TravelWeatherSummaryEngine, RainNotificationEngine, MorningBriefingEngine, ForecastDateResolver, WeatherProviderFallbackEngine. All engines live in `PofudukCore/Engines`.

## Rules
- No networking, business logic or speech in SwiftUI views.
- Dependency injection through `DependencyContainer`. Every external integration sits behind a protocol.
- Every snapshot carries its source, retrieval time and expiry. The UI shows it as stale or demo when it is one.
