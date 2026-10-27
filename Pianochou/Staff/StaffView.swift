import CoreText
import PianoCore
import SwiftUI

/// How a note has gone so far in a run. The current notes are found from `currentTime` instead.
/// Early and late are the right note at the wrong time: drawn as played, with a tick before or after it.
enum NoteMark {
    case upcoming, played, early, late, mistake
}

/// Draws an `Engraving` scaled to fit the available width, with the playing overlays:
/// played notes faded, mistakes in the fix color, the current beat highlighted.
struct StaffView: View {
    let engraving: Engraving
    /// Score time of the notes to play next; nil hides the highlight.
    var currentTime: Rational?
    /// Mark per note (`ref.note` set) or per event (`ref.note` nil, for stems, beams, rests).
    var mark: (Engraving.NoteRef) -> NoteMark = { _ in .upcoming }
    var showsFingers = true
    var showsCounts = true
    /// Largest staff space in points, so a one-bar window isn't blown up to the full width.
    var maximumSpace: CGFloat = .infinity
    /// Draw only this stretch of the engraving (in staff spaces), at `space` points per staff space:
    /// one tile of a `ScrollingStaffView`. Nil: all of it, scaled to fit the width.
    var tile: (range: ClosedRange<Double>, space: CGFloat)?

    var body: some View {
        if let tile {
            canvas(tile)
        } else {
            canvas(nil)
                .aspectRatio(engraving.width / engraving.height, contentMode: .fit)
                .frame(maxWidth: engraving.width * maximumSpace)
                .accessibilityElement()
                .accessibilityLabel("Staff")
        }
    }

    private func canvas(_ tile: (range: ClosedRange<Double>, space: CGFloat)?) -> some View {
        Canvas { context, size in
            let unit = tile?.space ?? size.width / engraving.width
            let shown = tile?.range ?? 0...engraving.width
            context.translateBy(x: -shown.lowerBound * unit, y: 0)
            if let currentTime, let x = engraving.x(at: currentTime), shown.overlaps(x - 1.8...x + 1.8) {
                let band = CGRect(x: (x - 1.8) * unit, y: 0, width: 3.6 * unit, height: size.height)
                context.fill(Path(roundedRect: band, cornerRadius: 0.8 * unit), with: .color(Theme.band))
            }
            for item in engraving.items where tile == nil || Self.extent(item).overlaps(shown) {
                draw(item, in: &context, unit: unit)
            }
        }
    }

    /// Roughly how far across an item reaches, in staff spaces (generous: glyphs are at most ~4 wide).
    static func extent(_ item: Engraving.Item) -> ClosedRange<Double> {
        switch item.shape {
        case let .glyph(_, at, scale): return (at.x - 1)...(at.x + 4 * scale)
        case let .line(from, to, _), let .beam(from, to, _), let .tie(from, to, _):
            return (min(from.x, to.x) - 1)...(max(from.x, to.x) + 1)
        case let .text(_, at, size): return (at.x - 2 * size)...(at.x + 2 * size)
        }
    }

    private func draw(_ item: Engraving.Item, in context: inout GraphicsContext, unit: CGFloat) {
        if item.role == .finger && !showsFingers || item.role == .count && !showsCounts { return }
        let color = color(for: item)
        func point(_ p: Engraving.Point) -> CGPoint { CGPoint(x: p.x * unit, y: p.y * unit) }

        switch item.shape {
        case let .glyph(glyph, at, scale):
            let path = GlyphPaths.path(glyph)
                .applying(CGAffineTransform(translationX: at.x * unit, y: at.y * unit).scaledBy(x: scale * unit, y: scale * unit))
            context.fill(path, with: .color(color))
            if item.role == .notehead, let ref = item.ref, case let mark = mark(ref), mark == .early || mark == .late {
                // A short tick in the fix colour: before the note when early, after it when late.
                let width = path.boundingRect.width / unit
                let x = mark == .early ? at.x - 1.1 : at.x + width + 0.3
                var tick = Path()
                tick.move(to: point(.init(x: x, y: at.y)))
                tick.addLine(to: point(.init(x: x + 0.8, y: at.y)))
                context.stroke(tick, with: .color(Theme.fix), style: StrokeStyle(lineWidth: 0.25 * unit, lineCap: .round))
            }

        case let .line(from, to, thickness):
            var path = Path()
            path.move(to: point(from))
            path.addLine(to: point(to))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: max(thickness * unit, 0.5), lineCap: .butt))

