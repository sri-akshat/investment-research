// File: ConsentView.swift
// One-time consent gate reminding the user about legal responsibilities.

import SwiftUI

struct ConsentView: View {
    @Binding var hasConsent: Bool

    var body: some View {
        VStack(spacing: 24) {
            Text("Audio Logging Consent")
                .font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 12) {
                Label("Continuous microphone capture while enabled.", systemImage: "mic.fill")
                Label("May capture voices of others nearby.", systemImage: "person.2.fill")
                Label("You must follow local laws and obtain consent.", systemImage: "exclamationmark.triangle.fill")
                Label("Uploads to your configured S3 bucket; protect your credentials.", systemImage: "lock.fill")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: { hasConsent = true }) {
                Text("I understand")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .padding()
    }
}
