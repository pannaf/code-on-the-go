import AVFoundation
import SwiftUI

struct WelcomeView: View {
    @State private var showChatView = false
    @State private var showPermissionAlert = false

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            Text("Code On The Go")
                .font(.system(size: 40, weight: .bold))
                .multilineTextAlignment(.center)

            Text(
                "Your AI coding assistant that helps you write, debug, and run code through natural conversation."
            )
            .font(.title3)
            .multilineTextAlignment(.center)
            .foregroundColor(.gray)
            .padding(.horizontal)

            Spacer()

            Button(action: {
                requestMicrophoneAccess()
            }) {
                Text("Press to start chatting!")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color.blue)
                    )
                    .shadow(radius: 5)
            }
            .padding(.horizontal)
            .alert("Microphone Access Required", isPresented: $showPermissionAlert) {
                Button("Open Settings", role: .none) {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Please enable microphone access in Settings to use voice chat.")
            }
        }
        .padding()
        .fullScreenCover(isPresented: $showChatView) {
            ChatView()
        }
    }

    private func requestMicrophoneAccess() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    showChatView = true
                } else {
                    showPermissionAlert = true
                }
            }
        }
    }
}
