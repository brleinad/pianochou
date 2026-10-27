import PianoCore
import SwiftUI

/// On the music stand, either way up. No taps while playing: a run starts on the first note and ends on silence.
struct PlayingView: View {
    @State private var session: PracticeSession
    @Environment(\.dismiss) private var dismiss

    init(score: Score, settings: PracticeSettings, onSettingsChange: @escaping (PracticeSettings) -> Void) {
        let session = PracticeSession(score: score, settings: settings)
        session.onSettingsChange = onSettingsChange
        _session = State(initialValue: session)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if session.phase == .result, let result = session.lastResult {
                    BetweenRunsView(result: result, hasNext: session.hasNext,
                                    slower: session.slower, next: session.next)
                } else {
                    staff
                }
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(Theme.muted)
            .accessibilityLabel("Close")
            .padding(.leading, 4)
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .task { await session.start() }
        .onDisappear {
            session.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    /// The top edge: which bars, the listening dot, the metronome, and the tempo with − / +.
    private var header: some View {
        HStack(spacing: 4) {
            Text(session.barsLabel)
                .font(Theme.text(16).weight(.semibold))
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 8)
            listening
                .padding(.trailing, 12)
            Button(action: session.toggleMetronome) {
                Image(systemName: session.settings.metronome ? "metronome.fill" : "metronome")
                    .font(.system(size: 19))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(session.settings.metronome ? Theme.now : Theme.muted)
            .accessibilityLabel("Metronome")
            .accessibilityValue(session.settings.metronome ? "On" : "Off")
            tempoButton("minus", enabled: session.canGoSlower) { session.changeTempo(by: -1) }
                .accessibilityLabel("Slower")
            Text("\(Int(session.settings.tempo))")
                .font(Theme.text(17).weight(.medium))
                .monospacedDigit()
                .frame(minWidth: 34)
                .accessibilityLabel("\(Int(session.settings.tempo)) beats per minute")
            tempoButton("plus", enabled: session.canGoFaster) { session.changeTempo(by: 1) }
                .accessibilityLabel("Faster")
        }
        .foregroundStyle(Theme.ink)
        .frame(height: 44)
        .padding(.leading, 96)
        .padding(.trailing, 44)
        .padding(.top, 8)
    }

    private func tempoButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .foregroundStyle(enabled ? Theme.ink : Theme.hairline)
        .disabled(!enabled)
    }

    private var staff: some View {
        let _ = session.revision // redraw marks on every heard note
        return VStack(spacing: 12) {
            ScrollingStaffView(engraving: session.engraving, currentTime: session.currentTime, mark: session.mark, follows: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule().fill(Theme.ink).frame(width: geometry.size.width * session.progress)
                }
            }
            .frame(height: 2)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 56)
        .padding(.top, 4)
        .padding(.bottom, 24)
    }

    /// The small listening dot, or why we can't listen.
    @ViewBuilder private var listening: some View {
        switch session.engine.state {
        case .running, .idle:
            Circle()
                .fill(session.engine.state == .running ? Theme.now : Theme.hairline)
                .frame(width: 8, height: 8)
                .accessibilityLabel("Listening")
        case .denied:
            Text("Microphone off in Settings")
                .font(Theme.text(15))
                .foregroundStyle(Theme.fix)
        case .failed(let message):
            Text(message)
                .font(Theme.text(15))
                .foregroundStyle(Theme.fix)
        }
    }
}

/// After a run: the score, one cell per note, the worst spot, and Slower / Next. Playing again starts the next run.
struct BetweenRunsView: View {
    let result: RunResult
    let hasNext: Bool
    let slower: () -> Void
    let next: () -> Void

    var body: some View {
        // Side by side when wide, one above the other when tall.
        GeometryReader { geometry in
            let layout = geometry.size.width > geometry.size.height
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 56)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 32))
            layout {
                score
                details
            }
        }
        .padding(.horizontal, 56)
        .padding(.top, 8)
        .padding(.bottom, 36)
    }

    private var score: some View {
        VStack(alignment: .leading) {
            Text("\(result.good)/\(result.total)")
                .font(Theme.text(96).weight(.light))
                .kerning(-3)
                .foregroundStyle(Theme.ink)
                .padding(.top, 24)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Spacer()
            NoteStrip(cells: result.strip)
                .accessibilityElement()
                .accessibilityLabel("\(result.good) of \(result.total) notes right")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let worst = result.worst {
                Text("Bar \(worst.measureNumber)")
                    .font(Theme.text(15).weight(.semibold))
                    .foregroundStyle(Theme.fix)
                Text(worst.summary)
                    .font(Theme.text(28).weight(.medium))
                    .foregroundStyle(Theme.ink)
            } else {
                Text("Clean")
                    .font(Theme.text(28).weight(.medium))
                    .foregroundStyle(Theme.now)
            }
            Spacer()
            HStack(spacing: 12) {
                Button("Slower", action: slower)
                    .buttonStyle(PillStyle(filled: true))
                Button("Next", action: next)
                    .buttonStyle(PillStyle(filled: false))
                    .disabled(!hasNext)
                    .opacity(hasNext ? 1 : 0.4)
            }
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One cell per note, ink when it went well, orange when not. A few notes stretch across one row; many
/// (a long run) shrink into rows of small cells that fit a fixed block.
struct NoteStrip: View {
    let cells: [Bool]
    private static let rowHeight: CGFloat = 22
    private static let blockHeight: CGFloat = 96

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let (columns, pitch, cell) = Self.grid(count: cells.count, in: size)
                for (i, good) in cells.enumerated() {
                    let rect = CGRect(x: CGFloat(i % columns) * pitch.width, y: CGFloat(i / columns) * pitch.height,
                                      width: cell.width, height: cell.height)
                    context.fill(Path(roundedRect: rect, cornerRadius: min(3, cell.width / 3)), with: .color(good ? Theme.ink : Theme.fix))
                }
            }
            .frame(height: Self.fitsOneRow(cells.count, width: geometry.size.width) ? Self.rowHeight : Self.blockHeight)
        }
        .frame(height: Self.blockHeight, alignment: .bottom)
    }

    static func fitsOneRow(_ count: Int, width: CGFloat) -> Bool {
        (width - 3 * CGFloat(count - 1)) / CGFloat(max(1, count)) >= 8
    }

    /// Columns, the step from one cell to the next, and the cell size.
    static func grid(count: Int, in size: CGSize) -> (Int, CGSize, CGSize) {
        let count = max(1, count)
        if fitsOneRow(count, width: size.width) {
            let width = (size.width - 3 * CGFloat(count - 1)) / CGFloat(count)
            return (count, CGSize(width: width + 3, height: 0), CGSize(width: width, height: rowHeight))
        }
        // The largest square step at which every cell fits the block.
        var step = rowHeight
        while step > 2 {
            let columns = max(1, Int(size.width / step))
            if CGFloat((count + columns - 1) / columns) * step <= size.height { break }
            step -= 0.5
        }
        let cell = max(1, step * 0.75)
        return (max(1, Int(size.width / step)), CGSize(width: step, height: step), CGSize(width: cell, height: cell))
    }
}
