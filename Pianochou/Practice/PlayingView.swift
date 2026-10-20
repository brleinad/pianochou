import PianoCore
import SwiftUI

/// On the music stand, landscape. No taps while playing: a run starts on the first note and ends on silence.
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
            if session.phase == .result, let result = session.lastResult {
                BetweenRunsView(result: result, hasNext: session.hasNext,
                                slower: session.slower, next: session.next)
            } else {
                staff
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
            Orientation.lock(.landscape)
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .task { await session.start() }
        .onDisappear {
            session.stop()
            UIApplication.shared.isIdleTimerDisabled = false
            Orientation.lock(.portrait)
        }
    }

    private var staff: some View {
        let _ = session.revision // redraw marks on every heard note
        return VStack(spacing: 12) {
            HStack {
                Text(session.barsLabel)
                    .font(Theme.text(16).weight(.semibold))
                Spacer()
                listening
            }
            .foregroundStyle(Theme.ink)
            .frame(height: 32)
            .padding(.leading, 40)

            StaffView(engraving: session.engraving, currentTime: session.currentTime, mark: session.mark)
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
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    /// The small listening dot and the tempo, or why we can't listen.
    @ViewBuilder private var listening: some View {
        switch session.engine.state {
        case .running, .idle:
            HStack(spacing: 10) {
                Circle()
                    .fill(session.engine.state == .running ? Theme.now : Theme.hairline)
                    .frame(width: 8, height: 8)
                Text("\(Int(session.settings.tempo))")
                    .font(Theme.text(15).weight(.medium))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Listening, \(Int(session.settings.tempo)) beats per minute")
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
        HStack(alignment: .top, spacing: 56) {
            VStack(alignment: .leading) {
                Text("\(result.good)/\(result.total)")
                    .font(Theme.text(96).weight(.light))
                    .kerning(-3)
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 40)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 3) {
                    ForEach(Array(result.strip.enumerated()), id: \.offset) { _, good in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(good ? Theme.ink : Theme.fix)
                            .frame(height: 22)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("\(result.good) of \(result.total) notes right")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
            .padding(.top, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 56)
        .padding(.top, 48)
        .padding(.bottom, 36)
    }
}
