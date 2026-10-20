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
