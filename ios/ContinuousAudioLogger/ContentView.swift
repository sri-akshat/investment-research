// File: ContentView.swift
// SwiftUI UI: main screen with start/stop, status, and navigation to settings and debug info.

import SwiftUI

struct ContentView: View {
    @StateObject var viewModel: RecordingViewModel
    @StateObject var settingsStore: RecordingSettingsStore
    @StateObject var indexStore: RecordingIndexStore
    @State private var showSettings = false
    @AppStorage("hasConsent") private var hasConsent: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                consentBanner
                recordingIndicator
                controlButton
                statusGrid
                Spacer()
                legalNotice
            }
            .padding()
            .navigationTitle("Audio Logger")
            .toolbar {
                Button("Settings") { showSettings = true }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(settingsStore: settingsStore, indexStore: indexStore)
            }
            .fullScreenCover(isPresented: Binding(get: { !hasConsent }, set: { _ in })) {
                ConsentView(hasConsent: $hasConsent)
            }
        }
    }

    private var consentBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Records continuously when active.", systemImage: "mic.fill")
                .foregroundStyle(.red)
            Text("Personal use only. Obtain consent where required. Audio is chunked and uploaded to S3.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.red.opacity(0.1))
        .cornerRadius(12)
    }

    private var recordingIndicator: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(viewModel.isRecording ? .red : .gray)
                .frame(width: 16, height: 16)
            if viewModel.isRecording {
                Text("Recording – Session \(viewModel.currentSessionId?.uuidString.prefix(6) ?? "-")")
            } else {
                Text("Idle")
            }
        }
        .font(.headline)
    }

    private var controlButton: some View {
        Button(action: {
            viewModel.isRecording ? viewModel.stop() : viewModel.start()
        }) {
            Text(viewModel.isRecording ? "Stop logging" : "Start logging")
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.isRecording ? Color.red : Color.green)
                .foregroundColor(.white)
                .cornerRadius(16)
        }
        .disabled(!hasConsent)
    }

    private var statusGrid: some View {
        Grid(alignment: .leading) {
            GridRow {
                Text("Chunk elapsed")
                Text("\(Int(viewModel.elapsed)) s")
            }
            GridRow {
                Text("Pending uploads")
                Text("\(viewModel.pendingUploads)")
            }
            GridRow {
                Text("Chunk length")
                Text("\(settingsStore.settings.chunkDurationMinutes) min")
            }
            GridRow {
                Text("Local limit")
                Text("\(settingsStore.settings.localStorageLimitMB) MB")
            }
            if let error = viewModel.lastError {
                GridRow {
                    Text("Last error").foregroundColor(.red)
                    Text(error).foregroundColor(.red)
                }
            }
        }
    }

    private var legalNotice: some View {
        Text("This prototype is for personal logging. Recording conversations may be subject to law; obtain consent before use.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let settingsStore = RecordingSettingsStore()
        let indexStore = RecordingIndexStore()
        let rotation = RotationManager(indexStore: indexStore)
        let s3 = S3Client(bucket: "demo", region: .USEast1)
        let upload = UploadManager(s3: s3, indexStore: indexStore, rotationManager: rotation, settingsStore: settingsStore)
        let recorder = RecordingManager(settingsStore: settingsStore, indexStore: indexStore, uploadManager: upload)
        ContentView(viewModel: RecordingViewModel(recordingManager: recorder, uploadManager: upload), settingsStore: settingsStore, indexStore: indexStore)
    }
}
