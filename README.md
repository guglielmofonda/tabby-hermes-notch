# Lima

> **Claude Code agents:** the full installation reference lives in [`CLAUDE.md`](./CLAUDE.md). Start there.

A MacBook-notch dictation launcher for a Hermes agent, routed through Telegram. Tap the notch, speak, and your voice is transcribed and delivered as a DM to your Hermes bot — its reply streams back into a scrollable conversation inside the notch.

*"Lima" is the release codename; the app bundle itself is called `Tabby`.*

## What it does

1. You tap the notch pill (or use the menu bar).
2. Lima records 16 kHz mono audio and transcribes it — on-device with **WhisperKit**, or via **OpenAI** (`gpt-4o-transcribe`), or via **Aqua Voice** (Avalon).
3. The transcript is sent as a Telegram DM from **your** account (MTProto, not a bot) to your Hermes bot, with a correlation key appended so replies can be matched out of your DM stream.
4. Hermes responds. Lima picks the matching reply, renders bold / markdown, and shows it in a conversation thread inside the notch.
5. Tap **🎤 Ask more** to continue the thread without leaving the notch.

## Requirements

- macOS 14 (Sonoma) or later, Apple Silicon
- MacBook with a physical notch (M1/M2/M3 Pro or Max). Non-notched Macs fall back to a floating panel — usable but untuned.
- Xcode 16+ (tested on Xcode 26)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- A Telegram account (you log in as yourself via MTProto, not as a bot)
- A Hermes Telegram bot that echoes a correlation key in its final reply
- *(Optional, cloud transcription)* an OpenAI API key for `gpt-4o-transcribe` **or** an Aqua Voice (Avalon) API key

