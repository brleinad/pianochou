import Foundation

/// Turns a stream of mono samples into overlapping magnitude spectra (Hann window).
/// Magnitudes are scaled so a sine of amplitude A peaks at about A.
final class SpectrumAnalyzer {
    let sampleRate: Double
    let fftSize: Int
    let hopSize: Int
    var binHz: Double { sampleRate / Double(fftSize) }

    /// Magnitudes of the latest frame, `fftSize / 2 + 1` bins.
    private(set) var magnitudes: [Float]
    /// Stream time (seconds) of the newest sample in the latest frame.
    private(set) var frameTime: Double = 0

    private var fft: FFT
    private let window: [Float]
    private let scale: Float
    private var ring: [Float]
    private var ringWrite = 0
    private var samplesSeen = 0
    private var samplesSinceFrame = 0
    private var frameInput: [Float]

    init(sampleRate: Double, fftSize: Int = Tuning.fftSize, hopSize: Int = Tuning.hopSize) {
        self.sampleRate = sampleRate
        self.fftSize = fftSize
        self.hopSize = hopSize
        fft = FFT(size: fftSize)
        window = (0..<fftSize).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(fftSize))) }
        scale = 2 / window.reduce(0, +)
        ring = Array(repeating: 0, count: fftSize)
        frameInput = Array(repeating: 0, count: fftSize)
        magnitudes = Array(repeating: 0, count: fftSize / 2 + 1)
    }

    /// Feeds samples; calls `onFrame` once per completed hop (zero or more times).
    func process(_ samples: UnsafeBufferPointer<Float>, onFrame: () -> Void) {
        for sample in samples {
            ring[ringWrite] = sample
            ringWrite = (ringWrite + 1) % fftSize
            samplesSeen += 1
            samplesSinceFrame += 1
            if samplesSinceFrame >= hopSize && samplesSeen >= fftSize {
                samplesSinceFrame = 0
                computeFrame()
                onFrame()
            }
        }
    }

    private func computeFrame() {
        for i in 0..<fftSize {
            frameInput[i] = ring[(ringWrite + i) % fftSize] * window[i]
        }
        fft.magnitudes(of: frameInput, into: &magnitudes)
        for k in magnitudes.indices { magnitudes[k] *= scale }
        frameTime = Double(samplesSeen) / sampleRate
    }
}
