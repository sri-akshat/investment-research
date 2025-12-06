// File: RotationManager.swift
// Handles local disk rotation: delete oldest uploaded chunks if storage exceeds limit.

import Foundation

final class RotationManager {
    private let indexStore: RecordingIndexStore
    private let fileManager: FileManager

    init(indexStore: RecordingIndexStore, fileManager: FileManager = .default) {
        self.indexStore = indexStore
        self.fileManager = fileManager
    }

    func enforceLocalLimit(limitMB: Int) {
        let dir = fileManager.recordingsDirectory()
        let totalBytes = directorySize(url: dir)
        let limitBytes = Int64(limitMB) * 1024 * 1024
        guard totalBytes > limitBytes else { return }

        var freed: Int64 = 0
        for chunk in indexStore.uploadedChunksSortedByCreation() {
            let url = URL(fileURLWithPath: chunk.localFilePath)
            if fileManager.fileExists(atPath: url.path) {
                if let attrs = try? fileManager.attributesOfItem(atPath: url.path), let size = attrs[.size] as? NSNumber {
                    try? fileManager.removeItem(at: url)
                    indexStore.removeChunk(id: chunk.id)
                    freed += size.int64Value
                    if totalBytes - freed <= limitBytes { break }
                }
            } else {
                indexStore.removeChunk(id: chunk.id)
            }
        }
    }

    private func directorySize(url: URL) -> Int64 {
        guard let files = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for file in files {
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
