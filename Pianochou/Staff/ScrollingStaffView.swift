import PianoCore
import SwiftUI

/// Any number of bars at a readable size, scrolling sideways. Drawn in tiles, so a whole song doesn't
/// become one enormous canvas. While playing it can follow the next notes on its own.
struct ScrollingStaffView: View {
    let engraving: Engraving
    var currentTime: Rational?
    var mark: (Engraving.NoteRef) -> NoteMark = { _ in .upcoming }
    /// Points per staff space; nil fits the staff to the height available, up to `maximumSpace`.
    var space: CGFloat?
    var maximumSpace: CGFloat = 14
    /// Keep the next notes in view, `Tuning.followPosition` of the way across.
    var follows = false
    /// How long to hold each note, drawn under it, filled up to the playhead as it moves.
    var holdBars: [HoldBar] = []
    var playhead: ((Date) -> Rational?)?

    @State private var position = ScrollPosition(edge: .leading)
    private static let tileWidth: CGFloat = 600

    var body: some View {
        GeometryReader { geometry in
            let unit = space ?? min(geometry.size.height / engraving.height, maximumSpace)
            let tile = Double(Self.tileWidth / unit)
            let count = max(1, Int((engraving.width / tile).rounded(.up)))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { i in
                        let range = Double(i) * tile...min(engraving.width, Double(i + 1) * tile)
                        ZStack(alignment: .topLeading) {
                            if !holdBars.isEmpty { holds(range, unit: unit) }
                            StaffView(engraving: engraving, currentTime: currentTime, mark: mark, tile: (range, unit))
                        }
                        .frame(width: (range.upperBound - range.lowerBound) * unit, height: engraving.height * unit)
                    }
                }
            }
            .scrollPosition($position)
            .onChange(of: currentTime, initial: true) { follow(width: geometry.size.width, unit: unit) }
            // The screen turning to landscape changes the scale: find the notes again.
            .onChange(of: geometry.size) { follow(width: geometry.size.width, unit: unit) }
        }
        .frame(height: space.map { engraving.height * $0 })
        .accessibilityElement()
        .accessibilityLabel("Staff")
    }

    /// The hold bars of one tile: faint for the whole length, filled up to the playhead, which is a thin
    /// line. Redrawn every frame on their own, under the (static) staff.
    private func holds(_ range: ClosedRange<Double>, unit: CGFloat) -> some View {
        let bars = holdBars.filter { $0.x1 >= range.lowerBound && $0.x0 <= range.upperBound }
        return TimelineView(.animation(paused: playhead == nil)) { timeline in
            Canvas { context, size in
                context.translateBy(x: -range.lowerBound * unit, y: 0)
                let now = playhead?(timeline.date)
                let x = now.flatMap(engraving.x(at:))
                for bar in bars {
                    let rect = CGRect(x: bar.x0 * unit, y: (bar.y - 0.35) * unit, width: max(0, bar.x1 - bar.x0) * unit, height: 0.7 * unit)
                    context.fill(Path(roundedRect: rect, cornerRadius: 0.35 * unit), with: .color(Theme.hairline))
                    if let now, let x, now > bar.start {
                        var filled = rect
                        filled.size.width = max(0, min(x, bar.x1) - bar.x0) * unit
                        context.fill(Path(roundedRect: filled, cornerRadius: 0.35 * unit), with: .color(Theme.now.opacity(0.35)))
                    }
                }
                if let x, range.contains(x) {
                    let line = CGRect(x: x * unit - 0.08 * unit, y: 0, width: 0.16 * unit, height: size.height)
                    context.fill(Path(line), with: .color(Theme.now.opacity(0.6)))
                }
            }
        }
    }

    private func follow(width: CGFloat, unit: CGFloat) {
        guard follows else { return }
        let x = currentTime.flatMap(engraving.x(at:)) ?? 0
        let target = max(0, x * unit - width * Tuning.followPosition)
        withAnimation(.easeInOut(duration: 0.3)) { position.scrollTo(x: target) }
    }
}
