import Testing
@testable import PianoCore

@Test func packageLinks() {
    #expect(PianoCore.version == "0.0.1")
}

@Test func tuningRangesAreSane() {
    #expect(Tuning.sessionMinutes.lowerBound > 0)
    #expect(Tuning.snippetsPerSession.lowerBound >= 1)
}
