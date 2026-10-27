import PianoCore
import SwiftUI

/// Any number of bars at a readable size, scrolling sideways. Drawn in tiles, so a whole song doesn't
/// become one enormous canvas. While playing it can follow the next notes on its own.
struct ScrollingStaffView: View {
    let engraving: Engraving
    var currentTime: Rational?
    var mark: (Engraving.NoteRef) -> NoteMark = { _ in .upcoming }
    /// Points per staff space; nil fits the staff to the height available.
    var space: CGFloat?
    /// Keep the next notes in view, `Tuning.followPosition` of the way across.
    var follows = false

    @State private var position = ScrollPosition(edge: .leading)
    private static let tileWidth: CGFloat = 600

    var body: some View {
        GeometryReader { geometry in
            let unit = space ?? geometry.size.height / engraving.height
            let tile = Double(Self.tileWidth / unit)
            let count = max(1, Int((engraving.width / tile).rounded(.up)))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { i in
                        let range = Double(i) * tile...min(engraving.width, Double(i + 1) * tile)
                        StaffView(engraving: engraving, currentTime: currentTime, mark: mark, tile: (range, unit))
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

    private func follow(width: CGFloat, unit: CGFloat) {
        guard follows else { return }
        let x = currentTime.flatMap(engraving.x(at:)) ?? 0
        let target = max(0, x * unit - width * Tuning.followPosition)
        withAnimation(.easeInOut(duration: 0.3)) { position.scrollTo(x: target) }
    }
}
