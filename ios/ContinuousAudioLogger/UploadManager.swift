// File: UploadManager.swift
// Queues recording chunks for upload and performs retries. Uses a serial queue to keep ordering simple.

import Foundation
import Combine

final class UploadManager: ObservableObject {
    struct QueueItem: Identifiable {
        let id = UUID()
        let chunkId: UUID
        let localURL: URL
        let sessionId: UUID
    }

    @Published private(set) var pending: [QueueItem] = []
    @Published var lastError: String?

    private let s3: S3Uploading
    private let indexStore: RecordingIndexStore
    private let rotationManager: RotationManager
    private let settingsStore: RecordingSettingsStore
    private let queue = DispatchQueue(label: "upload-manager-queue")
    private var isUploading = false

    init(s3: S3Uploading, indexStore: RecordingIndexStore, rotationManager: RotationManager, settingsStore: RecordingSettingsStore) {
        self.s3 = s3
        self.indexStore = indexStore
        self.rotationManager = rotationManager
        self.settingsStore = settingsStore

        // Enqueue pending uploads on launch
        for chunk in indexStore.pendingChunks() {
            enqueue(fileURL: URL(fileURLWithPath: chunk.localFilePath), sessionId: chunk.sessionId, chunkId: chunk.id)
        }
    }

    func enqueue(fileURL: URL, sessionId: UUID, chunkId: UUID? = nil) {
        let id = chunkId ?? UUID()
        queue.async {
            let item = QueueItem(chunkId: id, localURL: fileURL, sessionId: sessionId)
            self.pending.append(item)
            self.processQueue()
        }
    }

    private func processQueue() {
        guard !isUploading, let next = pending.first else { return }
        isUploading = true

        let remoteKey = makeRemoteKey(sessionId: next.sessionId, filename: next.localURL.lastPathComponent)
        s3.uploadRecording(localURL: next.localURL, remoteKey: remoteKey) { [weak self] result in
            guard let self else { return }
            self.queue.async {
                switch result {
                case .success:
                    self.indexStore.markUploaded(chunkId: next.chunkId, remoteKey: remoteKey)
                    self.pending.removeAll { $0.id == next.id }
                    self.rotationManager.enforceLocalLimit(limitMB: self.settingsStore.settings.localStorageLimitMB)
                case .failure(let error):
                    self.lastError = error.localizedDescription
                    // naive retry with delay
                    DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
                        self?.queue.async { self?.isUploading = false; self?.processQueue() }
                    }
                    return
                }
                self.isUploading = false
                self.processQueue()
            }
        }
    }

    private func makeRemoteKey(sessionId: UUID, filename: String) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let year = components.year ?? 1970
        let month = String(format: "%02d", components.month ?? 1)
        let day = String(format: "%02d", components.day ?? 1)
        return "audio/\(settingsStore.settings.userId)/\(year)/\(month)/\(day)/\(sessionId.uuidString)/\(filename)"
    }
}
