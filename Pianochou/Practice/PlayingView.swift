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
                    BetweenRunsView(session: session, result: result)
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
            ScrollingStaffView(engraving: session.engraving, currentTime: session.currentTime, mark: session.mark, follows: true,
                               focus: session.playbackChord, holdBars: session.holdBars, playhead: session.playhead(at:))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Listen to the bars, the progress line, and start over part-way through.
            HStack(spacing: 16) {
                iconButton(session.isPlayingBack ? "stop.fill" : "play.fill", action: session.togglePlayback)
                    .accessibilityLabel(session.isPlayingBack ? "Stop" : "Listen")
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.hairline)
                        Capsule().fill(Theme.ink).frame(width: geometry.size.width * session.progress)
                    }
                }
                .frame(height: 2)
                .accessibilityHidden(true)
                iconButton("arrow.counterclockwise", action: session.again)
                    .disabled(session.phase != .running)
                    .opacity(session.phase == .running ? 1 : 0.3)
                    .accessibilityLabel("Start over")
            }
        }
        .padding(.horizontal, 56)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(Theme.hairline))
                .contentShape(Circle())
        }
        .foregroundStyle(Theme.ink)
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

/// After a run: the score, the worst spot, the staff with every note marked, and Slower / Repeat / Next.
/// Playing the first note again also starts the next run.
struct BetweenRunsView: View {
    let session: PracticeSession
    let result: RunResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 28) {
                Text("\(result.good)/\(result.total)")
                    .font(Theme.text(56).weight(.light))
                    .kerning(-2)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityLabel("\(result.good) of \(result.total) notes right")
                VStack(alignment: .leading, spacing: 2) {
                    if let worst = result.worst {
                        Text("Bar \(worst.measureNumber)")
                            .font(Theme.text(15).weight(.semibold))
                            .foregroundStyle(Theme.fix)
                        Text(worst.summary)
                            .font(Theme.text(22).weight(.medium))
                            .foregroundStyle(Theme.ink)
                    } else {
                        Text("Clean")
                            .font(Theme.text(22).weight(.medium))
                            .foregroundStyle(Theme.now)
                    }
                }
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            }

            ScrollingStaffView(engraving: session.engraving, mark: session.mark, follows: true, focus: worstTime)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                Button("Slower", action: session.slower)
                    .buttonStyle(PillStyle(filled: false))
                    .disabled(!session.canGoSlower)
                    .opacity(session.canGoSlower ? 1 : 0.4)
                Button("Repeat", action: session.again)
                    .buttonStyle(PillStyle(filled: true))
                Button("Next", action: session.next)
                    .buttonStyle(PillStyle(filled: false))
                    .disabled(!session.hasNext)
                    .opacity(session.hasNext ? 1 : 0.4)
            }
        }
        .padding(.horizontal, 56)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    /// Where the worst spot is, to scroll it into view.
    private var worstTime: Rational? {
        result.worst.map { session.snippet.chords[$0.chord].time }
    }
}
