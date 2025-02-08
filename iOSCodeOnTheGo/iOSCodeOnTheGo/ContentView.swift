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
        private var speechSynthesizer: AVSpeechSynthesizer?
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
            speechSynthesizer = AVSpeechSynthesizer()
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
            guard let audioFileURL = recordingURL else {
                print("DEBUG: No recording URL available")
                return
            }

            print("DEBUG: Starting upload process")
            print("DEBUG: Audio file URL: \(audioFileURL)")

            // Create the upload request
            let boundary = "Boundary-\(UUID().uuidString)"

            // RICHARD IP ADDRESS - http://192.168.1.102:12000/upload
            // Use this command to figure out the endpoint: ifconfig | grep "inet " | grep -v 127.0.0.1
            let uploadURLString = "http://192.168.1.102:12000/upload"
            guard let uploadURL = URL(string: uploadURLString) else {
                print("DEBUG: Invalid URL: \(uploadURLString)")
                return
            }

            print("DEBUG: Upload URL: \(uploadURL)")

            var request = URLRequest(url: uploadURL)
            request.httpMethod = "POST"
            request.setValue(
                "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            // Create the request body
            var data = Data()

            // Add the file data
            data.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
            data.append(
                "Content-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\n"
                    .data(using: .utf8)!)
            data.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)

            do {
                let audioData = try Data(contentsOf: audioFileURL)
                print("DEBUG: Audio file size: \(audioData.count) bytes")

                data.append(audioData)
                data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

                // Create upload task
                print("DEBUG: Creating upload task")
                let task = URLSession.shared.uploadTask(with: request, from: data) {
                    [weak self] data, response, error in
                    guard let self = self else { return }

                    if let error = error {
                        print("DEBUG: Upload error: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            self.error = "Upload failed: \(error.localizedDescription)"
                            self.isProcessing = false
                            self.buttonColor = .blue
                        }
                        return
                    }

                    if let httpResponse = response as? HTTPURLResponse {
                        print("DEBUG: Upload response status code: \(httpResponse.statusCode)")
                        print("DEBUG: Response headers: \(httpResponse.allHeaderFields)")
                    }

                    if let responseData = data,
                        let responseString = String(data: responseData, encoding: .utf8)
                    {
                        print("DEBUG: Response data: \(responseString)")
                    }

                    guard let httpResponse = response as? HTTPURLResponse,
                        (200...299).contains(httpResponse.statusCode)
                    else {
                        print("DEBUG: Server error - invalid response")
                        DispatchQueue.main.async {
                            self.error = "Server error: Invalid response"
                            self.isProcessing = false
                            self.buttonColor = .blue
                        }
                        return
                    }

                    if let data = data {
                        do {
                            let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
                            print(
                                "DEBUG: Successfully decoded API response with taskId: \(apiResponse.taskId)"
                            )
                            self.startPolling(taskId: apiResponse.taskId)
                        } catch {
                            print("DEBUG: Failed to parse response: \(error)")
                            DispatchQueue.main.async {
                                self.error =
                                    "Failed to parse response: \(error.localizedDescription)"
                                self.isProcessing = false
                                self.buttonColor = .blue
                            }
                        }
                    }
                }

                print("DEBUG: Starting upload task")
                task.resume()

            } catch {
                print("DEBUG: Failed to read audio file: \(error)")
                DispatchQueue.main.async {
                    self.error = "Failed to read audio file: \(error.localizedDescription)"
                    self.isProcessing = false
                    self.buttonColor = .blue
                }
            }
        }

        private func startPolling(taskId: String) {
            var attempts = 0
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }

                attempts += 1

                // Create polling request
                var request = URLRequest(
                    url: URL(string: "http://192.168.1.102:12000/poll/\(taskId)")!)
                request.httpMethod = "GET"
                // Add any required headers
                // request.setValue("YOUR_API_KEY", forHTTPHeaderField: "Authorization")

                let task = URLSession.shared.dataTask(with: request) {
                    [weak self] data, response, error in
                    guard let self = self else { return }

                    if let error = error {
                        DispatchQueue.main.async {
                            timer.invalidate()
                            self.error = "Polling failed: \(error.localizedDescription)"
                            self.isProcessing = false
                            self.buttonColor = .blue
                        }
                        return
                    }

                    if let data = data,
                        let response = try? JSONDecoder().decode(APIResponse.self, from: data)
                    {
                        DispatchQueue.main.async {
                            timer.invalidate()
                            self.isProcessing = false
                            self.buttonColor = .blue
                            self.responseText = response.message
                            // Speak the response
                            // TODO: remove once we get a response
                            self.responseText = "Hello, how can I help you today?"
                            self.speakResponse(response.message)
                        }
                    }
                }

                task.resume()

                // Add timeout logic
                if attempts > 30 {  // 1 minute timeout
                    timer.invalidate()
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.buttonColor = .blue
                        self.error = "Request timed out. Please try again."
                    }
                }
            }
        }

        // New function to handle text-to-speech
        func speakResponse(_ text: String) {
            // Configure audio session for playback
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback)
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("Failed to set up playback session: \(error)")
                return
            }

            var utterance = AVSpeechUtterance(string: text)

            // Configure the voice (you can experiment with different voices)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")  // or try "en-GB" for British accent

            // Adjust speech parameters
            utterance.rate = 0.5  // 0.0 to 1.0, default is 0.5
            utterance.pitchMultiplier = 1.0  // 0.5 to 2.0, default is 1.0
            utterance.volume = 1.0  // 0.0 to 1.0, default is 1.0

            speechSynthesizer?.speak(utterance)
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

    struct APIResponse: Codable {
        let taskId: String
        let message: String
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

    struct ChatView: View {
        @StateObject var audioManager = AudioManager()
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

                    // eventually make this automatically respond to us after polling completes
                    if let response = audioManager.responseText {
                        Text(response)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                            // Add button to replay the speech
                            .onTapGesture {
                                audioManager.speakResponse(response)
                            }
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
