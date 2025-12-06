// File: RecordingViewModel.swift
// Bridges RecordingManager and UploadManager into UI-friendly state.

import Foundation
import Combine

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var currentSessionId: UUID?
    @Published var elapsed: TimeInterval = 0
    @Published var lastError: String?
    @Published var pendingUploads: Int = 0

    private let recordingManager: RecordingManager
    private let uploadManager: UploadManager
    private var cancellables = Set<AnyCancellable>()

    init(recordingManager: RecordingManager, uploadManager: UploadManager) {
        self.recordingManager = recordingManager
        self.uploadManager = uploadManager

        recordingManager.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .idle, .interrupted, .error:
                    self.isRecording = false
                case .recording(let sessionId, _):
                    self.isRecording = true
                    self.currentSessionId = sessionId
                }
            }
            .store(in: &cancellables)

        recordingManager.$elapsedInCurrentChunk
            .receive(on: DispatchQueue.main)
            .assign(to: &$elapsed)

        recordingManager.$lastError
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastError)

        uploadManager.$pending
            .receive(on: DispatchQueue.main)
            .map { $0.count }
            .assign(to: &$pendingUploads)
    }

    func start() {
        recordingManager.startRecording()
    }

    func stop() {
        recordingManager.stopRecording()
    }
}
