import Foundation
import PianoCore

/// What the UI needs from one processing tick.
struct ListenUpdate: Sendable {
    struct Detection: Sendable {
        var kind: NoteListener.Event.Kind
        /// Key strike to detection, as measured by the algorithm alone.
        var algorithmLatency: Double
        /// Key strike to the app knowing about it: algorithm + buffering + input hardware.
        var totalLatency: Double
    }

    var salience: [Int: Float] = [:]
    var sounding: Set<Int> = []
    var peakLevelDb: Float = -120
    var detections: [Detection] = []
    /// Processing time as a fraction of audio time.
    var load: Double = 0
    /// Seconds recorded so far, when recording.
    var recordingDuration: Double?
}

/// Owns the NoteListener and runs it on its own serial queue, pulling samples from the ring.
final class ListenProcessor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "pianochou.listen", qos: .userInteractive)
    private let ring: SampleRing
    private let sampleRate: Double
    private let inputLatency: Double
    private let onUpdate: @Sendable (ListenUpdate) -> Void

    // Everything below is only touched on `queue`.
    private var listener: NoteListener
    private var expected: Set<Int> = []
    private var streamStart = 0
    private var nextIndex = 0
    private var scratch: [Float] = []
    private var timer: DispatchSourceTimer?
    private var lastPublish: UInt64 = 0
    private var busySeconds = 0.0
    private var audioSeconds = 0.0
    private var recorder: SessionRecorder?
    /// Listener stream time at which the recording started.
    private var recordingOffset = 0.0

    init(ring: SampleRing, sampleRate: Double, inputLatency: Double, onUpdate: @escaping @Sendable (ListenUpdate) -> Void) {
        self.ring = ring
        self.sampleRate = sampleRate
        self.inputLatency = inputLatency
        self.onUpdate = onUpdate
        listener = NoteListener(sampleRate: sampleRate)
        scratch.reserveCapacity(Int(sampleRate))
    }

    func start() {
        queue.async {
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
        }
    }

    func setExpected(_ pitches: Set<Int>) {
        queue.async {
            self.expected = pitches
            self.listener.expected = pitches
            self.listener.resetOnsets()
            self.recorder?.noteExpected(pitches)
        }
    }

    func startRecording() {
        queue.async {
            self.recorder = SessionRecorder(sampleRate: self.sampleRate, expected: self.expected)
            // The next sample read will be recording time zero.
            self.recordingOffset = -Double(self.nextIndex - self.streamStart) / self.sampleRate
        }
    }

    /// Saves and returns the recording's URL (or the error) on the processor queue.
    func stopRecording(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        queue.async {
            guard let recorder = self.recorder else { return }
            self.recorder = nil
            completion(Result { try recorder.save() })
        }
    }

    private func tick() {
        let first = ring.readAvailable(into: &scratch)
        guard !scratch.isEmpty else { return }
        if first != nextIndex {
            // Samples were dropped; start a fresh timeline so times stay correct.
            listener = NoteListener(sampleRate: sampleRate)
            listener.expected = expected
            streamStart = first
        }
        nextIndex = first + scratch.count

        recorder?.append(scratch)
        let started = HostClock.now
        let events = listener.process(scratch)
        if let recorder { events.forEach { recorder.note($0, offset: recordingOffset) } }
        let now = HostClock.now
        busySeconds += HostClock.seconds(now - started)
        audioSeconds += Double(scratch.count) / sampleRate

        let detections = events.map { event -> ListenUpdate.Detection in
            let strikeSample = streamStart + Int(event.onsetTime * sampleRate)
            let strikeHost = ring.hostTime(forSample: strikeSample, sampleRate: sampleRate)
            let sinceStrike = now > strikeHost ? HostClock.seconds(now - strikeHost) : 0
            return .init(kind: event.kind,
                         algorithmLatency: event.detectedAt - event.onsetTime,
                         totalLatency: sinceStrike + inputLatency)
        }

        guard !detections.isEmpty || HostClock.seconds(now - lastPublish) > 1.0 / 30 else { return }
        lastPublish = now
        var update = ListenUpdate()
        for midi in expected {
            update.salience[midi] = listener.salience(of: midi)
            if listener.isSounding(midi) { update.sounding.insert(midi) }
        }
        update.peakLevelDb = listener.peakLevelDb
        update.detections = detections
        update.load = audioSeconds > 0 ? busySeconds / audioSeconds : 0
        update.recordingDuration = recorder?.duration
        if audioSeconds > 2 {
            busySeconds /= 2
            audioSeconds /= 2
        }
        onUpdate(update)
    }
}
