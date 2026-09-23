# Contributing

Thanks for helping with Cereal. Small changes to copy, screenshots, and docs are especially welcome.

## Build and run

Cereal builds from source with Xcode 27 on macOS 27.

```bash
git clone https://github.com/Neel-Sh/Cereal.git
cd Cereal
./script/build_and_run.sh
```

The script stops a running Cereal process, builds the Debug app with `xcodebuild`, and opens it. Other modes:

| Command | What it does |
| --- | --- |
| `./script/build_and_run.sh --verify` | Launch and check that the process is running |
| `./script/build_and_run.sh --debug` | Build and attach lldb |
| `./script/build_and_run.sh --logs` | Launch and stream the process log |
| `./script/build_and_run.sh --telemetry` | Launch and stream the app's subsystem log |

## Permissions

The first launch asks macOS for the access each feature needs:

- **Microphone**, for an in-person recording. System Settings → Privacy & Security → Microphone.
- **System Audio Recording Only**, for computer audio on a call or online class. This capture does not record video.
- **Calendar**, only if you connect it so a new note can offer the current event title.
- **Apple Intelligence**, for enhanced notes and Ask. Recording, transcription, playback, search, and export do not require it.

If a prompt was denied, turn the permission back on in System Settings and launch Cereal again. Open at login is optional and may also need approval under System Settings → General → Login Items.

## Good first issues

- Tighten a sentence in the README or in the app's copy
- Refresh a screenshot in `docs/screenshots/` when the UI changes
- Clarify a setup step, permission, or keyboard shortcut in the docs
- Fix a typo or an unclear empty-state message

Look for issues labeled `good first issue`, or open one if you notice a small gap.

## Releases

There is no downloadable build yet. A later GitHub Release can ship a notarized DMG. See [RELEASES.md](RELEASES.md). Until then, build from source with the script above.

## Conduct and security

This project uses the [Contributor Covenant](CODE_OF_CONDUCT.md). Report vulnerabilities privately, as described in [SECURITY.md](SECURITY.md).
