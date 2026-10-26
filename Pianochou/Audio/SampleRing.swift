import Foundation
import os

/// Hands samples from the real-time audio thread to the processing queue.
/// One writer, one reader; a short unfair lock guards the indices. The writer never allocates.
final class SampleRing: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var storage: [Float]
    /// Total samples ever written / read; indices into the stream, not the storage.
    private var written = 0
    private var read = 0
    /// Host time of the most recent write's first sample, to map stream positions to clock time.
    private var anchorSample = 0
    private var anchorHostTime: UInt64 = 0

    init(capacity: Int) {
        storage = Array(repeating: 0, count: capacity)
    }

    /// Called on the audio thread.
    func write(_ samples: UnsafePointer<Float>, count: Int, hostTime: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        anchorSample = written
        anchorHostTime = hostTime
        let capacity = storage.count
        let start = written
        storage.withUnsafeMutableBufferPointer { buffer in
            for i in 0..<count { buffer[(start + i) % capacity] = samples[i] }
        }
        written += count
        if written - read > capacity { read = written - capacity } // reader fell behind: drop the oldest
    }

    /// Copies everything not yet read into `out`. Returns the stream index of the first sample.
    func readAvailable(into out: inout [Float]) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let first = read
        let count = written - read
        out.removeAll(keepingCapacity: true)
        let capacity = storage.count
        for i in 0..<count { out.append(storage[(first + i) % capacity]) }
        read = written
        return first
    }

    /// Stream position of a clock time (mach host ticks), the inverse of `hostTime(forSample:)`.
    func sample(forHostTime time: UInt64, sampleRate: Double) -> Int {
        lock.lock()
        let sample = anchorSample, host = anchorHostTime
        lock.unlock()
        let seconds = time >= host ? HostClock.seconds(time - host) : -HostClock.seconds(host - time)
        return sample + Int((seconds * sampleRate).rounded())
    }

    /// Clock time (mach host ticks) of a stream position.
    func hostTime(forSample index: Int, sampleRate: Double) -> UInt64 {
        lock.lock()
        let sample = anchorSample, host = anchorHostTime
        lock.unlock()
        let offset = HostClock.ticks(seconds: Double(index - sample) / sampleRate)
        return offset >= 0 ? host &+ UInt64(offset) : host &- UInt64(-offset)
    }
}

enum HostClock {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static var now: UInt64 { mach_absolute_time() }

    static func seconds(_ ticks: UInt64) -> Double {
        Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1e9
    }

    static func ticks(seconds: Double) -> Int64 {
        Int64(seconds * 1e9 * Double(timebase.denom) / Double(timebase.numer))
    }
}
