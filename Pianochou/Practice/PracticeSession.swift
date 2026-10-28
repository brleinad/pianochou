import Foundation
import Observation
import PianoCore

/// One sitting at the piano with some bars (up to the whole song): listens, follows each run, keeps the last
/// result. A run starts on its first note and ends on silence; between runs, playing the first note again
/// starts the next. The bars are played as written, repeats included (`Score.playing(from:to:)`).
@MainActor
@Observable
final class PracticeSession {
    enum Phase: Equatable {
        /// Waiting for the first note (hint: it's highlighted).
        case ready
        case running
        /// Showing the last result until the next run starts.
        case result
    }

    let score: Score
    /// The chosen bars as played, one after another.
    private(set) var played: Score
    let engine = ListenEngine()
    private(set) var settings: PracticeSettings
    /// All the bars, laid out once; the view scrolls through them.
    private(set) var engraving: Engraving
    /// How long to hold each note to play, drawn under the staff.
    private(set) var holdBars: [HoldBar] = []
    private(set) var snippet: Snippet
    private(set) var follower: RunFollower
    private(set) var phase: Phase = .ready
    private(set) var lastResult: RunResult?
    /// Bumped on every heard note, so views redraw marks.
    private(set) var revision = 0

    /// The finished run, still taking late notes of its last chord.
    private var finished: RunFollower?
    private var finishedAt = 0.0
    private var ticker: Task<Void, Never>?
    var onSettingsChange: ((PracticeSettings) -> Void)?

    init(score: Score, settings: PracticeSettings) {
        self.score = score
        self.settings = settings
        let played = score.playing(from: settings.firstBar, to: settings.lastBar)
        self.played = played
        let snippet = Snippet(score: played, measures: 0...(played.parts[0].measures.count - 1), hands: settings.handsValue)
        self.snippet = snippet
        let engraving = Engraver.engrave(played, measures: 0..<played.parts[0].measures.count)
        self.engraving = engraving
        follower = RunFollower(snippet: snippet, tempo: settings.tempo, mode: .drill)
        holdBars = HoldBars.make(engraving: engraving, snippet: snippet)
    }

    var measureCount: Int { score.parts[0].measures.count }
    var hasNext: Bool { settings.lastBar + 1 < measureCount }

    /// "Bars 1–2", using the printed numbers.
    var barsLabel: String {
        let measures = score.parts[0].measures
        let first = measures[settings.firstBar].number, last = measures[settings.lastBar].number
        return first == last ? "Bar \(first)" : "Bars \(first)–\(last)"
    }

    // MARK: Lifecycle

