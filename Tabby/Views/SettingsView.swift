import SwiftUI
import CoreAudio
import AVFoundation

struct SettingsView: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject var transcriber: LocalTranscriber = AppState.shared.localTranscriber

    @State private var engine: SettingsStore.TranscriptionEngine = SettingsStore.transcriptionEngine
    @State private var model: String = SettingsStore.whisperKitModel
    @State private var openAIKey: String = SettingsStore.openAIKey ?? ""
    @State private var maxResponseLines: Int = SettingsStore.maxResponseLines

    private let modelOptions: [(label: String, value: String)] = [
        ("tiny.en — fastest (~40 MB)", "openai_whisper-tiny.en"),
        ("base.en — balanced (~140 MB)", "openai_whisper-base.en"),
        ("small.en — best accuracy (~250 MB)", "openai_whisper-small.en"),
    ]

    @State private var inputDevices: [AudioInputDevice] = AudioDeviceRegistry.listInputDevices()
    @State private var selectedInput: AudioDeviceID = SettingsStore.selectedInputDeviceID
        ?? AudioDeviceRegistry.builtInInput()?.id
        ?? AudioDeviceRegistry.systemDefaultInputID()
        ?? 0
    @State private var micAuthStatus: AVAuthorizationStatus =
        AVCaptureDevice.authorizationStatus(for: .audio)

    var body: some View {
        Form {
            Section("Microphone") {
                LabeledContent("Mic authorization") {
                    micAuthControl
                }

                Picker("Input", selection: $selectedInput) {
                    ForEach(inputDevices, id: \.id) { d in
                        Text(labelFor(d)).tag(d.id)
                    }
                }
                .onChange(of: selectedInput) { _, new in
                    SettingsStore.selectedInputDeviceID = new
                }
                Button("Refresh device list") {
                    inputDevices = AudioDeviceRegistry.listInputDevices()
                    refreshMicAuth()
                }
                Text("Built-in MacBook mic is picked by default. Change this if Tabby ever records silence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Transcription engine") {
                Picker("Engine", selection: $engine) {
                    Text("Local (WhisperKit, on-device)").tag(SettingsStore.TranscriptionEngine.local)
                    Text("Cloud (OpenAI Whisper API)").tag(SettingsStore.TranscriptionEngine.cloud)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .onChange(of: engine) { _, new in
                    SettingsStore.transcriptionEngine = new
                }
            }

            if engine == .local {
                Section("Local model (WhisperKit)") {
                    Picker("Model", selection: $model) {
                        ForEach(modelOptions, id: \.value) { opt in
                            Text(opt.label).tag(opt.value)
                        }
                    }
                    .onChange(of: model) { _, new in
                        SettingsStore.whisperKitModel = new
                    }

                    HStack(spacing: 8) {
                        statusBadge
                        Spacer()
                        Button(transcriber.isModelReady && currentMatchesSelected ? "Re-download" : "Download now") {
                            Task { await transcriber.preloadCurrentModel() }
                        }
                        .disabled(transcriber.isLoading)
                    }

                    if transcriber.isLoading, let msg = transcriber.loadingMessage {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.6).controlSize(.mini)
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let err = transcriber.lastLoadError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(3)
                    }

                    Text("Models are cached at ~/Library/Application Support/huggingface/ — first download can take 30–120s depending on connection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if engine == .cloud {
                Section("Cloud (OpenAI Whisper)") {
                    SecureField("OpenAI API key (sk-…)", text: $openAIKey)
                    HStack {
                        Button("Save key") {
                            SettingsStore.openAIKey = openAIKey.isEmpty ? nil : openAIKey
                        }
                        .disabled(openAIKey == (SettingsStore.openAIKey ?? ""))
                        Spacer()
                        if SettingsStore.openAIKey?.isEmpty == false {
                            Label("Key saved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                    Text("Tabby sends the recording as a 16 kHz mono WAV to POST /v1/audio/transcriptions (model: gpt-4o-transcribe). The key is stored in this Mac's Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("\(state.botDisplayName) response") {
                LabeledContent("Display name") {
                    TextField("Display name", text: $state.botDisplayName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
                LabeledContent("Max response lines") {
                    HStack(spacing: 6) {
                        Text("\(maxResponseLines)")
                            .monospacedDigit()
                            .frame(minWidth: 24, alignment: .trailing)
                        Stepper("", value: $maxResponseLines, in: 1...30)
                            .labelsHidden()
                            .onChange(of: maxResponseLines) { _, new in
                                SettingsStore.maxResponseLines = new
                            }
                    }
                }
                Text("Tabby appends \"Output should be \(maxResponseLines) line\(maxResponseLines == 1 ? "" : "s") long maximum.\" to every prompt so Hermes keeps its replies tight enough for the notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Telegram") {
                LabeledContent("\(state.botDisplayName) bot") {
                    Text(SettingsStore.hermesBotUsername.map { "@\($0)" } ?? "—")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("chat_id") {
                    Text("\(SettingsStore.hermesBotChatId)")
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
                Button("Re-run Telegram setup", role: .destructive) {
                    state.telegram.resetAuth()
                    NSApp.keyWindow?.close()
                }
            }

            Section {
                Button("Quit Tabby", role: .destructive) {
                    NSApp.terminate(nil)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 620)
        .onAppear { refreshMicAuth() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshMicAuth()
        }
    }

    private var currentMatchesSelected: Bool {
        transcriber.isModelReady
    }

    private func labelFor(_ d: AudioInputDevice) -> String {
        var parts = [d.name]
        if d.isBuiltIn { parts.append("(built-in)") }
        else if !d.manufacturer.isEmpty { parts.append("(\(d.manufacturer))") }
        return parts.joined(separator: " ")
    }

    @ViewBuilder
    private var statusBadge: some View {
        if transcriber.isLoading {
            Label("Loading…", systemImage: "arrow.down.circle")
                .foregroundStyle(.secondary)
        } else if transcriber.isModelReady {
            Label("Loaded", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Label("Not loaded", systemImage: "circle.dashed")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var micAuthControl: some View {
        switch micAuthStatus {
        case .authorized:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .notDetermined:
            Button("Authorize") {
                Task {
                    _ = await AVCaptureDevice.requestAccess(for: .audio)
                    await MainActor.run { refreshMicAuth() }
                }
            }
        case .denied, .restricted:
            HStack(spacing: 6) {
                Label("Denied", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Button("Open System Settings") { openMicPrivacyPane() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        @unknown default:
            Text("Unknown")
                .foregroundStyle(.secondary)
        }
    }

    private func refreshMicAuth() {
        micAuthStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    private func openMicPrivacyPane() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone",
        ]
        for str in urls {
            if let url = URL(string: str), NSWorkspace.shared.open(url) { return }
        }
    }
}
