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
        let last = measures.count - 1
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(entry.title)
                        .font(Theme.text(32, relativeTo: .title))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)

                    // The chosen bars, scrolling sideways.
                    ScrollingStaffView(engraving: Engraver.engrave(score, measures: current.firstBar..<(current.lastBar + 1)), space: 8)

                    NumberStepper(label: "From bar", value: measures[current.firstBar].number,
                                  canDecrease: current.firstBar > 0, canIncrease: current.firstBar < last) { step in
                        update { s in
                            s.firstBar = min(max(0, s.firstBar + step), last)
                            s.lastBar = max(s.lastBar, s.firstBar)
                        }
                    }
                    NumberStepper(label: "To bar", value: measures[current.lastBar].number,
                                  canDecrease: current.lastBar > current.firstBar, canIncrease: current.lastBar < last) { step in
                        update { s in s.lastBar = min(max(s.firstBar, s.lastBar + step), last) }
                    }
                    Button("Whole song") { update { s in s.firstBar = 0; s.lastBar = last } }
                        .font(Theme.text(15))
                        .foregroundStyle(current.firstBar == 0 && current.lastBar == last ? Theme.muted : Theme.now)
                        .disabled(current.firstBar == 0 && current.lastBar == last)
                        .frame(minHeight: 44)
                    if score.parts[0].staves > 1 {
                        Picker("Hands", selection: Binding(get: { current.handsValue }, set: { hands in update { $0.hands = hands.rawValue } })) {
                            Text("Right").tag(Hands.right)
                            Text("Left").tag(Hands.left)
                            Text("Both").tag(Hands.both)
                        }
                        .pickerStyle(.segmented)
                    }
                    NumberStepper(label: "Tempo", value: "\(Int(current.tempo))",
                                  canDecrease: current.tempo > Tuning.tempoRange.lowerBound,
                                  canIncrease: current.tempo < Tuning.tempoRange.upperBound) { step in
                        update { s in s.tempo = Metronome.step(s.tempo, by: step) }
                    }
                }
                .padding(24)
            }
            // Always in reach, whichever way the phone is held.
            Button("Start") { playing = true }
                .buttonStyle(PillStyle(filled: true))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
        }
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
        .buttonRepeatBehavior(.enabled)
        .foregroundStyle(enabled ? Theme.ink : Theme.hairline)
        .disabled(!enabled)
    }
}
