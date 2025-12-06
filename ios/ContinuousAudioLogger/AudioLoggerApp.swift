// File: AudioLoggerApp.swift
// Main SwiftUI entry point wiring services and view models together.
// Ensure Info.plist includes NSMicrophoneUsageDescription and Background Modes > Audio enabled.

import SwiftUI
import AWSS3

@main
struct AudioLoggerApp: App {
    @StateObject private var settingsStore = RecordingSettingsStore()
    @StateObject private var indexStore = RecordingIndexStore()

    var body: some Scene {
        WindowGroup {
            let rotation = RotationManager(indexStore: indexStore)
            let s3 = S3Client(bucket: settingsStore.settings.bucketName, region: AWSRegionType(rawValue: settingsStore.settings.region) ?? .USEast1)
            let upload = UploadManager(s3: s3, indexStore: indexStore, rotationManager: rotation, settingsStore: settingsStore)
            let recorder = RecordingManager(settingsStore: settingsStore, indexStore: indexStore, uploadManager: upload)
            ContentView(viewModel: RecordingViewModel(recordingManager: recorder, uploadManager: upload), settingsStore: settingsStore, indexStore: indexStore)
        }
    }
}
