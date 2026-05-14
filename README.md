# WhisperDictate

A small, private dictation tool for macOS. Press **⌘⌥D**, speak, press it again — the transcribed text lands in your clipboard. No cloud, no account, no agreements.

Under the hood it runs [whisper.cpp](https://github.com/ggerganov/whisper.cpp) as a local subprocess. That's the only "engine" piece; everything else — the menu-bar UI, the hotkey, the audio capture, the model management — is plain Swift in this repo.

---

## Why I built this

I started writing WhisperDictate for myself. Apple's built-in Dictation kept asking me to accept a long agreement and, depending on settings, would route my voice to Apple's servers. I wanted something that just worked on my own Mac, without telemetry, accounts, or surprises.

Once I had something usable, I realised other people probably want the same thing, so I cleaned it up and put it here.

The project also doubled as a hands-on test of my own skills with **Claude Code**—just gave it a try—and, more broadly, as a way to experience agentic software development. I used Claude Code as a pair programmer throughout: discussing trade-offs, generating boilerplate, catching bugs, and iterating on UI.

---

## What you get

- **Global hotkey:** ⌘⌥D from any app. Press once to start, press again to stop and transcribe.
- **Menu-bar only:** No Dock icon, no main window. A microphone glyph that turns red and shows a blinking `● REC` while recording.
- **Three one-click model downloads:** from inside the app: Base (multilingual, 142 MB), Base English-finetuned (142 MB), Large v3 Turbo (multilingual, 1.5 GB). The exact download URL appears in each menu item's tooltip.
- **Drop-in custom models:** Put any ggml `.bin` file in `~/Documents/WhisperDictate/Models/` and it shows up in the menu automatically.
- **Language hint** for English / Turkish / German / Auto, passed to whisper-cli to improve short-clip accuracy.
- **Clipboard output** plus a small frosted toast with a preview. Paste anywhere with ⌘V.
- **Microphone is the only permission** you'll ever be asked for. No Accessibility, no Input Monitoring, no Notifications, no Screen Recording.

---

## Quick start

```bash
git clone https://github.com/<your-handle>/WhisperDictate.git
cd WhisperDictate
bash scripts/build-app.sh
cp -R dist/WhisperDictate.app /Applications/
open /Applications/WhisperDictate.app
```

First launch:

1. Right-click the app → **Open** to bypass the unsigned-developer warning (the build is ad-hoc signed; one-time approval).
2. Click the mic icon in the menu bar → **Model** → pick a download. Base is a good starting point — small, fast, multilingual.
3. Wait for the download to finish.
4. Press **⌘⌥D**, say something, press **⌘⌥D** again. The text is in your clipboard.

> macOS uses ⌘⌥D to hide the Dock by default. Disable that under **System Settings → Keyboard → Keyboard Shortcuts → Launchpad & Dock** so it doesn't fire alongside dictation.

---

## Picking a model

| Model | Size | Languages | Speed | Notes |
| :--- | :--- | :--- | :--- | :--- |
| **Base (multilingual)** | 142 MB | All | Fast | Good default for most people |
| **Base English-only** | 142 MB | English | Fast | Slightly more accurate on English than the multilingual base |
| **Large v3 Turbo** | 1.5 GB | All | Slower | Best accuracy; worth it for accents or technical jargon |

You can install more than one and switch between them in the menu. To grab models that aren't in the curated list, use the menu's **Browse All whisper.cpp Models…** link, download the `.bin` file from there, and drop it into `~/Documents/WhisperDictate/Models/` — it'll appear in the menu next time you open it.

---

## System requirements

- **macOS 13** (Ventura) or later
- **Apple Silicon** (M1 and up). Intel Macs work after rebuilding for x86_64 — see [Build from source](#build-from-source).
- **5 MB** for the app itself, plus 142 MB – 1.5 GB per model you install
- **Internet** only when downloading a model. Zero network traffic afterwards.

---

## Privacy, concretely

A few claims I made above, with the receipts:

- **No telemetry.** Grep the codebase — there's no analytics SDK, no crash reporter, no usage tracking. The only network code is the one model downloader, and it only fires when you click a Download menu item.
- **Audio is ephemeral.** Each recording is written to `/tmp/WhisperDictate-<uuid>.wav` and deleted as soon as transcription finishes (or as soon as the 180-second timeout fires). On every launch, any leftover WAV files from a previous crash get wiped.
- **Logs don't contain your speech.** The log records *that* a transcription happened and how many characters it produced — not the transcribed text, not clipboard contents, not file paths beyond filenames.
- **Toasts are not OS notifications.** They're drawn as in-process panels, which is why the app doesn't need a Notifications permission. Your transcribed text never leaves the process.
- **Verify it yourself.** While using the app, run `lsof -i -n -P | grep WhisperDictate` — the only connection you'll ever see is to `huggingface.co`, and only during a download.

---

## The menu bar, top to bottom

```
Idle  ·  press ⌘⌥D to start
────────────────────────────────────
Start Dictation                ⌘⌥D
────────────────────────────────────
Language                       ▸  EN / TR / DE / Auto
Model                          ▸  installed + downloadable models
Open Log
Clear Log…
About WhisperDictate
────────────────────────────────────
Quit
```

The status line at the top updates live — *Idle*, *Recording*, *Transcribing*, or an error string.

The log lives at `~/Library/Application Support/WhisperDictate/logs/whisper-dictate.log` and rotates automatically at 1 MB. You can also open it from the menu.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| ⌘⌥D does nothing | macOS's Dock-hiding shortcut is conflicting. Disable it in *Keyboard → Keyboard Shortcuts → Launchpad & Dock → Turn Dock Hiding On/Off*. |
| No microphone prompt ever appeared | Launch `WhisperDictate.app`, not the raw binary. TCC attaches permissions to the bundle, not the executable. |
| Mic was denied earlier and now nothing works | The denial dialog has an *Open Settings* button. Or go to *System Settings → Privacy & Security → Microphone* and enable WhisperDictate. |
| "Transcription took longer than 180 seconds" | Long recording on a large model. Switch to Base, or shorten what you record. |
| Garbled text | Set the right language in the menu, or re-download the model in case the file is corrupt. |
| App seems frozen on launch | Check the log — any startup error is in the most recent lines with an ISO-8601 timestamp. |

---

## Limitations

Things WhisperDictate doesn't do today — listed honestly so you know what you're getting:

- **No live captioning.** It's a discrete start/stop/transcribe cycle, not a streaming overlay.
- **No voice-activity detection.** You decide when to stop. If you forget, the 60-second cap saves you.
- **Hotkey is hardcoded.** Currently ⌘⌥D. There's no UI to rebind it — change the constants in `HotkeyListener.swift` and rebuild if you need another combo.
- **No Intel binary by default.** Build script targets arm64. Add `--arch x86_64` to the swift build line for Intel.
- **Ad-hoc signed, not notarized.** Gatekeeper shows "unidentified developer" on first launch (right-click → Open works around it). Notarization needs a paid Apple Developer account.
- **No transcription history.** Each result goes to the clipboard and the app forgets about it. By design — the privacy story is much harder to make once you start persisting transcripts.
- **One recording at a time.** No queue, no batch mode.
- **System sleep cancels in-progress recordings.** Intentional — the audio engine doesn't survive sleep/wake cleanly.

---

## Build from source

```bash
# Prerequisites: macOS 13+, Xcode CLT (xcode-select --install), CMake (brew install cmake)

bash scripts/build-app.sh
```

The script generates the app icon, builds `whisper-cli` from the vendored source, compiles the Swift package in release mode, assembles `dist/WhisperDictate.app`, and ad-hoc codesigns it. The first build takes a few minutes (whisper.cpp is the long part); subsequent builds are quick because each step is idempotent.

For a universal binary, edit `scripts/build-app.sh` and add `--arch x86_64` to the `swift build` line — it currently builds arm64 only.

If you want to point the in-app downloader at a mirror or proxy:

```bash
WHISPER_DICTATE_MODEL_URL=https://your-mirror.example.com/ggml-base.bin open /Applications/WhisperDictate.app
```

---

## License

MIT. See [LICENSE](LICENSE).
