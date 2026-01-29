//
//  VoiceCommandService.swift
//  Mobile Terminal
//
//  Speech-to-text service for voice command input
//

import SwiftUI
import Speech
import AVFoundation

final class VoiceCommandService: ObservableObject {
    @Published var isListening = false
    @Published var transcribedText = ""
    @Published var errorMessage: String?
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    #if os(iOS)
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    #endif

    init() {
        checkAuthorization()
    }

    func checkAuthorization() {
        #if os(iOS)
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.authorizationStatus = status
            }
        }
        #endif
    }

    func requestPermissions() {
        #if os(iOS)
        // Request speech recognition
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.authorizationStatus = status
            }
        }

        // Request microphone
        AVAudioApplication.requestRecordPermission { granted in
            if !granted {
                Task { @MainActor in
                    self.errorMessage = "Microphone permission denied"
                }
            }
        }
        #endif
    }

    func startListening() {
        #if os(iOS)
        guard !isListening else { return }

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition not available"
            return
        }

        do {
            // Cancel any previous task
            recognitionTask?.cancel()
            recognitionTask = nil

            // Configure audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            // Create recognition request
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else {
                errorMessage = "Unable to create recognition request"
                return
            }

            recognitionRequest.shouldReportPartialResults = true
            recognitionRequest.requiresOnDeviceRecognition = false

            // Start recognition task
            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                Task { @MainActor in
                    guard let self = self else { return }

                    if let result = result {
                        self.transcribedText = result.bestTranscription.formattedString
                    }

                    if let error = error {
                        self.errorMessage = error.localizedDescription
                        self.stopListening()
                    }
                }
            }

            // Configure audio input
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            isListening = true
            transcribedText = ""
            HapticManager.shared.lightTap()

        } catch {
            errorMessage = "Audio engine error: \(error.localizedDescription)"
            stopListening()
        }
        #endif
    }

    func stopListening() {
        #if os(iOS)
        guard isListening else { return }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        isListening = false
        HapticManager.shared.mediumImpact()
        #endif
    }

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    func clearTranscription() {
        transcribedText = ""
    }
}
