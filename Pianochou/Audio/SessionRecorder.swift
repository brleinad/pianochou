import Foundation
import PianoCore

/// Records raw microphone audio plus what the listener decided, so a session can be replayed
/// on a Mac (`swift run listen-replay`). Files go to Documents/recordings/, visible in the Files app
/// and copyable with `xcrun devicectl device copy from`.
/// Only used on the processor queue.
final class SessionRecorder {
    static let maxSeconds = 120.0

    private let sampleRate: Double
    private var samples: [Float] = []
    private var expectedChanges: [[String: Any]] = []
    private var events: [[String: Any]] = []

    init(sampleRate: Double, expected: Set<Int>) {
        self.sampleRate = sampleRate
        samples.reserveCapacity(Int(sampleRate * 30))
        noteExpected(expected)
    }

    var duration: Double { Double(samples.count) / sampleRate }
    var isFull: Bool { duration >= Self.maxSeconds }

    func append(_ chunk: [Float]) {
        guard !isFull else { return }
        samples.append(contentsOf: chunk)
    }

    func noteExpected(_ pitches: Set<Int>) {
        expectedChanges.append(["time": duration, "midi": pitches.sorted()])
    }

    /// `offset` converts listener stream time to recording time (seconds).
    func note(_ event: NoteListener.Event, offset: Double) {
        var entry: [String: Any] = ["time": event.onsetTime + offset, "detectedAt": event.detectedAt + offset]
        switch event.kind {
        case .expected(let midi): entry["kind"] = "expected"; entry["midi"] = midi
        case .unexpected(let guess): entry["kind"] = "unexpected"; entry["midi"] = guess
        }
        events.append(entry)
    }

    /// Writes `<name>.wav` (32-bit float, mono) and `<name>.json`. Returns the WAV URL.
    func save() throws -> URL {
        let folder = URL.documentsDirectory.appending(path: "recordings", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)
            .dateTimeSeparator(.standard).timeSeparator(.omitted))
        let name = "listen-\(stamp.replacingOccurrences(of: " ", with: "-"))"
        let wav = folder.appending(path: "\(name).wav")
        try wavData().write(to: wav)

        let info: [String: Any] = [
            "sampleRate": sampleRate,
            "duration": duration,
            "appVersion": PianoCore.version,
            "expectedChanges": expectedChanges,
            "events": events,
        ]
        try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
            .write(to: folder.appending(path: "\(name).json"))
        return wav
    }

    private func wavData() -> Data {
        var data = Data()
        func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let byteCount = UInt32(samples.count * 4)
        data.append(contentsOf: Array("RIFF".utf8)); put(36 + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); put(UInt32(16))
        put(UInt16(3)) // IEEE float
        put(UInt16(1)) // mono
        put(UInt32(sampleRate)); put(UInt32(sampleRate) * 4)
        put(UInt16(4)); put(UInt16(32))
        data.append(contentsOf: Array("data".utf8)); put(byteCount)
        samples.withUnsafeBufferPointer { data.append(UnsafeBufferPointer(start: UnsafeRawPointer($0.baseAddress!).assumingMemoryBound(to: UInt8.self), count: $0.count * 4)) }
        return data
    }
}
