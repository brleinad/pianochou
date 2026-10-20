import Testing
@testable import PianoCore

struct SnippetTests {
    @Test func rightHandSkipsRests() throws {
        let score = try Fixture.score("engraving-sampler")
        let snippet = Snippet(score: score, measures: 0...0, hands: .right)
        #expect(snippet.chords.map(\.time) == [1, Rational(3, 2), 2, Rational(7, 2)])
        #expect(snippet.chords.map { $0.notes.map(\.midi) } == [[74], [76], [78], [79]])
        #expect(snippet.chords.map(\.duration) == [Rational(1, 2), Rational(1, 2), Rational(3, 2), Rational(1, 2)])
        #expect(snippet.chords[2].notes[0].fingering == 3)
        #expect(snippet.chords[0].measureNumber == "1")
    }

    @Test func bothHandsMergeIntoChords() throws {
        let score = try Fixture.score("engraving-sampler")
        let snippet = Snippet(score: score, measures: 0...0, hands: .both)
        #expect(snippet.chords.count == 6)
        #expect(snippet.noteCount == 10)
        #expect(snippet.chords[4].notes.map(\.midi) == [43, 50, 78]) // G2 D3 F#5
        #expect(snippet.chords[4].notes.map(\.staff) == [2, 2, 1])
        let left = Snippet(score: score, measures: 0...0, hands: .left)
        #expect(left.chords.count == 5)
    }

    @Test func heldTiedNotesAreNotPlayedAgain() throws {
        let score = try Fixture.score("engraving-sampler")
        let snippet = Snippet(score: score, measures: 1...2, hands: .right)
        let lastBar = snippet.chords.filter { $0.measure == 2 }
        // A4 is held over from bar 2; only D5 and G4 are struck in bar 3.
        #expect(lastBar.map { $0.notes.map(\.midi) } == [[74], [67]])
        // Its tie start is still in bar 2's chord.
        #expect(snippet.chords.contains { $0.measure == 1 && $0.notes.map(\.midi) == [67, 69] })
    }
}

struct RunFollowerTests {
    /// C D E F G A B C in quarters, fingers 1 2 3 1 2 3 4 5.
    func scale(mode: RunFollower.Mode = .drill) throws -> (Snippet, RunFollower) {
        let score = try Fixture.score("c-major-scale")
        let snippet = Snippet(score: score, measures: 0...(score.parts[0].measures.count - 1), hands: .right)
        return (snippet, RunFollower(snippet: snippet, tempo: 60, mode: mode))
    }

    let scaleMidis = [60, 62, 64, 65, 67, 69, 71, 72]

    @Test func cleanRunGetsFullMarks() throws {
        let (_, follower) = try scale()
        #expect(follower.state == .waiting)
        for (i, midi) in scaleMidis.enumerated() {
            follower.hear(midi, at: 10 + Double(i))
        }
        #expect(follower.state == .finished)
        let result = try #require(follower.result)
        #expect(result.good == 8 && result.total == 8)
        #expect(result.worst == nil)
        #expect(result.notes.allSatisfy { $0.grade == .right && $0.timing == .onTime })
    }

    @Test func waitsForTheFirstNote() throws {
        let (snippet, follower) = try scale()
        follower.hear(67, at: 1) // noodling before starting
        follower.tick(now: 30)
        #expect(follower.state == .waiting)
        #expect(follower.currentTime == snippet.chords[0].time)
        follower.hear(60, at: 31)
        #expect(follower.state == .running)
        #expect(follower.currentTime == snippet.chords[1].time)
    }

    @Test func listensForTheNextTwoChords() throws {
        let (_, follower) = try scale()
        #expect(follower.expectedPitches == [60, 62])
        follower.hear(60, at: 0)
        #expect(follower.expectedPitches == [62, 64])
    }

    @Test func skippedNoteIsMissed() throws {
        let (_, follower) = try scale()
        for (i, midi) in scaleMidis.enumerated() where midi != 64 {
            follower.hear(midi, at: Double(i))
        }
        let result = try #require(follower.result)
        #expect(result.good == 7)
        #expect(result.notes[2].grade == .missed)
        #expect(result.worst?.measureNumber == "1")
        #expect(result.worst?.summary == "Right middle finger missed")
    }

    @Test func wrongNoteInsteadOfTheRightOne() throws {
        let (_, follower) = try scale()
        follower.hear(60, at: 0)
        follower.hear(62, at: 1)
        follower.hear(63, at: 2) // D# instead of E
        for (i, midi) in scaleMidis.enumerated().dropFirst(3) {
            follower.hear(midi, at: Double(i))
        }
        let result = try #require(follower.result)
        #expect(result.notes[2].grade == .wrong)
        #expect(result.good == 7)
        #expect(result.worst?.summary == "Right middle finger: wrong note")
    }

