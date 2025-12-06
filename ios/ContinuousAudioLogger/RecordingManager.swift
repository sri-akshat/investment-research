// File: RecordingManager.swift
// Handles audio session configuration, live capture, chunk rotation, and notifying upload queue.
// Uses AVAudioEngine with a tap writing to AVAudioFile. Chunk rotation swaps the active file.
// Intended for personal use; always comply with local laws and obtain consent before recording.

import Foundation
import AVFoundation
import Combine

final class RecordingManager: ObservableObject {
    enum State {
        case idle
        case recording(sessionId: UUID, chunkStart: Date)
        case interrupted(String)
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published var elapsedInCurrentChunk: TimeInterval = 0
    @Published var lastError: String?

    private let engine = AVAudioEngine()
    private let audioQueue = DispatchQueue(label: "audio-writer-queue")
    private var currentFile: AVAudioFile?
    private var chunkStartDate: Date?
    private var chunkTimer: DispatchSourceTimer?
    private var cancellables = Set<AnyCancellable>()
    private let settingsStore: RecordingSettingsStore
    private let indexStore: RecordingIndexStore
    private let uploadManager: UploadManager

    init(settingsStore: RecordingSettingsStore, indexStore: RecordingIndexStore, uploadManager: UploadManager) {
        self.settingsStore = settingsStore
        self.indexStore = indexStore
        self.uploadManager = uploadManager
    }

    // MARK: - Permissions & session
    func requestPermissionIfNeeded(completion: @escaping (Bool) -> Void) {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: completion(true)
        case .denied: completion(false)
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission(completion)
        @unknown default:
            completion(false)
        }
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.allowBluetooth, .defaultToSpeaker, .duckOthers])
        try session.setPreferredSampleRate(16_000)
        try session.setPreferredIOBufferDuration(0.01)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Recording lifecycle
    func startRecording() {
        guard case .idle = state else { return }
        requestPermissionIfNeeded { [weak self] granted in
            guard let self else { return }
            DispatchQueue.main.async {
                if !granted {
                    self.state = .error("Microphone permission denied")
                    self.lastError = "Microphone permission denied"
                    return
                }
                do {
                    try self.configureSession()
                    let sessionId = UUID()
                    self.indexStore.startSession(sessionId: sessionId)
                    self.startEngine(sessionId: sessionId)
                } catch {
                    self.state = .error("Failed to start session: \(error.localizedDescription)")
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    func stopRecording() {
        guard case let .recording(sessionId, _) = state else { return }
        chunkTimer?.cancel()
        chunkTimer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioQueue.sync {
            if let file = self.currentFile {
                let duration = Date().timeIntervalSince(self.chunkStartDate ?? Date())
                self.indexStore.appendChunk(for: sessionId, fileURL: file.url, createdAt: self.chunkStartDate ?? Date(), duration: duration)
                self.uploadManager.enqueue(fileURL: file.url, sessionId: sessionId)
            }
            self.currentFile = nil
        }
        indexStore.finishSession(sessionId: sessionId)
        state = .idle
    }

    private func startEngine(sessionId: UUID) throws {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false) ?? format

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: targetFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.audioQueue.async {
                if let file = self.currentFile {
                    do {
                        try file.write(from: buffer)
                    } catch {
                        DispatchQueue.main.async {
                            self.lastError = "Write error: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }

        engine.prepare()
        try engine.start()
        rotateChunk(sessionId: sessionId)
        scheduleChunkTimer(sessionId: sessionId)
        state = .recording(sessionId: sessionId, chunkStart: Date())
    }

    // MARK: - Chunk handling
    private func scheduleChunkTimer(sessionId: UUID) {
        chunkTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        let interval = TimeInterval(settingsStore.settings.chunkDurationMinutes * 60)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.rotateChunk(sessionId: sessionId)
        }
        timer.resume()
        chunkTimer = timer

        // Track elapsed time every second for UI
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if case .recording = self.state {
                self.elapsedInCurrentChunk = Date().timeIntervalSince(self.chunkStartDate ?? Date())
            }
        }
    }

    private func rotateChunk(sessionId: UUID) {
        audioQueue.sync {
            if let file = self.currentFile {
                let duration = Date().timeIntervalSince(self.chunkStartDate ?? Date())
                self.indexStore.appendChunk(for: sessionId, fileURL: file.url, createdAt: self.chunkStartDate ?? Date(), duration: duration)
                self.uploadManager.enqueue(fileURL: file.url, sessionId: sessionId)
            }
            let newURL = self.makeChunkURL(sessionId: sessionId)
            let format = self.engine.inputNode.inputFormat(forBus: 0)
            do {
                self.currentFile = try AVAudioFile(forWriting: newURL, settings: self.recordingSettings(format: format))
                self.chunkStartDate = Date()
                DispatchQueue.main.async {
                    self.state = .recording(sessionId: sessionId, chunkStart: self.chunkStartDate ?? Date())
                    self.elapsedInCurrentChunk = 0
                }
            } catch {
                DispatchQueue.main.async {
                    self.state = .error("Failed to create chunk file: \(error.localizedDescription)")
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    private func recordingSettings(format: AVAudioFormat) -> [String: Any] {
        // AAC mono at 16kHz for speech
        return [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
    }

    private func makeChunkURL(sessionId: UUID) -> URL {
        let fm = FileManager.default
        let dir = fm.recordingsDirectory()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "session_\(sessionId.uuidString)_chunk_\(timestamp).m4a"
        return dir.appendingPathComponent(filename)
    }
}

// MARK: - Helpers
extension FileManager {
    func recordingsDirectory() -> URL {
        let dir = try! url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Recordings")
        if !fileExists(atPath: dir.path) {
            try? createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
