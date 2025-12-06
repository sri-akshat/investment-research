// File: S3Client.swift
// Thin abstraction over AWS S3 uploads. Replace credentials setup with Cognito or static keys as needed.
// For production, configure AWSMobileClient or Amplify; here we use AWSS3TransferUtility for simplicity.

import Foundation
import AWSS3

protocol S3Uploading {
    func uploadRecording(localURL: URL, remoteKey: String, completion: @escaping (Result<Void, Error>) -> Void)
}

final class S3Client: S3Uploading {
    private let bucket: String

    init(bucket: String, region: AWSRegionType) {
        self.bucket = bucket
        // NOTE: Configure AWS credentials before using (e.g., AWSCognitoCredentialsProvider or static key for prototyping).
        let config = AWSServiceConfiguration(region: region, credentialsProvider: nil)
        AWSServiceManager.default().defaultServiceConfiguration = config
    }

    func uploadRecording(localURL: URL, remoteKey: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let transferUtility = AWSS3TransferUtility.default() else {
            completion(.failure(NSError(domain: "S3Client", code: -1, userInfo: [NSLocalizedDescriptionKey: "TransferUtility not configured"])))
            return
        }

        transferUtility.uploadFile(localURL, bucket: bucket, key: remoteKey, contentType: "audio/m4a", expression: nil) { task, error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
}

// Alternatively, if you prefer presigned URLs, generate them server-side and use URLSession uploadTask here.
