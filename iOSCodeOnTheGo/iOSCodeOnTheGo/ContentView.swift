//
//  ContentView.swift
//  iOSCodeOnTheGo
//
//  Created by Richard on 2/8/25.
//

import AVFoundation
import SwiftUI

#if os(iOS)
    class AudioManager: NSObject, ObservableObject {
        // only setup for ios for now

        private var audioRecorder: AVAudioRecorder?
        private var audioPlayer: AVAudioPlayer?
        #if os(iOS)
            private var recordingSession: AVAudioSession?
        #endif
        @Published var isRecording = false
        @Published var isProcessing = false
        @Published var responseText: String?
        @Published var error: String?
        @Published var buttonColor: Color = .blue
        @Published var isPlaying = false
        @Published var playbackProgress: Double = 0.0
        private var recordingURL: URL?
        private var progressTimer: Timer?

        override init() {
            super.init()
            setupAudio()
        }

        //
        private func setupAudio() {
            #if os(iOS)
                recordingSession = AVAudioSession.sharedInstance()
                do {
                    try recordingSession?.setCategory(.playAndRecord, mode: .default)
                    try recordingSession?.setActive(true)
                } catch {
                    print("Failed to set up audio session: \(error)")
                }
            #endif
        }

        private func playSound(named: String) {
            guard let url = Bundle.main.url(forResource: named, withExtension: "mp3") else {
                print("Sound file not found")
                return
            }

            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.play()
            } catch {
                print("Failed to play sound: \(error)")
            }
        }

        func startRecording() {
            do {
                try AVAudioSession.sharedInstance().setCategory(.record)
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("Failed to set up recording session: \(error)")
                return
            }

            let audioFilename = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask)[
                    0
                ].appendingPathComponent("recording.m4a")

            recordingURL = audioFilename  // Store the URL for playback

            let settings = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 12000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]

            do {
                audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
                audioRecorder?.record()
                isRecording = true
                buttonColor = .red
                playSound(named: "start_recording")
            } catch {
                print("Could not start recording: \(error)")
            }
        }

        func stopRecording() {
            audioRecorder?.stop()
            isRecording = false
            isProcessing = true
            buttonColor = .white
            playSound(named: "end_recording")

            // Here you would upload the audio file and get a task ID
            uploadAudioAndPoll()
        }

        private func uploadAudioAndPoll() {
            // Simulated API call - replace with your actual API implementation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let taskId = "sample-task-id"
                self.startPolling(taskId: taskId)
            }
        }

        private func startPolling(taskId: String) {
            // Implement polling logic here
            // This is a simplified example
            var attempts = 0
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
                attempts += 1

                // Simulate API check - replace with actual API call
                if attempts >= 3 {  // Simulating completion after 6 seconds
                    timer.invalidate()
                    self.isProcessing = false
                    self.buttonColor = .blue  // Reset color to blue after processing
                    self.responseText = "This is the transcribed and processed response"
                }

                // Add timeout logic
                if attempts > 30 {  // 1 minute timeout
                    timer.invalidate()
                    self.isProcessing = false
                    self.buttonColor = .blue  // Reset color to blue after timeout
                    self.error = "Request timed out. Please try again."
                }
            }
        }

        func playRecording() {
            guard let url = recordingURL else {
                print("No recording URL available")
                return
            }

            do {
                // added by me
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playback)
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    print("Failed to set up playback session: \(error)")
                    return
                }

                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.delegate = self
                audioPlayer?.play()
                isPlaying = true

                // Start progress timer
                progressTimer?.invalidate()
                progressTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) {
                    [weak self] _ in
                    guard let self = self,
                        let player = self.audioPlayer
                    else { return }
                    self.playbackProgress = player.currentTime / player.duration
                }
            } catch {
                print("Failed to play recording: \(error)")
            }
        }

        func stopPlayback() {
            audioPlayer?.stop()
            isPlaying = false
            progressTimer?.invalidate()
            progressTimer = nil
            playbackProgress = 0.0
        }
    }

    extension AudioManager: AVAudioPlayerDelegate {
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            DispatchQueue.main.async {
                self.isPlaying = false
                self.progressTimer?.invalidate()
                self.progressTimer = nil
                self.playbackProgress = 0.0
            }
        }
    }

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
                    "Your AI coding companion that helps you write, debug, and learn code through natural conversation."
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

    struct ChatView: View {
        @StateObject private var audioManager = AudioManager()
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationView {
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(audioManager.buttonColor)
                            .frame(width: 200, height: 200)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 4)
                            )
                            .shadow(radius: 10)

                        Image(systemName: audioManager.isRecording ? "mic.fill" : "mic")
                            .font(.system(size: 60))
                            .foregroundColor(audioManager.buttonColor == .white ? .black : .white)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !audioManager.isRecording && !audioManager.isProcessing {
                                    audioManager.startRecording()
                                }
                            }
                            .onEnded { _ in
                                if audioManager.isRecording {
                                    audioManager.stopRecording()
                                }
                            }
                    )
                    .disabled(audioManager.isProcessing)

                    // Debug Playback Section
                    VStack(spacing: 10) {
                        Button(action: {
                            if audioManager.isPlaying {
                                audioManager.stopPlayback()
                            } else {
                                audioManager.playRecording()
                            }
                        }) {
                            HStack {
                                Image(
                                    systemName: audioManager.isPlaying ? "stop.fill" : "play.fill")
                                Text("DEBUG: Play Recording")
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.orange)
                            .cornerRadius(10)
                        }
                        .disabled(audioManager.isRecording || audioManager.isProcessing)

                        // Playback Progress Bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 8)
                                    .cornerRadius(4)

                                Rectangle()
                                    .fill(Color.orange)
                                    .frame(
                                        width: geometry.size.width
                                            * CGFloat(audioManager.playbackProgress), height: 8
                                    )
                                    .cornerRadius(4)
                            }
                        }
                        .frame(height: 8)
                        .padding(.horizontal)
                    }
                    .padding(.vertical)

                    if audioManager.isProcessing {
                        VStack {
                            ProgressView()
                            Text("Processing your request...")
                                .foregroundColor(.gray)
                        }
                    }

                    if let response = audioManager.responseText {
                        Text(response)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                    }

                    if let error = audioManager.error {
                        Text(error)
                            .foregroundColor(.red)
                            .padding()
                    }
                }
                .padding()
                .navigationTitle("Voice Chat")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    struct ContentView: View {
        var body: some View {
            WelcomeView()
        }
    }

    #Preview {
        ContentView()
    }

#endif
