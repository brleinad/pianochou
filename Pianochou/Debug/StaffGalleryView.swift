import PianoCore
import SwiftUI

/// Every test fixture, two bars at a time, for checking the staff renderer by eye.
/// "Overlays" fakes a run in progress: earlier notes played, one mistake, the current beat highlighted.
struct StaffGalleryView: View {
    @State private var overlays = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Toggle("Overlays", isOn: $overlays)
                    .font(Theme.text(17))
                    .tint(Theme.now)
                ForEach(Self.shown, id: \.self) { name in
                    SampleStaves(name: name, overlays: overlays)
                }
            }
            .padding(16)
        }
        .background(Theme.paper)
        .navigationTitle("Staff")
    }

    /// Launch with `-galleryFrom <fixture>` to start the list there (for simulator screenshots).
    static var shown: [String] {
        guard let from = UserDefaults.standard.string(forKey: "galleryFrom"),
              let index = SampleScores.names.firstIndex(of: from) else { return SampleScores.names }
        return Array(SampleScores.names[index...])
    }
}

/// One fixture, split into two-bar windows.
struct SampleStaves: View {
    let name: String
    var overlays = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(Theme.text(13))
                .foregroundStyle(Theme.muted)
            if let score = SampleScores.score(name) {
                ForEach(Self.windows(score), id: \.lowerBound) { range in
                    window(score, range)
                }
            } else {
                Text("Couldn't load \(name)")
                    .foregroundStyle(Theme.fix)
            }
        }
    }
}

extension SampleStaves {
    static func windows(_ score: Score) -> [Range<Int>] {
        let count = score.parts[0].measures.count
        return stride(from: 0, to: count, by: 2).map { $0..<min($0 + 2, count) }
    }

    func window(_ score: Score, _ range: Range<Int>) -> StaffView {
        let engraving = Engraver.engrave(score, measures: range)
        guard overlays else { return StaffView(engraving: engraving, maximumSpace: 9) }
        let demo = Demo(score: score, engraving: engraving)
        return StaffView(engraving: engraving, currentTime: demo.current, mark: demo.mark, maximumSpace: 9)
    }
}

/// A pretend run: the third onset is current, everything before it is played, and the first
/// note of the window's second onset was a mistake.
private struct Demo {
    let score: Score
    let current: Rational?
    let mistake: Rational?

    init(score: Score, engraving: Engraving) {
        self.score = score
        let onsets = Array(Set(engraving.items.filter { $0.role == .notehead }.compactMap(\.time))).sorted()
        current = onsets.count > 2 ? onsets[2] : onsets.last
        mistake = onsets.count > 2 ? onsets[1] : nil
    }

    func mark(_ ref: Engraving.NoteRef) -> NoteMark {
        guard let current else { return .upcoming }
        let measure = score.parts[0].measures[ref.measure]
        let event = measure.events[ref.event]
        let time = measure.start + event.onset
        if time == mistake && (ref.note ?? 0) == 0 && event.staff == 1 { return .mistake }
        return time < current ? .played : .upcoming
    }
}

/// The PianoCore test fixtures, bundled into the app for the gallery and previews.
enum SampleScores {
    static let names = ["engraving-sampler", "c-major-scale", "waltz-3-4", "triplets", "two-voices",
                        "clef-change", "key-change", "pickup", "repeat-endings"]

    private static let scores: [String: Score] = Dictionary(uniqueKeysWithValues: names.compactMap { name in
        guard let url = Bundle.main.url(forResource: name, withExtension: "musicxml"),
              let score = try? MusicXMLImporter.parse(url: url) else { return nil }
        return (name, score)
    })

    static func score(_ name: String) -> Score? { scores[name] }
}

#Preview("Gallery") {
    NavigationStack { StaffGalleryView() }
}

#Preview("Sampler, dark", traits: .landscapeLeft) {
    SampleStaves(name: "engraving-sampler")
        .padding()
        .background(Theme.paper)
        .preferredColorScheme(.dark)
}

#Preview("c-major-scale") { SampleStaves(name: "c-major-scale").padding() }
#Preview("waltz-3-4") { SampleStaves(name: "waltz-3-4").padding() }
#Preview("triplets") { SampleStaves(name: "triplets").padding() }
#Preview("two-voices") { SampleStaves(name: "two-voices").padding() }
#Preview("clef-change") { SampleStaves(name: "clef-change").padding() }
#Preview("key-change") { SampleStaves(name: "key-change").padding() }
#Preview("pickup") { SampleStaves(name: "pickup").padding() }
#Preview("repeat-endings") { SampleStaves(name: "repeat-endings").padding() }
