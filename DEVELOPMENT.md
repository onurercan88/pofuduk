# Pofuduk — Development

## Windows (current dev machine)
Only `PofudukCore` (domain logic) builds here.
```
scripts\swift-core.cmd build
scripts\swift-core.cmd test
```
The script loads the MSVC x64 environment (`vcvars64.bat`) and `SDKROOT`, which `swift` needs on Windows.
Requires the Swift toolchain (`winget install Swift.Toolchain`) plus Visual Studio 2022 with the MSVC x64 tools and the Windows 11 SDK.

## macOS (required for the iOS app)
1. Xcode 15+ (iOS 17 SDK), and `brew install xcodegen`.
2. `xcodegen generate` in the repo root → `Pofuduk.xcodeproj`.
3. Open it and run the `Pofuduk` scheme on an iPhone simulator.
4. Tests: `xcodebuild test -scheme Pofuduk -destination 'platform=iOS Simulator,name=iPhone 15'`, and `swift test` in `PofudukCore`.

## Configuration
- No API keys yet (demo data only). Phase 3 adds `Config/Secrets.xcconfig` (gitignored) and a Keychain-based key store. Keys never go into source.
- Turkish TTS needs a tr-TR voice. Simulator: Settings › Accessibility › Spoken Content › Voices › Türkçe.

## Conventions
- Engines are pure, with inputs injected (`now`, `Calendar`, thresholds).
- Mock data only in `PofudukCore/Mock`, used by previews, tests and the labelled demo mode.
