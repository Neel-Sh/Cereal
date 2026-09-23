# Cereal

A local-first macOS lecture recorder and study notebook. Record from the microphone or capture computer audio with your microphone for online lectures. Cereal saves audio locally and transcribes it on device after you stop.

## Run

Open `Cereal.xcodeproj` in Xcode 27 or run:

```sh
./script/build_and_run.sh
```

The app targets macOS 27. Choose an audio source, add a course or topic, then use **Start Recording** and **Stop & Save**. Computer audio capture asks for macOS screen-recording permission. The home button opens your saved lectures. In a lecture, play or seek the audio and use the **Transcript** inspector to jump to a timed passage. Older transcripts can be retranscribed from the inspector to add timestamps.

Write your own notes while recording. After transcription, **Enhance notes** uses Apple Intelligence on device to create editable, source-linked notes, concepts, flashcards, and practice questions. **Ask Lectures** answers questions across one lecture, a course, or the whole library and links to source passages. Search titles, courses, topics, notes, and transcripts; filter the library by course. Export a lecture with its notes, study material, and transcript to Markdown or PDF.

Audio and the lecture index are stored in the app's sandboxed Application Support folder under `Cereal/`. The first transcription may download Apple's on-device speech model. Enhanced notes and question answering require Apple Intelligence to be enabled and available on the Mac. Online capture temporarily records a low-resolution video while macOS mixes computer and microphone audio; Cereal extracts the audio and deletes the temporary video after a successful save.
# Cereal
