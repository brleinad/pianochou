import Foundation

/// Radix-2 complex FFT used for magnitude spectra. Plain Swift so PianoCore stays portable;
/// swap in vDSP in the app if profiling ever says so.
struct FFT {
    let size: Int
    private let cosTable: [Float]
    private let sinTable: [Float]
    private let bitReversed: [Int]
    private var real: [Float]
    private var imag: [Float]

    init(size: Int) {
        precondition(size > 1 && size & (size - 1) == 0, "FFT size must be a power of two")
        self.size = size
        let half = size / 2
        cosTable = (0..<half).map { Float(cos(2 * Double.pi * Double($0) / Double(size))) }
        sinTable = (0..<half).map { Float(sin(2 * Double.pi * Double($0) / Double(size))) }
        let bits = size.trailingZeroBitCount
        bitReversed = (0..<size).map { i in
            var result = 0
            for b in 0..<bits where i & (1 << b) != 0 { result |= 1 << (bits - 1 - b) }
            return result
        }
        real = Array(repeating: 0, count: size)
        imag = Array(repeating: 0, count: size)
    }

    /// `input` must have `size` samples. Writes `size / 2 + 1` magnitudes into `output`.
    mutating func magnitudes(of input: [Float], into output: inout [Float]) {
        let n = size
        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                input.withUnsafeBufferPointer { x in
                    bitReversed.withUnsafeBufferPointer { rev in
                        for i in 0..<n {
                            re[rev[i]] = x[i]
                            im[rev[i]] = 0
                        }
                    }
                }
                cosTable.withUnsafeBufferPointer { cosT in
                    sinTable.withUnsafeBufferPointer { sinT in
                        var length = 2
                        while length <= n {
                            let half = length / 2
                            let step = n / length
                            var start = 0
                            while start < n {
                                for k in 0..<half {
                                    let wr = cosT[k * step]
                                    let wi = -sinT[k * step]
                                    let a = start + k
                                    let b = a + half
                                    let tr = re[b] * wr - im[b] * wi
                                    let ti = re[b] * wi + im[b] * wr
                                    re[b] = re[a] - tr
                                    im[b] = im[a] - ti
                                    re[a] += tr
                                    im[a] += ti
                                }
                                start += length
                            }
                            length *= 2
                        }
                    }
                }
                output.withUnsafeMutableBufferPointer { out in
                    for k in 0...(n / 2) {
                        out[k] = (re[k] * re[k] + im[k] * im[k]).squareRoot()
                    }
                }
            }
        }
    }
}
