# Tabby

A MacBook-notch dictation launcher for a Hermes agent running on a Mac Mini, routed through Telegram.

Tap the notch → speak → Tabby transcribes (local WhisperKit *or* OpenAI Whisper) → sends the prompt as a DM from your own Telegram account to your Hermes bot → shows Hermes's reply in the notch as a scrollable conversation. Tap **Ask more** to keep chatting.

## Requirements

- macOS 14 (Sonoma) or later, Apple Silicon
- MacBook with a physical notch (M1 / M2 / M3 Pro or Max). Non-notched Macs get the "floating" fallback but it hasn't been tuned.
- Xcode 16+ (tested on Xcode 26)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- A Telegram account (your own — Tabby logs in via MTProto, not via a bot)
- A Hermes Telegram bot that listens to your DMs and echoes a correlation key in its final reply
- *(Optional, for cloud transcription)* an OpenAI API key with access to `gpt-4o-transcribe`

## Build & run

From the repo root:

```sh
xcodegen generate
xcodebuild -project Tabby.xcodeproj -scheme Tabby -configuration Debug -derivedDataPath build/ build
open build/Build/Products/Debug/Tabby.app
```

Tabby runs as `LSUIElement=YES`: no dock icon, just a notch pill and a menu-bar waveform. Menu bar → **Open Tabby Settings…** to reach configuration.

## First run — setup wizard

### 1. Telegram API credentials (one-time)

1. Go to <https://my.telegram.org> and sign in with your phone number.
2. Click **API development tools**.
3. Create a new application:
   - **App title / Short name:** anything (e.g. `Tabby`)
   - **URL:** blank is fine
   - **Platform:** *Desktop*
4. Copy the resulting **`api_id`** (digits) and **`api_hash`** (hex) and paste them into Tabby's first wizard step.

They're stored in the macOS Keychain under service `com.guglielmofonda.Tabby`.

### 2. Sign in to Telegram

Tabby sends messages *as you*, so it needs to authenticate against your real account.

- Enter your phone number in international format (e.g. `+14155551234`).
- Telegram sends a 5-digit code — usually as an in-app message in Telegram Desktop / mobile, not as SMS.
- If your account has 2-step verification enabled, enter your Telegram password.

The TDLib session is persisted on disk under `~/Library/Application Support/Tabby/tdlib_db`. Subsequent launches skip the wizard.

### 3. Connect your Hermes bot

Enter the bot's username (without the `@`) when prompted. Tabby calls `searchPublicChat`, resolves the `chat_id`, and pins it in `UserDefaults`.

## Using Tabby

- **Tap the notch pill** → expanded recording view with a red stop button, rolling RMS waveform, and a timer.
- **Tap the red button** (or anywhere on the expanded notch) to stop and send.
- Tabby appends a short correlation key (`respond to this with key: abc123`) to the prompt before sending. Hermes echoes the key in its reply so Tabby can pick the right message out of the DM stream.
- Messages that look like agent tool calls (e.g. `clarify: "…" — …`) are skipped; only the conversational reply lands in the notch.
- The response shows as a **scrollable thread** — your bubble on the right, Hermes on the left. Use **🎤 Ask more** to record a follow-up, or **✕** to close the thread.
- No response within 2 minutes → Tabby surfaces a "No reply from Hermes" error (check Telegram directly).

## Settings (menu bar → Open Tabby Settings…)

- **Microphone** — pick any input device. Defaults to the built-in MacBook mic (picking the wrong input is usually why the waveform goes flat).
- **Transcription engine** — `Local (WhisperKit)` or `Cloud (OpenAI Whisper)`.
- **WhisperKit model** — `tiny.en` (~40 MB), `base.en` (~140 MB), `small.en` (~250 MB, default). First use downloads into the Hugging Face cache; a **Download now** button lets you preload before dictating so you don't eat a 30–120 s wait mid-flow.
- **OpenAI API key** — stored in Keychain. Tabby uploads a 16 kHz mono WAV to `/v1/audio/transcriptions` with model `gpt-4o-transcribe`.
- **Telegram** — shows current bot + `chat_id`. *Re-run Telegram setup* wipes the TDLib database and takes you back to step 1 of the wizard.

## Architecture (high level)

```
┌────────────────────────────────── MacBook (Tabby.app) ──────────────────────────────────┐
│                                                                                         │
│  Notch tap → AVAudioEngine (16 kHz mono Float32) → WhisperKit OR OpenAI Whisper         │
│                                                          │                              │
│                                                       transcript + correlation-key      │
│                                                          ▼                              │
│                                              TDLibKit (MTProto as your user)            │
│                                                          │                              │
└──────────────────────────────────────────────────────────┼──────────────────────────────┘
                                                           ▼
                                                    Telegram DM to @HermesBot
                                                           │
                                                      Hermes replies
                                                           │
                                                           ▼
                                              TDLib `updateNewMessage` stream
                                                           │
                                            filter: chat = Hermes AND text ⊇ key AND
                                                    not shaped like a tool call
                                                           ▼
                                              Notch expands with conversation view
```

Key libraries:

| Concern | Library | Version |
|---|---|---|
| Telegram MTProto | [Swiftgram/TDLibKit](https://github.com/Swiftgram/TDLibKit) | 1.5.2 (TDLib 1.8.63) |
| Notch UI | [MrKai77/DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) | 1.1.0 |
| On-device transcription | [argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift) (`WhisperKit` product) | 0.18.0 |

## Known limits

- Ad-hoc signed build — fine for local dogfood, will need Developer ID + notarization before any external sharing. The embedded `TDLibFramework` XCFramework will need resigning in a Run-Script phase when that happens.
- Fullscreen apps occlude the notch panel (macOS hides the notch area under fullscreen). Expected.
- No conversation history is persisted across app restarts.
- English-only WhisperKit models are shipped (`*.en`). Cloud Whisper auto-detects language.
- No global hotkey, no conversation streaming, no non-notch fallback polish.

## Reset / uninstall

- Menu bar → **Reset Telegram setup** wipes TDLib state and prompts wizard again.
- To fully reset: quit Tabby, then
  ```sh
  rm -rf "~/Library/Application Support/Tabby"
  defaults delete com.guglielmofonda.Tabby
  security delete-generic-password -s com.guglielmofonda.Tabby
  ```
