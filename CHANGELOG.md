# Changelog

All notable changes to WhisperDictate will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — Initial public release

### Added
- Menu-bar app (LSUIElement, no Dock icon) triggered by **⌘⌥D** via Carbon `RegisterEventHotKey` — no Accessibility permission required.
- Local transcription using vendored [whisper.cpp](https://github.com/ggerganov/whisper.cpp), spawned as a subprocess with a 180-second timeout guard.
- Dynamic Model submenu that scans `~/Documents/WhisperDictate/Models/` for `.bin` files, shows file sizes, and lets users drop additional models manually.
- **One-click downloads for three models** from the official HuggingFace repo: `ggml-base.bin` (~142 MB), `ggml-base.en.bin` (~142 MB), and `ggml-large-v3-turbo.bin` (~1.5 GB). Each menu item shows its source URL as a tooltip.
- "Browse All whisper.cpp Models…" entry that opens the upstream HuggingFace page for any model not in the curated catalog.
- SHA-256 logged for every downloaded model so users can verify integrity manually.
- `WHISPER_DICTATE_MODEL_URL` environment variable to override the base model download URL for users behind mirrors.
- Language picker (English / Turkish / German / Auto) persisted in UserDefaults and passed to `whisper-cli -l`.
- Frosted-glass HUD toast for status messages (no notification entitlement required).
- Custom About panel with dynamic version, clickable GitHub link, and `lock.shield.fill` privacy badge.
- Blinking `● REC` indicator next to the menu-bar icon during recording.
- Append-only log file at `~/Library/Application Support/WhisperDictate/logs/whisper-dictate.log` with automatic rotation at 1 MB.

### Security
- **Single TCC permission**: Microphone only. No Accessibility, Input Monitoring, Notifications, or Screen Recording.
- Audio files in `/tmp` are deleted immediately after transcription and any stragglers from crashed sessions are cleaned up at launch.
- No telemetry, no analytics, no crash reporting, no network calls except the explicit model download.

### Robustness
- Friendly error messages for common download failures (no internet, timed out, host unreachable).
- Explicit 600-second `URLSession` resource timeout — large model downloads on slow links never hang silently.
- Granular error classification for whisper-cli failures (model invalid vs. audio invalid vs. timed out).
- Sleep/wake handler stops an in-progress recording when the system goes to sleep.
- Second-instance detection: a duplicate launch shows an alert and quits rather than fighting for the hotkey.
- "Open Settings" deep-link in the microphone-denied alert.
