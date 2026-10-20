import AVFoundation
import Observation
import PianoCore

/// Microphone capture for note detection: session setup, AVAudioEngine, and the processor.
@MainActor
@Observable
final class ListenEngine {
    enum State: Equatable {
        case idle, running, denied
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var sampleRate: Double = 0
    private(set) var ioBufferDuration: Double = 0
    private(set) var inputLatency: Double = 0
    private(set) var latest = ListenUpdate()

    /// Called on the main actor for every detection.
    var onDetection: ((ListenUpdate.Detection) -> Void)?

    var expected: Set<Int> = [] {
        didSet { processor?.setExpected(expected) }
    }

    /// Name of the last saved recording, or the error saving it.
    private(set) var lastRecording: String?

    var isRecording: Bool { latest.recordingDuration != nil }

    /// Forget recent onsets, e.g. when a run starts.
    func resetOnsets() {
        processor?.resetOnsets()
    }

    func startRecording() {
        processor?.startRecording()
    }

    func stopRecording() {
        processor?.stopRecording { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let url): self?.lastRecording = url.lastPathComponent
                case .failure(let error): self?.lastRecording = "Save failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private var engine: AVAudioEngine?
    private var processor: ListenProcessor?

    func start() async {
        guard state != .running else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .denied
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            // Measurement mode turns off voice processing and automatic gain, which would distort the piano.
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try session.setPreferredSampleRate(48_000)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)

            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw NSError(domain: "Pianochou", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone input"])
            }

            let ring = SampleRing(capacity: Int(format.sampleRate * 2))
            let processor = ListenProcessor(ring: ring, sampleRate: format.sampleRate,
                                            inputLatency: session.inputLatency) { [weak self] update in
                Task { @MainActor in self?.receive(update) }
            }
            let sink = Self.makeSink(writingTo: ring)
            engine.attach(sink)
            engine.connect(input, to: sink, format: format)
            engine.prepare()
            try engine.start()

            processor.setExpected(expected)
            processor.start()
            self.engine = engine
            self.processor = processor
            sampleRate = format.sampleRate
            ioBufferDuration = session.ioBufferDuration
            inputLatency = session.inputLatency
            state = .running
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        processor?.stop()
        engine?.stop()
        processor = nil
        engine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if state == .running { state = .idle }
    }

    private func receive(_ update: ListenUpdate) {
        latest = update
        update.detections.forEach { onDetection?($0) }
    }

    /// Built outside the main actor: the block runs on the real-time audio thread.
    private nonisolated static func makeSink(writingTo ring: SampleRing) -> AVAudioSinkNode {
        AVAudioSinkNode { timestamp, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
            guard let first = buffers.first, let data = first.mData else { return noErr }
            // Non-interleaved float: the first buffer is channel 0.
            ring.write(data.assumingMemoryBound(to: Float.self), count: Int(frameCount), hostTime: timestamp.pointee.mHostTime)
            return noErr
        }
    }
}
