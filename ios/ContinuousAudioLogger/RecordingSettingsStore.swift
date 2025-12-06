// File: RecordingSettingsStore.swift
// Stores configurable settings like chunk duration and local disk limit.

import Foundation
import Combine

struct RecordingSettings: Codable {
    var chunkDurationMinutes: Int = 5 // default 5 minutes
    var localStorageLimitMB: Int = 500 // default 500 MB
    var bucketName: String = "S3_BUCKET_NAME"
    var region: String = "AWS_REGION"
    var userId: String = UUID().uuidString // persisted after first save
}

final class RecordingSettingsStore: ObservableObject {
    @Published var settings: RecordingSettings
    private let url: URL
    private var cancellables = Set<AnyCancellable>()

    init(fileManager: FileManager = .default) {
        let supportDir = try! fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        self.url = supportDir.appendingPathComponent("recording_settings.json")
        if let data = try? Data(contentsOf: url), let loaded = try? JSONDecoder().decode(RecordingSettings.self, from: data) {
            self.settings = loaded
        } else {
            self.settings = RecordingSettings()
            persist()
        }

        $settings
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.persist() }
            .store(in: &cancellables)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: url)
        }
    }
}