    @Test func earlyNoteIsGradedInDrills() throws {
        let times = [0, 1, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5]
        let (_, drill) = try scale()
        for (midi, time) in zip(scaleMidis, times) { drill.hear(midi, at: time) }
        let result = try #require(drill.result)
        #expect(result.notes[2].timing == .early)
        #expect(result.notes.filter { $0.timing != .onTime }.count == 1) // timing is local, so the rest are fine
        #expect(result.good == 7)
        #expect(result.worst?.summary == "Right middle finger early")

        let (_, flow) = try scale(mode: .flow)
        for (midi, time) in zip(scaleMidis, times) { flow.hear(midi, at: time) }
        #expect(flow.result?.good == 8)
    }

    @Test func silenceEndsTheRun() throws {
        let (_, follower) = try scale()
        for (i, midi) in scaleMidis.prefix(3).enumerated() { follower.hear(midi, at: Double(i)) }
        follower.tick(now: 3.5)
        #expect(follower.state == .running) // F is due at 3 s; give it a moment
        follower.tick(now: 3 + Tuning.silenceGrace + 0.1)
        #expect(follower.state == .finished)
        let result = try #require(follower.result)
        #expect(result.good == 3)
        #expect(result.notes.suffix(5).allSatisfy { $0.grade == .missed })
    }

    @Test func chordNotesMayArriveSpreadOut() throws {
        let score = try Fixture.score("engraving-sampler")
        let snippet = Snippet(score: score, measures: 0...0, hands: .both)
        let follower = RunFollower(snippet: snippet, tempo: 60, mode: .flow)
        var t = 0.0
        for chord in snippet.chords {
            for (i, note) in chord.notes.reversed().enumerated() {
                follower.hear(note.midi, at: t + Double(i) * 0.04)
            }
            t += 1
        }
        let result = try #require(follower.result)
        #expect(result.good == 10)
    }

    @Test func lateHandStillCountsForItsChord() throws {
        let score = try Fixture.score("engraving-sampler")
        let snippet = Snippet(score: score, measures: 0...0, hands: .both)
        let follower = RunFollower(snippet: snippet, tempo: 120, mode: .flow)
        // Chord 4 is G2 D3 F#5: play F#5 and G2, then chord 5's G5 sneaks in before D3 lands.
        let order: [(Int, Double)] = [(43, 0), (50, 0.25), (74, 0.5), (59, 0.5), (76, 0.75), (50, 0.75),
                                      (78, 1.0), (43, 1.0), (79, 1.05), (50, 1.08)]
        for (midi, time) in order { follower.hear(midi, at: time) }
        let result = try #require(follower.result)
        #expect(result.good == 10, "\(result.notes.map(\.grade))")
    }

    @Test func repeatedNotesCountOncePerStrike() throws {
        let score = try Fixture.inline("""
        <measure number="1"><attributes><divisions>1</divisions><time><beats>3</beats><beat-type>4</beat-type></time></attributes>
          <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
          <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
          <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
        </measure>
        """)
        let snippet = Snippet(score: score, measures: 0...0, hands: .right)
        let follower = RunFollower(snippet: snippet, tempo: 60, mode: .drill)
        follower.hear(60, at: 0)
        follower.hear(60, at: 1)
        #expect(follower.state == .running)
        follower.tick(now: 2 + Tuning.silenceGrace + 0.1)
        #expect(follower.result?.good == 2)
        #expect(follower.result?.notes.last?.grade == .missed)
    }

    @Test func echoOfTheLastNoteIsIgnored() throws {
        let (_, follower) = try scale()
        follower.hear(60, at: 0)
        follower.hear(60, at: 0.05) // a double detection of the same strike
        for (i, midi) in scaleMidis.enumerated().dropFirst() { follower.hear(midi, at: Double(i)) }
        #expect(follower.result?.good == 8)
        #expect(follower.result?.extraNotes == 0)
    }

    @Test func outcomesMarkTheStaff() throws {
        let (snippet, follower) = try scale()
        follower.hear(60, at: 0)
        follower.hear(64, at: 1) // D skipped
        let c = snippet.chords[0].notes[0].refs[0], d = snippet.chords[1].notes[0].refs[0]
        #expect(follower.outcome(for: c) == .good)
        #expect(follower.outcome(for: d) == .bad)
        #expect(follower.outcome(for: d.eventRef) == .bad)
        #expect(follower.outcome(for: snippet.chords[3].notes[0].refs[0]) == nil)
        #expect(follower.progress == 3.0 / 8)
    }
}
