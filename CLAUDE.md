# CLAUDE.md — Installation reference

Installation reference for Claude Code agents working on this repo. Humans: see [README.md](./README.md).

## Project

macOS notch dictation app (Swift 5.10 / SwiftUI). Captures mic → transcribes (on-device WhisperKit, OpenAI, or Aqua Voice) → sends as a Telegram DM from the user's own account to a Hermes bot. App bundle name: `Tabby`. Release codename: `Lima`.

## Hardware & OS

- Apple Silicon Mac (M1/M2/M3/M4)
- macOS 14.0 (Sonoma) or later
- MacBook with a physical notch for the primary UI; non-notched Macs get an untuned fallback

## Tooling

- Xcode 16+ (tested on Xcode 26)
- XcodeGen: `brew install xcodegen`
- Swift 5.10 (shipped with Xcode 16+)
- No Node, no npm, no test runner

## Install & build

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project Tabby.xcodeproj -scheme Tabby -configuration Debug -derivedDataPath build/ build
open build/Build/Products/Debug/Tabby.app
```

- `xcodegen generate` reads `project.yml` and produces `Tabby.xcodeproj`.
- `xcodebuild` auto-resolves SPM packages.
- Scheme: `Tabby`. Product bundle id: `tabby.app`.

## SPM dependencies (auto-resolved)

- `DynamicNotchKit` (MrKai77) from `1.1.0` — notch UI + pill tap
- `TDLibKit` (Swiftgram) exact `1.5.2-tdlib-1.8.63-a82128ab` — Telegram MTProto
- `ArgmaxOSS` → product `WhisperKit` from `0.18.0` — on-device transcription

## Entitlements (`Tabby/Tabby.entitlements`)

- `com.apple.security.app-sandbox`: `false`
- `com.apple.security.device.audio-input`: `true`
- `com.apple.security.cs.disable-library-validation`: `true` (required for the embedded TDLib XCFramework)
- `com.apple.security.network.client`: `true`

## Human-gated secrets — STOP and ask the user

Claude Code cannot automate any of the following. The app collects them via its first-run wizard. Do not try to script them:

1. **Telegram `api_id` + `api_hash`** — user creates an application at <https://my.telegram.org> → *API development tools* (platform: *Desktop*).
2. **Telegram phone auth** — phone number in international format. Telegram sends a 5-digit code via Telegram Desktop / mobile (not SMS). 2FA password if enabled.
3. **Hermes bot username** — e.g. `HermesBot` (no `@`). App resolves chat_id via `searchPublicChat`.
4. *(Optional)* **OpenAI API key** — for cloud transcription via model `gpt-4o-transcribe`.
5. *(Optional)* **Aqua Voice (Avalon) API key + model name** — default model is `avalon-1`.

All land in Keychain service `tabby.app` or UserDefaults domain `tabby.app`.

## First-run flow (app handles automatically)

1. Launch the built app.
2. Wizard step 1: paste `api_id` + `api_hash`.
3. Wizard step 2: phone → auth code → (optional) 2FA password.
4. Wizard step 3: Hermes bot username.
5. macOS prompts for microphone access on first recording — user must approve.
6. TDLib session persists; subsequent launches skip the wizard.

## Persistence paths

- TDLib session: `~/Library/Application Support/Tabby/tdlib_db/`
- Keychain service: `tabby.app`
- UserDefaults domain: `tabby.app`

## Reset / uninstall

Wizard only: menu bar → **Reset Telegram setup**.

Full wipe:

```sh
rm -rf ~/Library/Application\ Support/Tabby
defaults delete tabby.app
security delete-generic-password -s tabby.app
```

## Repo layout

- `project.yml` — XcodeGen source of truth (versions, deps, entitlements path)
- `Tabby/TabbyApp.swift` — app entry, AppDelegate, notch lifecycle
- `Tabby/State/` — `AppState.swift` (recording → transcription → send flow), `AuthStep.swift` (wizard state machine)
- `Tabby/Views/` — SwiftUI screens; `Views/Setup/` for the wizard
- `Tabby/Services/` — `TelegramClient.swift`, `AudioRecorder.swift`, `LocalTranscriber.swift`, `CloudTranscriber.swift`, `SettingsStore.swift`, `CorrelationKey.swift`, `AudioDeviceRegistry.swift`
- `Tabby/Info.plist`, `Tabby/Tabby.entitlements` — bundle config

## Verification

No test suite, no CI. Validate a change by:

1. `xcodegen generate && xcodebuild -project Tabby.xcodeproj -scheme Tabby -configuration Debug -derivedDataPath build/ build` succeeds.
2. `open build/Build/Products/Debug/Tabby.app`.
3. Tap the notch pill → record → confirm a Telegram DM is sent to the Hermes bot and the reply renders in the notch.

## Notes

- `LSUIElement` app: no dock icon. Menu-bar waveform + notch pill only.
- Ad-hoc signed Debug builds. No Developer ID / notarization configured; distribution needs a Run-Script phase to resign `TDLibFramework`.
- `build/` and `Tabby.xcodeproj/` are gitignored regenerables.
