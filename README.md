# Tabby

A MacBook-notch dictation launcher for a Hermes agent running on a Mac Mini, routed through Telegram.

Tap the notch → speak → Tabby transcribes → sends a DM from your own Telegram account to your Hermes bot → shows Hermes's reply in the notch.

## Status

Phase 0 — skeleton. No Telegram, no audio yet. Just an empty notch.

## Build

Requirements:

- macOS 14+ on an Apple Silicon MacBook with a physical notch
- Xcode 16+ (tested on Xcode 26)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

From the repo root:

```sh
xcodegen generate
open Tabby.xcodeproj
```

…or from CLI:

```sh
xcodebuild -project Tabby.xcodeproj -scheme Tabby -configuration Debug build
```

## Architecture

See `/Users/guglielmofonda/.claude/plans/system-instruction-you-are-working-peppy-hedgehog.md` (in progress — will move to `docs/plan.md` before merge).
