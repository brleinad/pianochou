import Testing
@testable import PianoCore

@Suite struct PlayedOrderTests {
    private func bar(_ n: Int, _ barlines: String = "") -> String {
        """
        <measure number="\(n)">\(n == 1 ? "<attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes>" : "")
        <note><rest/><duration>4</duration><voice>1</voice></note>\(barlines)</measure>
        """
    }

    @Test func noRepeatsIsWrittenOrder() throws {
        let score = try Fixture.inline(bar(1) + bar(2) + bar(3))
        #expect(score.playedOrder == [0, 1, 2])
    }

    @Test func backwardRepeatWithoutForwardGoesToStartAndHonorsTimes() throws {
        let score = try Fixture.inline(
            bar(1) + bar(2, #"<barline location="right"><repeat direction="backward" times="3"/></barline>"#) + bar(3)
        )
        #expect(score.playedOrder == [0, 1, 0, 1, 0, 1, 2])
    }

    @Test func secondRepeatStartsAfterTheFirst() throws {
        let back = #"<barline location="right"><repeat direction="backward"/></barline>"#
        let score = try Fixture.inline(bar(1) + bar(2, back) + bar(3) + bar(4, back))
        #expect(score.playedOrder == [0, 1, 0, 1, 2, 3, 2, 3])
    }

    @Test func multiNumberEnding() throws {
        // |: 1 | 2 [1,2 :| [3 4 |  played three times
        let score = try Fixture.inline(
            bar(1, #"<barline location="left"><repeat direction="forward"/></barline>"#)
            + bar(2, #"<barline location="left"><ending number="1, 2" type="start"/></barline><barline location="right"><ending number="1, 2" type="stop"/><repeat direction="backward" times="3"/></barline>"#)
            + bar(3, #"<barline location="left"><ending number="3" type="start"/></barline><barline location="right"><ending number="3" type="stop"/></barline>"#)
        )
        #expect(score.playedOrder == [0, 1, 0, 1, 0, 2])
    }
}

/// The bars to practise, laid out as played: a score whose measures follow the repeats.
@Suite struct PracticeRangeTests {
    /// repeat-endings: |: 1 2 [1. 3 :| [2. 4 | 5, played 1 2 3 1 2 4 5.
    func numbers(_ from: Int, _ to: Int) throws -> [String] {
        try Fixture.score("repeat-endings").playing(from: from, to: to).parts[0].measures.map(\.number)
    }

    @Test func wholeSongFollowsRepeats() throws {
        let score = try Fixture.score("repeat-endings")
        let played = score.playing(from: 0, to: 4)
        #expect(played.parts[0].measures.map(\.number) == ["1", "2", "3", "1", "2", "4", "5"])
        // Laid out one after another, with nothing left to repeat.
        #expect(played.parts[0].measures.map(\.index) == Array(0..<7))
        #expect(played.parts[0].measures.map(\.start) == (0..<7).map { Rational($0 * 4) })
        #expect(played.parts[0].measures.allSatisfy { !$0.startRepeat && $0.endRepeatTimes == nil && $0.endingNumbers == nil })
        #expect(played.playedOrder == Array(0..<7))
        // The notes are the same as written.
        #expect(played.parts[0].measures[3].events == score.parts[0].measures[0].events)
    }

    @Test func rangeInsideARepeatIsPlayedOnce() throws {
        #expect(try numbers(0, 1) == ["1", "2"])
        #expect(try numbers(0, 2) == ["1", "2", "3"])
    }

    @Test func rangeOverARepeatIncludesIt() throws {
        #expect(try numbers(0, 3) == ["1", "2", "3", "1", "2", "4"])
        #expect(try numbers(3, 4) == ["4", "5"])
    }

    @Test func rangeAcrossEndingsFollowsTheMusic() throws {
        // From bar 2 to the 2nd ending: the repeat takes the music back to bar 1 on the way.
        #expect(try numbers(1, 3) == ["2", "3", "1", "2", "4"])
    }

    @Test func withoutRepeatsItIsTheWrittenBars() throws {
        let score = try Fixture.score("c-major-scale")
        #expect(score.playing(from: 1, to: 1).parts[0].measures.map(\.number) == ["2"])
        #expect(score.playing(from: 0, to: 1).parts[0].measures.map(\.number) == ["1", "2"])
    }
}