        case let .beam(from, to, thickness):
            var path = Path()
            path.move(to: point(from))
            path.addLine(to: point(to))
            path.addLine(to: point(.init(x: to.x, y: to.y + thickness)))
            path.addLine(to: point(.init(x: from.x, y: from.y + thickness)))
            path.closeSubpath()
            context.fill(path, with: .color(color))

        case let .tie(from, to, above):
            context.fill(tiePath(from: point(from), to: point(to), above: above, unit: unit), with: .color(color))

        case let .text(string, at, size):
            let isCurrent = item.time != nil && item.time == currentTime
            let weight: Font.Weight = item.role == .finger || isCurrent ? .semibold : .regular
            let text = Text(string).font(Theme.text(size * unit).weight(weight)).foregroundStyle(color)
            context.draw(text, at: point(at), anchor: .center)
        }
    }

    /// A crescent: thin at the ends, ~0.22 spaces thick in the middle.
    private func tiePath(from: CGPoint, to: CGPoint, above: Bool, unit: CGFloat) -> Path {
        let length = (to.x - from.x) / unit
        let height = min(max(0.15 * length + 0.25, 0.4), 0.9) * unit
        let direction: CGFloat = above ? -1 : 1
        let thickness = 0.22 * unit
        func control(_ t: CGFloat, _ h: CGFloat) -> CGPoint {
            CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t + direction * h * 4 / 3)
        }
        var path = Path()
        path.move(to: from)
        path.addCurve(to: to, control1: control(0.25, height), control2: control(0.75, height))
        path.addCurve(to: from, control1: control(0.75, height - thickness), control2: control(0.25, height - thickness))
        path.closeSubpath()
        return path
    }

    private func color(for item: Engraving.Item) -> Color {
        switch item.role {
        case .staffLine, .barline, .brace, .clef, .keySignature, .timeSignature:
            return Theme.staffLine
        case .count:
            guard let currentTime, let time = item.time else { return Theme.muted }
            return time == currentTime ? Theme.now : time < currentTime ? Theme.playedText : Theme.muted
        default:
            let isText = item.role == .finger
            guard let ref = item.ref else { return Theme.ink }
            switch mark(ref) {
            case .mistake: return Theme.fix
            case .played, .early, .late: return isText ? Theme.playedText : Theme.played
            case .upcoming:
                if let currentTime, item.time == currentTime { return Theme.now }
                return Theme.ink
            }
        }
    }
}

/// Bravura glyph outlines, one staff space per unit, y down, origin at the glyph's SMuFL origin.
enum GlyphPaths {
    private static let paths: [Glyph: Path] = {
        // Em = 4 staff spaces, so a font size of 4 makes one unit one staff space.
        let font = CTFontCreateWithName("Bravura" as CFString, 4, nil)
        var result: [Glyph: Path] = [:]
        for glyph in Glyph.allCases {
            var character = UniChar(glyph.rawValue)
            var cgGlyph = CGGlyph()
            guard CTFontGetGlyphsForCharacters(font, &character, &cgGlyph, 1),
                  let outline = CTFontCreatePathForGlyph(font, cgGlyph, nil) else { continue }
            result[glyph] = Path(outline).applying(CGAffineTransform(scaleX: 1, y: -1))
        }
        return result
    }()

    static func path(_ glyph: Glyph) -> Path { paths[glyph] ?? Path() }
}
