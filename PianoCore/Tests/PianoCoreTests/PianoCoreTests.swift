import Testing
@testable import PianoCore

@Test func packageLinks() {
    #expect(PianoCore.version == "0.0.1")
}

@Test func tuningRangesAreSane() {
    #expect(Tuning.tempoRange.lowerBound > 0 && Tuning.tempoStep > 0)
}