## Install & run

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project Tabby.xcodeproj -scheme Tabby -configuration Debug -derivedDataPath build/ build
open build/Build/Products/Debug/Tabby.app
```

Lima runs as an `LSUIElement` app: no dock icon, just a notch pill and a menu-bar waveform. Use **menu bar → Open Tabby Settings…** to configure.

For an end-to-end install script that a Claude Code agent can follow, see [`CLAUDE.md`](./CLAUDE.md).

## First-run setup wizard

### 1. Telegram API credentials

1. Visit <https://my.telegram.org>, sign in with your phone number, and open **API development tools**.
2. Create an application:
   - **App title / Short name:** anything (e.g. `Lima`)
   - **URL:** blank is fine
   - **Platform:** *Desktop*
3. Paste the resulting **`api_id`** and **`api_hash`** into the wizard.

Credentials land in the Keychain under service `tabby.app`.

### 2. Sign in to Telegram

- Phone number in international format (e.g. `+14155551234`).
- Telegram sends a 5-digit code — usually in-app, not SMS.
- 2FA password if your account has one.

The TDLib session lives at `~/Library/Application Support/Tabby/tdlib_db`. Future launches skip the wizard.

### 3. Connect your Hermes bot

Enter the bot's username (no `@`). Lima calls `searchPublicChat`, resolves the `chat_id`, and persists it in UserDefaults.

## Using Lima

- **Tap the notch pill** — the notch expands to a recording view with a red stop button, rolling waveform, and a timer.
- **Tap the red button** (or anywhere on the expanded notch) to stop and send.
- Lima appends a short correlation key (`respond to this with key: abc123`) to the prompt. Hermes echoes the key so Lima can pick the right reply out of your DM stream.
- Messages shaped like agent tool calls (e.g. `clarify: "…" — …`) are filtered out; only the conversational reply lands in the notch.
- Replies render with **bold / markdown** in a scrollable thread — your bubble on the right, Hermes on the left.
- **🎤 Ask more** records a follow-up in the same conversation; **✕** closes the thread.
- No reply within 2 minutes → Lima surfaces a "No reply from Hermes" error (check Telegram directly).

## Settings (menu bar → Open Tabby Settings…)

| Setting | What it does |
|---|---|
| **Microphone** | Pick any input device. Defaults to the built-in mic; a wrong pick is the usual reason the waveform stays flat. |
| **Transcription engine** | `Local (WhisperKit)`, `Cloud (OpenAI)`, or `Cloud (Aqua Voice)`. |
| **WhisperKit model** | `tiny.en` (~40 MB), `base.en` (~140 MB), or `small.en` (~250 MB, default). First use downloads into the Hugging Face cache — **Download now** lets you preload so you don't eat a 30–120 s wait mid-dictation. |
| **OpenAI API key** | Stored in Keychain. Lima uploads a 16 kHz mono WAV to `/v1/audio/transcriptions` with model `gpt-4o-transcribe`. |
| **Aqua Voice API key + model** | Stored in Keychain. Default model is `avalon-1`; override if you use a different Avalon variant. |
| **Hermes bot username** | The bot Lima DMs. Used for chat_id resolution. |
| **Hermes bot display name** | Override the label above Hermes's bubble in the conversation thread. |
| **Max response lines** | Trim long replies so the notch panel doesn't overflow. |
| **Appended prompt suffix** | Text automatically added to every prompt (e.g. to nudge formatting or tone). |
| **Telegram** | Shows current bot + `chat_id`. *Re-run Telegram setup* wipes TDLib and restarts the wizard. |

## Transcription engines

| Engine | Where it runs | Trade-off |
|---|---|---|
| **WhisperKit** (default) | On-device, via `argmax-oss-swift` | Private + free, but first run downloads a 40–250 MB model; English-only shipped |
| **OpenAI `gpt-4o-transcribe`** | Cloud | Fastest, auto-detects language; requires API key and sends audio to OpenAI |
| **Aqua Voice (Avalon)** | Cloud | Alternative cloud engine, configurable model; requires API key |

Switch engines at any time from Settings — no restart needed.

## Architecture (high level)

```
┌────────────────────────────────── MacBook (Tabby.app) ──────────────────────────────────┐
│                                                                                         │
│  Notch tap → AVAudioEngine (16 kHz mono Float32)                                        │
│                        │                                                                │
│                        ▼                                                                │
│          WhisperKit  ──OR──  OpenAI gpt-4o-transcribe  ──OR──  Aqua Voice               │
│                        │                                                                │
│                        ▼                                                                │
│                transcript + correlation-key                                             │
│                        │                                                                │
│                        ▼                                                                │
│                TDLibKit (MTProto, as your user)                                         │
│                        │                                                                │
└────────────────────────┼────────────────────────────────────────────────────────────────┘
                         ▼
                  Telegram DM to @HermesBot
                         │
                    Hermes replies
                         │
                         ▼
               TDLib `updateNewMessage` stream
                         │
      filter: chat = Hermes AND text ⊇ key AND not shaped like a tool call
                         │
                         ▼
      Notch expands → scrollable conversation with bold / markdown
```

Key libraries:

| Concern | Library | Version |
|---|---|---|
| Telegram MTProto | [Swiftgram/TDLibKit](https://github.com/Swiftgram/TDLibKit) | 1.5.2 (TDLib 1.8.63) |
| Notch UI & pill tap | [MrKai77/DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) | 1.1.0 |
| On-device transcription | [argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift) (`WhisperKit` product) | 0.18.0 |

## Known limits

- Ad-hoc signed build — fine for local dogfood, will need Developer ID + notarization before any external sharing. The embedded `TDLibFramework` XCFramework will need resigning in a Run-Script phase when that happens.
- Fullscreen apps occlude the notch panel (macOS hides the notch area under fullscreen). Expected.
- No conversation history is persisted across app restarts.
- English-only WhisperKit models are shipped (`*.en`). Cloud engines auto-detect language.
- No global hotkey — the notch pill tap (or menu bar) is the only trigger.

## Reset / uninstall

Re-run the wizard only: **menu bar → Reset Telegram setup**.

Full wipe — quit Lima, then:

```sh
rm -rf "~/Library/Application Support/Tabby"
defaults delete tabby.app
security delete-generic-password -s tabby.app
```
