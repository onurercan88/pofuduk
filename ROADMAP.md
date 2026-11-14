# Pofuduk — Roadmap

| Phase | Scope | Gate |
|---|---|---|
| 1 Architecture | PRD, ARCHITECTURE, ROADMAP, API_INTEGRATIONS, PRIVACY, DEVELOPMENT; core models/protocols | Docs + package builds |
| 2 Visual MVP | App shell, character + moods + weather looks, home screen, speech bubble/subtitles, demo data, light/dark, design system | Runs in simulator with demo data |
| 3 Weather | WeatherAPI + Open-Meteo adapters, fallback engine, cache, failure handling, licence validation | Real forecast on device |
| 4 Location | CoreLocation (When In Use), pre-permission explanation, IP opt-in, manual city/district, persistence, timezone | All permission paths tested |
| 5 Voice | TTS polish, Turkish voice choice, text Q&A, WeatherQueryParser, follow-ups, mic input | Conversation tests pass |
| 6 Clothing | ClothingRecommendationEngine + screen + briefing integration | Rule tests pass |
| 7 Notifications | Rain/wind/severe local notifications, quiet hours, dedup, BGTask refresh | Dedup/quiet-hour tests |
| 8 Morning briefing | Schedule, greeting, summary, notification | — |
| 9 Travel | Destination search, geocoding, dates, comparison, summary | Timezone tests |
| 10 MGM | Authorized source investigation, matcher, banner, warning mode, fallback link | Matcher tests |
| 11 Personality | Styles, lengths, voice speed, subtitle size, greetings | — |
| 12 Release | Full test pass, a11y/security/privacy/perf review, README, App Store metadata, icons | Release checklist |
