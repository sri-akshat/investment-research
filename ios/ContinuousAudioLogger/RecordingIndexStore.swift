// File: RecordingIndexStore.swift
// Persists a lightweight JSON index of sessions and chunks to avoid heavier dependencies.
// Pending uploads are kept even when rotating local storage; only uploaded files may be deleted.

import Foundation
import Combine

final class RecordingIndexStore: ObservableObject {
    @Published private(set) var index: RecordingIndex
    private let url: URL
    private let queue = DispatchQueue(label: "recording-index-queue")

    init(fileManager: FileManager = .default) {
        let supportDir = try! fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        self.url = supportDir.appendingPathComponent("recording_index.json")
        if let data = try? Data(contentsOf: url), let loaded = try? JSONDecoder().decode(RecordingIndex.self, from: data) {
            self.index = loaded
        } else {
            self.index = .empty
            persist()
        }
    }

    func startSession(sessionId: UUID) {
        queue.sync {
            let session = RecordingSession(id: sessionId, startTime: Date(), endTime: nil)
            index.sessions.append(session)
            persist()
        }
    }

    func finishSession(sessionId: UUID) {
        queue.sync {
            if let idx = index.sessions.firstIndex(where: { $0.id == sessionId }) {
                index.sessions[idx].endTime = Date()
                persist()
            }
        }
    }

    func appendChunk(for sessionId: UUID, fileURL: URL, createdAt: Date, duration: Double) {
        queue.sync {
            let chunk = RecordingChunk(
                id: UUID(),
                sessionId: sessionId,
                localFilePath: fileURL.path,
                creationTime: createdAt,
                durationSeconds: duration,
                uploaded: false,
                remoteKey: nil
            )
            index.chunks.append(chunk)
            persist()
        }
    }

    func markUploaded(chunkId: UUID, remoteKey: String) {
        queue.sync {
            guard let idx = index.chunks.firstIndex(where: { $0.id == chunkId }) else { return }
            index.chunks[idx].uploaded = true
            index.chunks[idx].remoteKey = remoteKey
            persist()
        }
    }

    func removeChunk(id: UUID) {
        queue.sync {
            index.chunks.removeAll { $0.id == id }
            persist()
        }
    }

    func pendingChunks() -> [RecordingChunk] {
        queue.sync { index.chunks.filter { !$0.uploaded } }
    }

    func uploadedChunksSortedByCreation() -> [RecordingChunk] {
        queue.sync { index.chunks.filter { $0.uploaded }.sorted { $0.creationTime < $1.creationTime } }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(index) {
            try? data.write(to: url)
        }
    }
}
