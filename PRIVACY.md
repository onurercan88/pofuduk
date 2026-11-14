# Pofuduk — Privacy

| Data | When | Why | Stored | Shared |
|---|---|---|---|---|
| Precise location | Only when the app needs a forecast, after the user agrees to When In Use | Local forecast | Last selected place (on device) | Coordinates sent to the weather provider only |
| Approximate IP location | Only if the user picks it explicitly | Fallback when GPS is denied | Resolved city only | IP seen by the lookup provider |
| Microphone / speech | Only while the user holds the mic button (Phase 5) | Voice questions | Not stored; on-device recognition preferred | Apple, only when on-device recognition isn't available (the user is told) |
| Notifications | Only if enabled by the user | Rain/warning/morning alerts | Preferences on device | None |
| Preferences, cached forecasts | Always | App function | On device (SwiftData/UserDefaults) | None |

- No accounts, no analytics, no ads, no sale of data.
- No background location, no "Always" permission, no continuous microphone.
- A "Delete my data" option clears the cache, history and saved places (Settings, Phase 11).
- Info.plist usage strings: `NSLocationWhenInUseUsageDescription`, `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` (Turkish text in `project.yml`).
