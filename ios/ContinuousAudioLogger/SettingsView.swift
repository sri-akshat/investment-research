// File: SettingsView.swift
// Simple settings for chunk duration and local storage cap plus debug info.

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: RecordingSettingsStore
    @ObservedObject var indexStore: RecordingIndexStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Recording") {
                    Stepper(value: $settingsStore.settings.chunkDurationMinutes, in: 1...15) {
                        Text("Chunk duration: \(settingsStore.settings.chunkDurationMinutes) minutes")
                    }
                    Stepper(value: $settingsStore.settings.localStorageLimitMB, in: 100...2048, step: 50) {
                        Text("Local storage cap: \(settingsStore.settings.localStorageLimitMB) MB")
                    }
                }

                Section("S3") {
                    Text("Bucket: \(settingsStore.settings.bucketName)")
                    Text("Region: \(settingsStore.settings.region)")
                    Text("User ID: \(settingsStore.settings.userId)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Debug") {
                    Text("Sessions: \(indexStore.index.sessions.count)")
                    Text("Chunks: \(indexStore.index.chunks.count)")
                    Text("Pending uploads: \(indexStore.pendingChunks().count)")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
