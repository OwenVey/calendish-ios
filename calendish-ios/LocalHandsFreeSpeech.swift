import AVFAudio
import Speech

/// Hands-free cooking's speech boundary: on-device SpeechAnalyzer recognition from the microphone,
/// plus spoken feedback. Audio and transcripts stay in memory and never leave the iPhone.
@MainActor
final class LocalHandsFreeSpeech: NSObject, HandsFreeSpeech {
    private var engine: AVAudioEngine?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var recognition: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var sessionActive = false
    private let gate = AudioGate()
    private lazy var synthesizer: AVSpeechSynthesizer = {
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.usesApplicationAudioSession = true
        synthesizer.delegate = self
        return synthesizer
    }()
    private var spoken: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]

    func requestMicrophoneAccess() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func availability() async -> HandsFreeAvailability {
        guard SpeechTranscriber.isAvailable, let transcriber = await Self.transcriber() else {
            return .unavailable("Voice commands aren’t available on this iPhone. You can keep cooking with the buttons.")
        }
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed: return .ready
        case .supported, .downloading: return .needsPreparation
        default: return .unavailable("Voice commands aren’t available on this iPhone. You can keep cooking with the buttons.")
        }
    }

    func prepare(progress: @escaping @MainActor (Double) -> Void) async throws {
        guard let transcriber = await Self.transcriber(),
              let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else { return }
        let reporting = Task {
            while !Task.isCancelled {
                progress(request.progress.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { reporting.cancel() }
        try await withTaskCancellationHandler {
            try await request.downloadAndInstall()
        } onCancel: {
            request.progress.cancel()
        }
        try Task.checkCancellation()
    }

    func listen(_ hear: @escaping @MainActor (HandsFreeHearing) -> Void) {
        endCapture()
        observe(hear)
        recognition = Task {
            var analyzer: SpeechAnalyzer?
            do {
                guard let transcriber = await Self.transcriber() else { throw CancellationError() }
                try Task.checkCancellation()
                let current = SpeechAnalyzer(modules: [transcriber])
                analyzer = current
                let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
                try await current.prepareToAnalyze(in: format)
                try Task.checkCancellation()
                let (sequence, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
                self.input = input
                try startCapture(into: input, format: format)
                try await current.start(inputSequence: sequence)
                for try await result in transcriber.results {
                    // A result's start time identifies one utterance within this capture.
                    let start = result.range.start
                    hear(.utterance(id: "\(start.value)/\(start.timescale)", text: String(result.text.characters), isFinal: result.isFinal))
                }
                if !Task.isCancelled { hear(.failed) }
            } catch {
                if !Task.isCancelled { hear(.failed) }
            }
            await analyzer?.cancelAndFinishNow()
        }
    }

    func stopListening() {
        endCapture()
        // Let other apps' audio resume only once listening actually ends.
        if sessionActive {
            sessionActive = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func endCapture() {
        recognition?.cancel()
        recognition = nil
        input?.finish()
        input = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        gate.isMuted = false
    }

    func speak(_ text: String) async {
        gate.isMuted = true
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        await withCheckedContinuation { continuation in
            spoken[ObjectIdentifier(utterance)] = continuation
            synthesizer.speak(utterance)
        }
        // Let the room's echo of the feedback fade before listening again.
        try? await Task.sleep(for: .milliseconds(300))
        if spoken.isEmpty { gate.isMuted = false }
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        spoken.values.forEach { $0.resume() }
        spoken = [:]
    }

    /// English commands only: the person's own English variant, or US English.
    private static func transcriber() async -> SpeechTranscriber? {
        let preferred = Locale.current.language.languageCode == .english ? Locale.current : Locale(identifier: "en-US")
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: preferred) else { return nil }
        return SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.fastResults], attributeOptions: [])
    }

    private func startCapture(into input: AsyncStream<AnalyzerInput>.Continuation, format: AVAudioFormat?) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: Self.sessionOptions)
        try session.setActive(true)
        sessionActive = true
        let engine = AVAudioEngine()
        let node = engine.inputNode
        let captured = node.outputFormat(forBus: 0)
        // Installing a tap without a usable input raises an exception Swift can't catch.
        guard captured.channelCount > 0, captured.sampleRate > 0 else { throw CancellationError() }
        node.installTap(onBus: 0, bufferSize: 4096, format: captured,
            block: Self.tap(from: captured, to: format ?? captured, gate: gate, input: input))
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    /// Converts microphone audio for the analyzer, replacing it with silence during feedback.
    /// Runs on the audio thread.
    private nonisolated static func tap(from source: AVAudioFormat, to target: AVAudioFormat, gate: AudioGate,
                                        input: AsyncStream<AnalyzerInput>.Continuation) -> AVAudioNodeTapBlock {
        let converter = source == target ? nil : AVAudioConverter(from: source, to: target)
        return { buffer, _ in
            var output = buffer
            if let converter {
                let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / source.sampleRate) + 1
                guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
                var supplied = false
                var error: NSError?
                converter.convert(to: converted, error: &error) { _, status in
                    if supplied { status.pointee = .noDataNow; return nil }
                    supplied = true
                    status.pointee = .haveData
                    return buffer
                }
                guard error == nil else { return }
                output = converted
            }
            if gate.isMuted {
                for channel in UnsafeMutableAudioBufferListPointer(output.mutableAudioBufferList) {
                    if let data = channel.mData { memset(data, 0, Int(channel.mDataByteSize)) }
                }
            }
            input.yield(AnalyzerInput(buffer: output))
        }
    }

    private static let sessionOptions: AVAudioSession.CategoryOptions = [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP]

    private func observe(_ hear: @escaping @MainActor (HandsFreeHearing) -> Void) {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
                let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                    .flatMap(AVAudioSession.InterruptionType.init) == .began
                if began { MainActor.assumeIsolated { hear(.interrupted) } }
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { hear(.failed) }
            },
            // Route changes, such as connecting headphones, can stop the engine.
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if self?.engine?.isRunning == false { hear(.failed) }
                }
            },
        ]
    }

    private func finishedSpeaking(_ id: ObjectIdentifier) {
        spoken.removeValue(forKey: id)?.resume()
    }
}

extension LocalHandsFreeSpeech: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in finishedSpeaking(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in finishedSpeaking(id) }
    }
}

/// Whether captured audio is replaced with silence, read from the audio thread.
private nonisolated final class AudioGate: @unchecked Sendable {
    private let lock = NSLock()
    private var muted = false
    var isMuted: Bool {
        get { lock.withLock { muted } }
        set { lock.withLock { muted = newValue } }
    }
}
