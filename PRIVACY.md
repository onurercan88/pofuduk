# Pofuduk — Privacy

| Data | When | Why | Stored | Shared |
|---|---|---|---|---|
| Precise location | Only when the app needs a forecast, after the user agrees to When In Use | Local forecast | Last selected place (on device) | Coordinates rounded to ~1 km (Apple Weather) / 4 decimals (Open-Meteo fallback) sent to the weather provider only |
| Approximate IP location | Only if the user picks it explicitly | Fallback when GPS is denied | Resolved city only | IP seen by the lookup provider |
| Microphone / speech | Only while the user holds the mic button (Phase 5) | Voice questions | Not stored; on-device recognition preferred | Apple, only when on-device recognition isn't available (the user is told) |
| Notifications | Only if enabled by the user | Rain/warning/morning alerts | Preferences + delivery log on device | None |
| Current-conditions check (~1 km, 2-decimal coordinates) | When the forecast came from a fallback provider | Confirm whether it is raining now | Not stored (10 min in memory) | Apple Weather (WeatherKit) |
| Last used place (~1 km, 2-decimal coordinates) + when it was last confirmed by GPS | After a forecast is shown | Background notification refresh (location is never requested in the background); if a device fix fails, the forecast for this place is shown for up to 12 h, labelled "Son bilinen konum" | On device | Sent to the weather provider only |
| Preferences, cached forecasts | Always | App function | On device (SwiftData/UserDefaults) | None |

- Public privacy policy (Turkish, for the App Store): https://onurercan88.github.io/pofuduk/gizlilik.html (source `docs/gizlilik.html`; keep it in sync with this table).
- No accounts, no analytics, no ads, no sale of data.
- No background location, no "Always" permission, no continuous microphone.
- A "Delete my data" option clears the cache, history and saved places (Settings, Phase 11).
- Info.plist usage strings: `NSLocationWhenInUseUsageDescription`, `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` (Turkish text in `project.yml`).
