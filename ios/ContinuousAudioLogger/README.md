# Continuous Audio Logger (Personal Prototype)

This directory contains a minimal SwiftUI app that records microphone input into fixed-length chunks and uploads them to S3. It is intended for personal/experimental use only. Do not distribute without validating local recording laws and App Store policies.

## Capabilities to enable in Xcode
- Add `NSMicrophoneUsageDescription` to `Info.plist` explaining that audio is captured continuously when enabled.
- Enable **Background Modes > Audio, AirPlay, and Picture in Picture** to allow continued capture while in background (subject to iOS policies).
- Link AWS SDK for iOS (e.g., via Swift Package Manager) to provide `AWSS3`.

## AWS configuration
- Set `RecordingSettings.bucketName` and `RecordingSettings.region` defaults as needed.
- Provide credentials via Cognito, Amplify, or static keys for prototyping before using `S3Client`.
- S3 key format is `audio/<userId>/<YYYY>/<MM>/<DD>/<sessionId>/chunk_<timestamp>.m4a`.
- Handle S3 retention using lifecycle policies (time-based) and/or backend cleanup jobs (size-based).

## Local storage rotation
- Local recordings are written to `Application Support/Recordings`.
- Only **uploaded** chunks are eligible for deletion when size exceeds `localStorageLimitMB`.

## Extending
- Hook transcription/LLM processing by listening to `UploadManager` success callbacks or by consuming the S3 objects offline.
