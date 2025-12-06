// File: RecordingModels.swift
// Simple data models for sessions and chunks. Stored via JSON for simplicity.

import Foundation

struct RecordingSession: Codable, Identifiable {
    let id: UUID
    let startTime: Date
    var endTime: Date?
}

struct RecordingChunk: Codable, Identifiable, Hashable {
    let id: UUID
    let sessionId: UUID
    let localFilePath: String
    let creationTime: Date
    var durationSeconds: Double
    var uploaded: Bool
    var remoteKey: String?
}

struct RecordingIndex: Codable {
    var sessions: [RecordingSession]
    var chunks: [RecordingChunk]
}

extension RecordingIndex {
    static let empty = RecordingIndex(sessions: [], chunks: [])
}
