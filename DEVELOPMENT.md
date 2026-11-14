# Pofuduk — Development

## Windows (current dev machine)
Only `PofudukCore` (domain logic) builds here.
```
scripts\swift-core.cmd build
scripts\swift-core.cmd test
```
The script loads the MSVC x64 environment (`vcvars64.bat`) and `SDKROOT`, which `swift` needs on Windows.
Requires the Swift toolchain (`winget install Swift.Toolchain`) plus Visual Studio 2022 with the MSVC x64 tools and the Windows 11 SDK.

## Console demo (Windows, live data)
Pofuduk's engines in a terminal, with real Open-Meteo data. No Mac or iPhone needed.
```
.\scripts\pofuduk.cmd Ankara
.\scripts\pofuduk.cmd İzmir --stil sakaci --ses
.\scripts\pofuduk.cmd Bursa --soru "yarin yagmur var mi"
```
(In PowerShell the leading `.\` is required; in cmd.exe `scripts\pofuduk.cmd` also works.)
- Shows: current weather, the briefing (the morning greeting between 07:30 and noon), the 12-hour forecast, "Bugün Ne Giysem?", the notifications that would be planned, and the MGM status. Then you can ask questions until you type `çık`.
- `--ses` reads answers aloud with the Windows Turkish voice "Microsoft Tolga" (`scripts\speak.ps1`). `--kisa` gives the short briefing. `--stil samimi|sakaci|sakin` picks the tone.
- Questions can be typed without Turkish letters ("yarin hava nasil").

## macOS (required for the iOS app)
1. Xcode 15+ (iOS 17 SDK), and `brew install xcodegen`.
2. `xcodegen generate` in the repo root → `Pofuduk.xcodeproj`.
3. Open it and run the `Pofuduk` scheme on an iPhone simulator.
4. Tests: `xcodebuild test -scheme Pofuduk -destination 'platform=iOS Simulator,name=iPhone 15'`, and `swift test` in `PofudukCore`.

## CI screenshots
Each CI run uploads a `screenshots` artifact with every demo scenario. Download it with `gh run download <run-id> -n screenshots`. Locally, the launch argument `-pofuduk.demoScenario <sunny|rainyAfternoon|stormy|snowy|cloudy|windy>` picks the scenario.

## Configuration
- No API keys yet (demo data only). Phase 3 adds `Config/Secrets.xcconfig` (gitignored) and a Keychain-based key store. Keys never go into source.
- Turkish TTS needs a tr-TR voice. Simulator: Settings › Accessibility › Spoken Content › Voices › Türkçe.

## Conventions
- Engines are pure, with inputs injected (`now`, `Calendar`, thresholds).
- Mock data only in `PofudukCore/Mock`, used by previews, tests and the labelled demo mode.
