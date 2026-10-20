import PianoCore
import SwiftUI

/// Pick bars, hands and tempo, then go to the piano.
struct SetupView: View {
    let library: ScoreLibrary
    let entry: ScoreEntry
    @State private var settings: PracticeSettings?
    @State private var playing = false

    var body: some View {
        Group {
            if let score = library.score(entry), let settings {
                form(score, settings)
            } else {
                Text("Couldn't open this score.")
                    .font(Theme.text(17))
                    .foregroundStyle(Theme.fix)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.paper)
        .onAppear {
            Orientation.lock(.portrait)
            if settings == nil, let score = library.score(entry) {
                settings = library.settings(for: entry) ?? .defaults(for: score)
                // Debug: `-autoStart YES` goes straight to the piano.
                if UserDefaults.standard.bool(forKey: "autoStart") { playing = true }
            }
        }
        .onChange(of: settings) { _, new in
            if let new { library.save(new, for: entry) }
        }
        .navigationDestination(isPresented: $playing) {
            if let score = library.score(entry), let settings {
                PlayingView(score: score, settings: settings) { self.settings = $0 }
            }
        }
    }

    private func form(_ score: Score, _ current: PracticeSettings) -> some View {
        let measures = score.parts[0].measures
        let length = current.lastBar - current.firstBar + 1
        return VStack(alignment: .leading, spacing: 28) {
            Text(entry.title)
                .font(Theme.text(32, relativeTo: .title))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)

            StaffView(engraving: Engraver.engrave(score, measures: current.firstBar..<(current.lastBar + 1)), maximumSpace: 9)
                .frame(maxWidth: .infinity, alignment: .leading)

            NumberStepper(label: "From bar", value: measures[current.firstBar].number,
                          canDecrease: current.firstBar > 0, canIncrease: current.firstBar < measures.count - 1) { step in
                update { s in
                    s.firstBar = min(max(0, s.firstBar + step), measures.count - 1)
                    s.lastBar = min(s.firstBar + length - 1, measures.count - 1)
                }
            }
            NumberStepper(label: "Bars", value: "\(length)",
                          canDecrease: length > 1, canIncrease: length < 4 && current.lastBar < measures.count - 1) { step in
                update { s in s.lastBar = min(max(s.firstBar, s.lastBar + step), measures.count - 1) }
            }
            if score.parts[0].staves > 1 {
                Picker("Hands", selection: Binding(get: { current.handsValue }, set: { hands in update { $0.hands = hands.rawValue } })) {
                    Text("Right").tag(Hands.right)
                    Text("Left").tag(Hands.left)
                    Text("Both").tag(Hands.both)
                }
                .pickerStyle(.segmented)
            }
            NumberStepper(label: "Tempo", value: "\(Int(current.tempo))",
                          canDecrease: current.tempo > 30, canIncrease: current.tempo < 240) { step in
                update { s in s.tempo = min(max(30, s.tempo + Double(step) * 5), 240) }
            }

            Spacer(minLength: 0)
            Button("Start") { playing = true }
                .buttonStyle(PillStyle(filled: true))
        }
        .padding(24)
    }

    private func update(_ change: (inout PracticeSettings) -> Void) {
        guard var s = settings else { return }
        change(&s)
        settings = s
    }
}

/// A label, a big number, and − / + buttons.
struct NumberStepper: View {
    let label: String
    let value: String
    var canDecrease = true
    var canIncrease = true
    let step: (Int) -> Void

    var body: some View {
        HStack {
            Text(label)
                .font(Theme.text(17))
                .foregroundStyle(Theme.muted)
            Spacer()
            round("minus", enabled: canDecrease) { step(-1) }
                .accessibilityLabel("Less")
            Text(value)
                .font(Theme.text(30).weight(.light))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 64)
            round("plus", enabled: canIncrease) { step(1) }
                .accessibilityLabel("More")
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(value)
    }

    private func round(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .frame(width: 48, height: 48)
                .overlay(Circle().stroke(Theme.hairline))
                .contentShape(Circle())
        }
        .foregroundStyle(enabled ? Theme.ink : Theme.hairline)
        .disabled(!enabled)
    }
}
