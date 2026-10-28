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
    /// When `latest` arrived, to tell the stream time between updates.
    private(set) var latestArrived = Date()

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
    private var player: AVAudioPlayerNode?
    private var music: AVAudioPlayerNode?
    private var clickFormat: AVAudioFormat?

    private let clickSound = try? Metronome.Sound.bundled()

    /// Loops metronome clicks for `time` at `tempo` through the speaker while listening; nil stops them.
    /// The processor learns when each click will reach the microphone, so they aren't heard as notes.
    func setClicks(_ clicks: (time: TimeSignature, tempo: Double)?) {
        guard let player, let format = clickFormat, let processor else { return }
        player.stop()
        processor.setClicks(firstArrival: nil, period: 0)
        guard let clicks, let sound = clickSound else { return }
        let bar = Metronome.bar(clicks.time, tempo: clicks.tempo, sampleRate: format.sampleRate, sound: sound)
        guard !bar.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(bar.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(bar.count)
        bar.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: bar.count) }
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        // Start at a known moment, so every click's arrival at the microphone is known.
        let start = HostClock.now &+ UInt64(HostClock.ticks(seconds: 0.1))
        player.play(at: AVAudioTime(hostTime: start))
        let latency = AVAudioSession.sharedInstance().outputLatency + Tuning.clickArrivalOffset
        processor.setClicks(firstArrival: start &+ UInt64(HostClock.ticks(seconds: latency)),
                            period: Metronome.beatSeconds(clicks.time, tempo: clicks.tempo))
    }

    /// Plays mono `samples` (at `outputSampleRate`) through the speaker. Returns when the first sample
    /// will be heard, or nil when not running.
    func play(_ samples: [Float]) -> Date? {
        guard let music, let format = clickFormat, !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        music.stop()
        music.scheduleBuffer(buffer, at: nil)
        let lead = 0.1
        music.play(at: AVAudioTime(hostTime: HostClock.now &+ UInt64(HostClock.ticks(seconds: lead))))
        return Date().addingTimeInterval(lead + AVAudioSession.sharedInstance().outputLatency)
    }

    func stopPlaying() {
        music?.stop()
    }

    /// The rate `play` expects.
    var outputSampleRate: Double? { clickFormat?.sampleRate }

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
            // The metronome plays through the same engine, mono at the output's rate.
            let player = AVAudioPlayerNode()
            engine.attach(player)
            let clickFormat = AVAudioFormat(standardFormatWithSampleRate: engine.mainMixerNode.outputFormat(forBus: 0).sampleRate, channels: 1)
            engine.connect(player, to: engine.mainMixerNode, format: clickFormat)
            // Playing the bars back, the same way.
            let music = AVAudioPlayerNode()
            engine.attach(music)
            engine.connect(music, to: engine.mainMixerNode, format: clickFormat)
            engine.prepare()
            try engine.start()

            processor.setExpected(expected)
            processor.start()
            self.engine = engine
            self.processor = processor
            self.player = player
            self.music = music
            self.clickFormat = clickFormat
            sampleRate = format.sampleRate
            ioBufferDuration = session.ioBufferDuration
            inputLatency = session.inputLatency
            state = .running
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        player?.stop()
        music?.stop()
        processor?.stop()
        engine?.stop()
        processor = nil
        engine = nil
        player = nil
        music = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if state == .running { state = .idle }
    }

    private func receive(_ update: ListenUpdate) {
        latest = update
        latestArrived = .now
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
