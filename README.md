# Cereal

A local-first macOS lecture recorder and study notebook. Record from the microphone or capture computer audio with your microphone for online lectures. Cereal saves audio locally and transcribes it on device after you stop.

## Run

Open `Cereal.xcodeproj` in Xcode 27 or run:

```sh
./script/build_and_run.sh
```

The app targets macOS 27. Choose an audio source, add a course or topic, then use **Start Recording** and **Stop & Save**. **Computer audio** records your microphone and what the Mac is playing as separate tracks, so call transcripts label each passage **Me** or **Them**. It asks for macOS system-audio recording permission (not screen recording).

Cereal lives in the menu bar and keeps running after you close its window. When another app such as Zoom, Teams, Meet in a browser, Slack, or FaceTime starts using the microphone, a small prompt offers to record the call with the Meeting template, named after the calendar event happening now. When the call ends, Cereal asks whether to stop and save, or stops automatically if you turn that on. Settings (⌘,) has call detection, auto-stop, launch at login, and the list of apps Cereal never asks about. The home button opens your saved lectures. In a lecture, play or seek the audio and use the **Transcript** inspector to jump to a timed passage. Older transcripts can be retranscribed from the inspector to add timestamps.

Write your own notes while recording and open **Live** to follow an on-device live transcript. Microphone recordings can be paused and resumed. Pick a template (Lecture, Seminar, Lab, Study group, Office hours, Meeting, Interview) to shape how notes are enhanced, and connect your calendar to name a note after the class or meeting happening now.

After transcription, **Enhance** uses Apple Intelligence on device to write a summary, organized source-linked notes under headings, a checklist of to-dos and deadlines, and study material with flashcards and practice questions. Untitled notes get a title automatically. **Ask anything** (⌘J) opens a conversation with the current note, its course, or all notes, with suggested prompts and follow-up questions; answers link to their source passages. The home screen groups notes by date with pinned notes on top, and filters by course. Copy notes, share them, or export with the transcript to Markdown or PDF from the share menu.

Shortcuts: ⌘N new note, ⌘Space start/stop recording, ⌘⇧P pause or play, ⌘1–3 switch between My notes, Enhanced, and Study, ⌘E enhance, ⌘J ask, ⌘⇧C copy notes.

Audio, drafts, and the lecture index are stored in the app's sandboxed Application Support folder under `Cereal/`. If a recording is interrupted, Cereal restores the draft notes and attempts to recover any finalized audio on the next launch. The first transcription may download Apple's on-device speech model. Enhanced notes and question answering require Apple Intelligence to be enabled and available on the Mac. Call recordings keep the microphone and computer-audio tracks next to the mixed recording so they can be retranscribed with speaker labels.
# Cereal
