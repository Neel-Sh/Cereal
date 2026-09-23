import SwiftUI

struct RecorderView: View {
    @Bindable var library: LectureLibrary
    @State private var showingLiveTranscript = false

    private var courses: [String] {
        Array(Set(library.lectures.map(\.course).filter { !$0.isEmpty })).sorted()
    }

    var body: some View {
        PageColumn {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("New note", text: $library.draftTitle, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 30, weight: .regular, design: .serif))
                        .lineLimit(1...3)
                        .accessibilityLabel("Note title")

                    GlassEffectContainer(spacing: 6) {
                        FlowLayout(spacing: 6) {
                            MetaChip(symbol: "calendar", text: Date.now.formatted(.dateTime.month(.abbreviated).day()))
                            EditableChip(symbol: "folder", placeholder: "Course", text: $library.draftCourse, suggestions: courses)
                            EditableChip(symbol: "number", placeholder: "Topic", text: $library.draftTopic)
                            TemplateChip(template: $library.draftTemplate)
                            if !library.isRecording && !library.canRetrySaving {
                                AudioSourceChip(mode: $library.captureMode)
                            }
                            calendarChip
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 22)

                NotesEditor(text: $library.draftNotes,
                            placeholder: library.isRecording ? "Jot down what matters — Cereal is listening" : "Write notes")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        .inspector(isPresented: $showingLiveTranscript) {
            LiveTranscriptPanel(transcriber: library.liveTranscriber, isRecording: library.isRecording, isPaused: library.isPaused)
                .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
        }
        .onAppear {
            library.calendar.refresh()
            #if DEBUG
            let scene = DebugSnapshot.scene
            if scene.contains("livefile") {
                showingLiveTranscript = true
                Task { await DebugSnapshot.feedLiveFile(into: library.liveTranscriber) }
            }
            guard scene.contains("rec-") else { return }
            Task {
                await library.startRecording()
                showingLiveTranscript = scene.contains("live")
                if scene.contains("pause") {
                    try? await Task.sleep(for: .seconds(2))
                    library.togglePause()
                    try? await Task.sleep(for: .seconds(2))
                    library.togglePause()
                }
                if scene.contains("stop") {
                    try? await Task.sleep(for: .seconds(4))
                    library.stopRecording()
                }
            }
            #endif
        }
        .onChange(of: [library.draftTitle, library.draftNotes, library.draftCourse, library.draftTopic]) { _, _ in
            library.persistDraft()
        }
        .onChange(of: library.draftTemplate) { _, _ in library.persistDraft() }
    }

    @ViewBuilder
    private var calendarChip: some View {
        if let event = library.calendar.currentEvent, library.draftTitle != event.title {
            Button {
                library.applyCalendarEvent(event)
            } label: {
                Label("Use “\(event.title)”", systemImage: "calendar.badge.clock")
                    .labelStyle(ChipLabelStyle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(.accentColor.opacity(0.3)).interactive(), in: .capsule)
            .help("Name this note after the current calendar event")
        } else if library.calendar.canRequestAccess {
            Button {
                Task { await library.calendar.requestAccess() }
            } label: {
                Label("Connect calendar", systemImage: "calendar.badge.plus")
                    .labelStyle(ChipLabelStyle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .help("Name notes after the class or meeting on your calendar")
        }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 12) {
                    if library.isRecording {
                        RecordingWaveform(level: library.microphoneLevel, tint: library.isPaused ? .secondary : .red)
                    } else if library.canRetrySaving {
                        Button("Retry saving recording") { library.retrySaving() }
                            .buttonStyle(.glassProminent)
                            .disabled(library.isStopping)
                    }
                    if let statusText {
                        Text(statusText)
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }

                    if library.canPause {
                        Button {
                            library.togglePause()
                        } label: {
                            Image(systemName: library.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 36, height: 36)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel(library.isPaused ? "Resume recording" : "Pause recording")
                        .help(library.isPaused ? "Resume (⌘⇧P)" : "Pause (⌘⇧P)")
                        .keyboardShortcut("p", modifiers: [.command, .shift])
                    }

                    if library.isRecording {
                        Button {
                            library.stopRecording()
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.red, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Stop and save recording")
                        .help("Stop and save (⌘Space)")
                        .disabled(library.isStopping)
                        .keyboardShortcut(.space, modifiers: [.command])
                    } else if !library.canRetrySaving {
                        Button {
                            Task { await library.startRecording() }
                        } label: {
                            Label("Start Recording", systemImage: "record.circle")
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                        .tint(.red)
                        .accessibilityLabel("Start recording")
                        .help("Start recording (⌘Space)")
                        .disabled(library.isStarting || library.isRecovering)
                        .keyboardShortcut(.space, modifiers: [.command])
                    }
                }
                .padding(.leading, isIdle ? 5 : 18)
                .padding(.trailing, 5)
                .frame(height: 46)
                .glassEffect(.regular.interactive(), in: .capsule)

                if library.isRecording {
                    Button {
                        showingLiveTranscript.toggle()
                    } label: {
                        Label("Live", systemImage: "captions.bubble")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 16)
                            .frame(height: 46)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .help(showingLiveTranscript ? "Hide live transcript" : "Show live transcript")
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                }
            }
        }
        .padding(.bottom, 22)
        .padding(.top, 8)
        .animation(.snappy, value: library.isRecording)
        .animation(.snappy, value: library.isPaused)
    }

    private var statusText: String? {
        if library.isRecovering { return "Recovering recording…" }
        if library.canRetrySaving { return "Recording needs saving" }
        if library.isStopping { return "Saving…" }
        if library.isRecording { return library.isPaused ? "Paused · \(library.elapsed.formattedDuration)" : library.elapsed.formattedDuration }
        return nil
    }

    private var isIdle: Bool { statusText == nil && !library.isRecording }
}

private struct AudioSourceChip: View {
    @Binding var mode: CaptureMode

    var body: some View {
        Menu {
            Picker("Audio source", selection: $mode) {
                Label("Microphone", systemImage: "mic").tag(CaptureMode.microphone)
                Label("Computer + microphone", systemImage: "desktopcomputer").tag(CaptureMode.online)
            }
            .pickerStyle(.inline)
        } label: {
            Label(mode == .online ? "Computer audio" : "Microphone", systemImage: mode == .online ? "desktopcomputer" : "mic")
                .labelStyle(ChipLabelStyle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .glassEffect(.regular.interactive(), in: .capsule)
        .help("Audio source — use Computer audio for online classes and calls")
    }
}

private struct LiveTranscriptPanel: View {
    let transcriber: LiveTranscriber
    let isRecording: Bool
    let isPaused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isPaused ? Color.secondary : .red)
                    .frame(width: 7, height: 7)
                    .symbolEffect(.pulse)
                Text(isPaused ? "Paused" : "Live transcript")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if transcriber.hasText {
                            let separator = transcriber.finalizedText.isEmpty || transcriber.volatileText.isEmpty ? "" : " "
                            Text("\(transcriber.finalizedText)\(separator)\(Text(transcriber.volatileText).foregroundStyle(.secondary))")
                                .font(.system(size: 14))
                                .lineSpacing(5)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(transcriber.isListening ? "Listening…" : "Starting on-device transcription…")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 20)
                }
                .onChange(of: transcriber.volatileText) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: transcriber.finalizedText) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            }

            Text("A timestamped transcript is made after you stop.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 22)
                .padding(.bottom, 14)
        }
    }
}
