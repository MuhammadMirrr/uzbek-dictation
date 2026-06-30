# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A system-wide Uzbek speech-to-text dictation app for macOS (Apple Silicon only). Press **⌃⌥D** anywhere, speak Uzbek, and the transcription is typed into the focused field via clipboard + ⌘V. Fully offline — `islomov/rubaistt_v2_medium` (a Whisper fine-tune) runs locally through whisper.cpp with Metal. It's a menu-bar accessory app (`LSUIElement`), ad-hoc signed (no Apple Developer cert).

Note: comments, log strings, and user-facing text are in **Uzbek**. Match that when editing existing code.

## Build & run

There is no test suite, linter, or package manager. Everything is shell scripts + a single Swift compile.

```bash
./setup.sh          # full one-time install: deps → whisper.cpp (Metal) → model → app → login agent
src/build.sh        # rebuild ONLY the app (use this iterating on dictate.swift / whisper_bridge.c)
```

`src/build.sh` requires whisper.cpp static libs to already exist at `whisper.cpp/build-static/` — `setup.sh` produces them. The compiled `.app` lands at `~/Applications/RubaiSTT Dictation.app`. To test changes, run `src/build.sh` then relaunch that app (it's loaded at login via `~/Library/LaunchAgents/com.rubaistt.dictation.plist`).

The model file the app reads is `~/rubai-stt/models/ggml-rubaistt.bin` (q8_0). `setup.sh` fetches a prebuilt one from the GitHub release, falling back to `scripts/convert_model.sh` (downloads from HuggingFace, converts to f16) + `whisper-quantize` → q8_0.

## Architecture

Three layers, FFI-bridged:

1. **`src/whisper_bridge.c` / `.h`** — a tiny C shim over whisper.cpp. Holds one global `whisper_context`. Four functions: `rubai_load` / `rubai_unload` / `rubai_transcribe` / `rubai_free_str`. Transcription params are hardcoded here: language `uz`, beam search (size 5), no timestamps, GPU + flash attention on. `rubai_transcribe` mallocs the result string; **the Swift caller must `rubai_free_str` it**.

2. **`src/Bridging.h`** — exposes the C header to Swift (`-import-objc-header`). The C functions become globally callable Swift symbols.

3. **`src/dictate.swift`** — the whole app in one file, organized by `// MARK:`:
   - `Whisper` (singleton) — wraps the C bridge on a serial dispatch queue; lazy-loads the model on first transcribe; thread count = `activeProcessorCount - 2` (min 4).
   - `Recorder` — `AVAudioEngine` mic capture, converts hardware format → 16kHz mono float32. **Creates a fresh `AVAudioEngine` on every `start()`** to avoid a stuck-state bug after login / device change.
   - `Overlay` — borderless non-activating `NSPanel` HUD that shows recording/transcribing status without stealing focus.
   - `Inserter` — sets clipboard, posts a synthetic ⌘V `CGEvent`, then restores the old clipboard after 0.6s. **Requires Accessibility permission** to send the keystroke.
   - `HotKey` — Carbon global hotkey (⌃⌥D) → posts `.rubaiHotkey` notification.
   - `AppDelegate` — menu-bar status item, wires hotkey→`toggle()`. `toggle()` flips record/stop; on stop it transcribes then inserts. After each transcription, an idle timer unloads the model from RAM after **180s**.

### Data flow per dictation
⌃⌥D → `AppDelegate.toggle` → `Recorder.start` (mic float32 buffer) → ⌃⌥D again → `Recorder.stop` returns `[Float]` → `Whisper.transcribe` (off main thread) → `rubai_transcribe` (Metal) → text back on main thread → `Inserter.insert` (clipboard + ⌘V).

## Things to know before editing

- **Two macOS permissions gate functionality**: Microphone (`NSMicrophoneUsageDescription`, requested at first record) and Accessibility (for the synthetic ⌘V — checked via `AXIsProcessTrusted`). The launch agent runs the app via `/usr/bin/open` specifically so TCC permission bindings attach correctly.
- **The C bridge owns the only whisper context** — it's a process-global, not per-instance. Loading is idempotent; `unload` is called on quit, terminate, and the idle timer.
- The app bundle's `Info.plist` and ad-hoc `codesign` (with `src/entitlements.plist`: audio-input + allow-jit) are generated inside `src/build.sh` — edit them there, not as standalone files.
- `whisper.cpp/`, `*.bin`, `.venv/`, `.assets/`, and build artifacts are gitignored — they're fetched/built, never committed.