    func start() async {
        if UserDefaults.standard.bool(forKey: "simulateRun") {
            await simulateRun()
            return
        }
        engine.onDetection = { [weak self] detection in self?.heard(detection) }
        await engine.start()
        engine.resetOnsets()
        // Debug: `-metronome YES -recordSession 10` records 10 s of the microphone with the clicks on, and
        // where the clicks were predicted to arrive, to Documents/recordings (for `Tuning.clickArrivalOffset`).
        if UserDefaults.standard.bool(forKey: "metronome") { settings.metronome = true }
        let record = UserDefaults.standard.double(forKey: "recordSession")
        if record > 0 {
            engine.startRecording()
            Task { [engine] in
                try? await Task.sleep(for: .seconds(record))
                engine.stopRecording()
            }
        }
        updateClicks()
        updateExpected()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.tick()
            }
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        engine.onDetection = nil
        engine.stop()
        clicking = nil
    }

    // MARK: Following

    private func heard(_ detection: ListenUpdate.Detection) {
        let midi: Int = switch detection.kind {
        case let .expected(m): m
        case let .unexpected(guess): guess
        }
        let time = detection.onsetTime

        // A late hand for the run that just ended.
        if let finished, time - finishedAt <= Tuning.chordSpread {
            finished.hear(midi, at: time)
            lastResult = finished.result
            revision += 1
            return
        }

        let wasWaiting = follower.state == .waiting
        follower.hear(midi, at: time)
        if wasWaiting && follower.state != .waiting {
            phase = .running
            finished = nil
        }
        revision += 1
        if follower.state == .finished { endRun(at: time) }
        updateExpected()
    }

    private func tick() {
        guard follower.state == .running else { return }
        follower.tick(now: engine.latest.streamTime)
        if follower.state == .finished { endRun(at: engine.latest.streamTime) }
    }

    private func endRun(at time: Double) {
        lastResult = follower.result
        finished = follower
        finishedAt = time
        phase = .result
        follower = RunFollower(snippet: snippet, tempo: settings.tempo, mode: .drill)
        updateExpected()
    }

    private func updateExpected() {
        let pitches = follower.expectedPitches
        if engine.expected != pitches { engine.expected = pitches }
    }

    // MARK: Between runs

    /// A tempo step faster (+1) or slower (-1); starts over from the first note.
    func changeTempo(by steps: Int) {
        var next = settings
        next.tempo = Metronome.step(settings.tempo, by: steps)
        guard next.tempo != settings.tempo else { return }
        apply(next)
    }

    var canGoSlower: Bool { settings.tempo > Tuning.tempoRange.lowerBound }
    var canGoFaster: Bool { settings.tempo < Tuning.tempoRange.upperBound }

    /// Turns the click on or off without interrupting the run.
    func toggleMetronome() {
        settings.metronome.toggle()
        updateClicks()
        onSettingsChange?(settings)
    }

    /// What the metronome is clicking, or nil when it's off.
    private var clicking: Clicks?
    private struct Clicks: Equatable {
        var tempo: Double
        var time: TimeSignature
    }

    /// Clicks on every beat of the snippet's time signature while the metronome is on. Restarted only
    /// when the tempo changes, so the beat doesn't jump.
    private func updateClicks() {
        let time = played.parts[0].measures[0].time
        let wanted = settings.metronome && engine.state == .running ? Clicks(tempo: settings.tempo, time: time) : nil
        guard wanted != clicking else { return }
        clicking = wanted
        engine.setClicks(wanted.map { ($0.time, $0.tempo) })
    }

    /// The same number of bars, straight after these.
    func next() {
        guard hasNext else { return }
        var next = settings
        let length = settings.lastBar - settings.firstBar
        next.firstBar = settings.lastBar + 1
        next.lastBar = min(measureCount - 1, next.firstBar + length)
        apply(next)
    }

    /// The same bars again, from the first note.
    func again() {
        apply(settings)
    }

    private func apply(_ new: PracticeSettings) {
        settings = new
        played = score.playing(from: new.firstBar, to: new.lastBar)
        snippet = Snippet(score: played, measures: 0...(played.parts[0].measures.count - 1), hands: new.handsValue)
        engraving = Engraver.engrave(played, measures: 0..<played.parts[0].measures.count)
        holdBars = HoldBars.make(engraving: engraving, snippet: snippet)
        follower = RunFollower(snippet: snippet, tempo: new.tempo, mode: .drill)
        finished = nil
        phase = .ready
        engine.resetOnsets()
        updateExpected()
        updateClicks()
        onSettingsChange?(new)
    }

    // MARK: Simulator checks

    /// Debug (`-simulateRun YES`): plays the snippet without a piano, skipping one note and rushing
    /// another, stopping halfway for a screenshot of the playing screen, then showing the result.
    private func simulateRun() async {
        try? await Task.sleep(for: .seconds(1))   // let the screen turn to landscape first
        let spq = 60 / settings.tempo
        var events: [(midi: Int, time: Double)] = []
        for (i, chord) in snippet.chords.enumerated() {
            let time = 1 + (chord.time - snippet.start).doubleValue * spq - (i == 3 ? 0.4 * spq : 0)
            for (n, note) in chord.notes.enumerated() where !(i == 1 && n == 0) {
                events.append((note.midi, time + Double(n) * 0.02))
            }
        }
        let pause = UserDefaults.standard.double(forKey: "simulatePause")
        for (index, event) in events.enumerated() {
            heard(.init(kind: .expected(midi: event.midi), onsetTime: event.time, algorithmLatency: 0, totalLatency: 0))
            if pause > 0 && index == events.count / 2 { try? await Task.sleep(for: .seconds(pause)) }
        }
        if follower.state == .running {
            follower.tick(now: (events.last?.time ?? 0) + 10)
            endRun(at: (events.last?.time ?? 0) + 10)
        }
    }

    // MARK: Drawing

    /// How a note on the staff should look: the other hand is faded, done notes graded.
    func mark(_ ref: Engraving.NoteRef) -> NoteMark {
        let event = played.parts[0].measures[ref.measure].events[ref.event]
        guard settings.handsValue.includes(staff: event.staff) else { return .played }
        let source = phase == .result ? finished : follower
        switch source?.outcome(for: ref) {
        case .good: return .played
        case .early: return .early
        case .late: return .late
        case .bad: return .mistake
        case nil: return .upcoming
        }
    }

    /// Where the line showing the beat has got to at `date`; nil on the result.
    func playhead(at date: Date) -> Rational? {
        guard phase != .result else { return nil }
        // The detection clock, moved on by the time since its last update.
        return follower.playhead(at: engine.latest.streamTime + date.timeIntervalSince(engine.latestArrived))
    }

    /// The highlighted beat: the next chord while playing, the first chord when ready, none on the result.
    var currentTime: Rational? {
        phase == .result ? nil : follower.currentTime
    }

    var progress: Double {
        phase == .result ? 1 : follower.progress
    }
}
