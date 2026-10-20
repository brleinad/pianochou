import SwiftUI
import PianoCore

/// M2 debug screen: pick target notes, play them, see them light up, read latency.
struct ListenTestView: View {
    @State private var engine = ListenEngine()
    @State private var targets: Set<Int> = [60]
    @State private var stats = ListenStats()

    private static let presets: [(String, Set<Int>)] = [
        ("C4", [60]), ("A4", [69]), ("C5", [72]), ("C3", [48]), ("G2", [43]),
        ("C E G", [60, 64, 67]), ("A C E", [57, 60, 64]), ("F A C low", [41, 45, 48]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                status
                targetRow
                statsBlock
                presetRow
                KeyStrip(selected: $targets)
            }
            .padding(20)
        }
        .background(Theme.paper)
        .navigationTitle("Listen test")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            engine.expected = targets
            engine.onDetection = { stats.record($0) }
            await engine.start()
        }
        .onDisappear { engine.stop() }
        .onChange(of: targets) {
            engine.expected = targets
            stats = ListenStats()
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(engine.state == .running ? Theme.now : Theme.muted)
                    .frame(width: 10, height: 10)
                Text(statusText)
                    .font(Theme.text(15))
                    .foregroundStyle(Theme.muted)
            }
            LevelBar(db: engine.latest.peakLevelDb)
        }
    }

    private var statusText: String {
        switch engine.state {
        case .idle: "Starting…"
        case .denied: "Microphone access is off. Turn it on in Settings › Pianochou."
        case .failed(let message): "Audio failed: \(message)"
        case .running:
            String(format: "%.0f kHz · buffer %.1f ms · input %.1f ms · load %.0f%%",
                   engine.sampleRate / 1000, engine.ioBufferDuration * 1000,
                   engine.inputLatency * 1000, engine.latest.load * 100)
        }
    }

    private var targetRow: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            HStack(spacing: 20) {
                ForEach(targets.sorted(), id: \.self) { midi in
                    TargetCircle(
                        name: Pitch.name(midi: midi),
                        sounding: engine.latest.sounding.contains(midi),
                        flashing: stats.lastHit[midi].map { context.date.timeIntervalSince($0) < 0.3 } ?? false,
                        hits: stats.hits[midi, default: 0],
                        salience: engine.latest.salience[midi] ?? 0
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var statsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Latency", stats.lastTotal.map { ms($0) + "  (median \(ms(stats.medianTotal)))" } ?? "–")
            row("Algorithm", stats.lastAlgorithm.map { ms($0) } ?? "–")
            row("Unexpected", stats.unexpected == 0 ? "0"
                : "\(stats.unexpected)  (last heard \(stats.lastGuess.map(Pitch.name(midi:)) ?? ""))")
            Button("Reset counts") { stats = ListenStats() }
                .font(Theme.text(15))
                .frame(minHeight: 44)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).foregroundStyle(Theme.ink).monospacedDigit()
        }
        .font(Theme.text(17))
    }

    private func ms(_ seconds: Double) -> String { String(format: "%.0f ms", seconds * 1000) }

    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Self.presets, id: \.0) { preset in
                    Button(preset.0) { targets = preset.1 }
                        .font(Theme.text(16))
                        .foregroundStyle(targets == preset.1 ? Theme.paper : Theme.ink)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(targets == preset.1 ? Theme.ink : Theme.hairline))
                }
            }
        }
    }
}

/// Running numbers for the debug screen.
struct ListenStats {
    var hits: [Int: Int] = [:]
    var lastHit: [Int: Date] = [:]
    var unexpected = 0
    var lastGuess: Int?
    var lastTotal: Double?
    var lastAlgorithm: Double?
    private var totals: [Double] = []

    var medianTotal: Double {
        guard !totals.isEmpty else { return 0 }
        return totals.sorted()[totals.count / 2]
    }

    mutating func record(_ detection: ListenUpdate.Detection) {
        switch detection.kind {
        case .expected(let midi):
            hits[midi, default: 0] += 1
            lastHit[midi] = Date()
            lastTotal = detection.totalLatency
            lastAlgorithm = detection.algorithmLatency
            totals = Array((totals + [detection.totalLatency]).suffix(20))
        case .unexpected(let guess):
            unexpected += 1
            lastGuess = guess
        }
    }
}

private struct TargetCircle: View {
    let name: String
    let sounding: Bool
    let flashing: Bool
    let hits: Int
    let salience: Float

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(sounding ? Theme.now : Color.clear)
                Circle()
                    .strokeBorder(flashing ? Theme.now : Theme.hairline, lineWidth: flashing ? 6 : 2)
                Text(name)
                    .font(Theme.text(28).weight(.light))
                    .foregroundStyle(sounding ? Theme.paper : Theme.ink)
            }
            .frame(width: 96, height: 96)
            .animation(.easeOut(duration: 0.15), value: flashing)
            Text("\(hits)")
                .font(Theme.text(34).weight(.light))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
            Text(String(format: "%.0f dB", salience))
                .font(Theme.text(13))
                .foregroundStyle(Theme.muted)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LevelBar: View {
    let db: Float

    var body: some View {
        GeometryReader { geo in
            // -90 dBFS … 0 dBFS
            let fraction = CGFloat(max(0, min(1, (db + 90) / 90)))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline)
                Capsule().fill(db > -6 ? Theme.fix : Theme.ink).frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 4)
        .accessibilityLabel("Input level")
    }
}

/// Tap keys to choose target notes, C2–C7.
private struct KeyStrip: View {
    @Binding var selected: Set<Int>

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(36...96, id: \.self) { midi in
                        let black = [1, 3, 6, 8, 10].contains(midi % 12)
                        let on = selected.contains(midi)
                        Button {
                            if on { selected.remove(midi) } else { selected.insert(midi) }
                        } label: {
                            Text(midi % 12 == 0 ? Pitch.name(midi: midi) : "")
                                .font(Theme.text(11))
                                .foregroundStyle(on ? Theme.paper : (black ? Theme.paper : Theme.muted))
                                .frame(width: 30, height: black ? 64 : 88, alignment: .bottom)
                                .padding(.bottom, 6)
                                .background(RoundedRectangle(cornerRadius: 4)
                                    .fill(on ? Theme.now : (black ? Theme.ink : Theme.hairline)))
                        }
                        .accessibilityLabel(Pitch.name(midi: midi))
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .id(midi)
                    }
                }
            }
            .onAppear { proxy.scrollTo(60, anchor: .center) }
        }
    }
}

#Preview {
    NavigationStack { ListenTestView() }
}
