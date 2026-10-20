// Replays a Listen-test recording through NoteListener on the Mac.
//
//   swift run listen-replay rec.wav                 events (expected notes from rec.json)
//   swift run listen-replay rec.wav --expect 60,64  override expected notes
//   swift run listen-replay rec.wav --trace 60 --from 1.2 --to 2.0   per-frame internals for one pitch
import Foundation
import PianoCore

let args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
guard let path = args.first(where: { $0.hasSuffix(".wav") }) else {
    print("usage: listen-replay <recording.wav> [--expect 60,64] [--trace 60 --from s --to s]")
    exit(2)
}

// MARK: Read WAV (float32 or int16; first channel)

func readWav(_ url: URL) throws -> (samples: [Float], sampleRate: Double) {
    let data = try Data(contentsOf: url)
    func u16(_ o: Int) -> Int { Int(data[o]) | Int(data[o + 1]) << 8 }
    func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
    guard data.count > 44, String(decoding: data[0..<4], as: UTF8.self) == "RIFF" else {
        throw NSError(domain: "wav", code: 1, userInfo: [NSLocalizedDescriptionKey: "not a WAV file"])
    }
    var offset = 12
    var format = 0, channels = 1, rate = 48_000, bits = 16
    while offset + 8 <= data.count {
        let id = String(decoding: data[offset..<offset + 4], as: UTF8.self)
        let size = u32(offset + 4)
        let body = offset + 8
        if id == "fmt " {
            format = u16(body); channels = u16(body + 2); rate = u32(body + 4); bits = u16(body + 14)
        } else if id == "data" {
            let frameBytes = channels * bits / 8
            let count = min(size, data.count - body) / frameBytes
            var samples = [Float](repeating: 0, count: count)
            data.withUnsafeBytes { raw in
                for i in 0..<count {
                    let o = body + i * frameBytes
                    if format == 3 && bits == 32 {
                        samples[i] = Float(bitPattern: UInt32(u32(o)))
                    } else if bits == 16 {
                        samples[i] = Float(Int16(bitPattern: UInt16(u16(o)))) / 32768
                    }
                }
            }
            return (samples, Double(rate))
        }
        offset = body + size + (size & 1)
    }
    throw NSError(domain: "wav", code: 2, userInfo: [NSLocalizedDescriptionKey: "no data chunk"])
}

let url = URL(fileURLWithPath: path)
let (samples, sampleRate) = try readWav(url)

// MARK: Expected notes over time

var changes: [(time: Double, midi: Set<Int>)] = []
var phoneEvents: [[String: Any]] = []
let sidecar = url.deletingPathExtension().appendingPathExtension("json")
if let data = try? Data(contentsOf: sidecar),
   let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
    for change in info["expectedChanges"] as? [[String: Any]] ?? [] {
        changes.append((change["time"] as? Double ?? 0, Set(change["midi"] as? [Int] ?? [])))
    }
    phoneEvents = info["events"] as? [[String: Any]] ?? []
}
if let list = option("--expect") {
    changes = [(0, Set(list.split(separator: ",").compactMap { Int($0) }))]
}
let traceMidi = option("--trace").flatMap { Int($0) }
let from = option("--from").flatMap(Double.init) ?? 0
let to = option("--to").flatMap(Double.init) ?? .infinity

print(String(format: "%@: %.1f s at %.0f Hz, peak %.1f dBFS", url.lastPathComponent, Double(samples.count) / sampleRate,
             sampleRate, 20 * log10(Double(samples.map(abs).max() ?? 1e-9))))
for change in changes {
    print(String(format: "  expect from %6.2f s: %@", change.time, change.midi.sorted().map(Pitch.name(midi:)).joined(separator: " ")))
}

// MARK: Replay

let listener = NoteListener(sampleRate: sampleRate)
var nextChange = 0
var events: [NoteListener.Event] = []
let hop = Tuning.hopSize
var index = 0
if traceMidi != nil { print("   time    sal   rise  snd armed  flux  eRise  lRise") }
while index < samples.count {
    let time = Double(index) / sampleRate
    while nextChange < changes.count && changes[nextChange].time <= time {
        // Like the app: changing what's expected keeps onset memory, so a ringing note isn't heard twice.
        listener.expected = changes[nextChange].midi
        nextChange += 1
    }
    let chunk = Array(samples[index..<min(samples.count, index + hop)])
    let new = listener.process(chunk)
    events += new
    index += hop
    if let midi = traceMidi, listener.currentTime >= from, listener.currentTime <= to {
        let d = listener.diagnostics(for: midi)
        let marks = new.map { e -> String in
            switch e.kind {
            case .expected(let m): "<< \(Pitch.name(midi: m)) onset @\(String(format: "%.3f", e.onsetTime))"
            case .unexpected(let g): "?? \(Pitch.name(midi: g))"
            }
        }.joined(separator: " ")
        print(String(format: "%7.3f %6.1f %6.1f  %@   %@  %5.1f %6.1f %6.1f  %@", listener.currentTime, d.salience, d.rise,
                     d.sounding ? "*" : ".", d.armed ? "y" : "n", d.flux, d.energyRise, d.levelRise, marks))
    }
}

print("\nReplay detected \(events.count) events:")
for e in events {
    switch e.kind {
    case .expected(let m): print(String(format: "  %7.3f  %@", e.onsetTime, Pitch.name(midi: m)))
    case .unexpected(let g): print(String(format: "  %7.3f  unexpected (heard %@)", e.onsetTime, Pitch.name(midi: g)))
    }
}
if !phoneEvents.isEmpty {
    print("Phone logged \(phoneEvents.count) events during the session.")
}
