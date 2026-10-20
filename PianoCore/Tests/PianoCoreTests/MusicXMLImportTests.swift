import Foundation
import Testing
@testable import PianoCore

@Suite struct MusicXMLImportTests {

    @Test func cMajorScale() throws {
        let score = try Fixture.score("c-major-scale")
        #expect(score.title == "C major scale")
        #expect(score.composer == "Fixture")
        #expect(score.parts.count == 1)
        let part = score.parts[0]
        #expect(part.name == "Piano")
        #expect(part.measures.count == 2)

        let m1 = part.measures[0]
        #expect(m1.time == TimeSignature(beats: 4, beatType: 4))
        #expect(m1.key == KeySignature(fifths: 0, mode: "major"))
        #expect(m1.clefs[1] == Clef(sign: .g, line: 2))
        #expect(m1.events.map(\.onset) == [0, 1, 2, 3])
        #expect(m1.duration == 4)
        #expect(m1.isPickup == false)

        let m2 = part.measures[1]
        #expect(m2.start == 4)
        #expect(m2.time == m1.time, "time signature carries forward")
        #expect(m2.clefs[1] == Clef(sign: .g, line: 2), "clef carries forward")

        let all = part.measures.flatMap(\.events)
        #expect(all.flatMap(\.midis) == [60, 62, 64, 65, 67, 69, 71, 72])
        #expect(all.compactMap { $0.notes.first?.fingering } == [1, 2, 3, 1, 2, 3, 4, 5])
        #expect(all.allSatisfy { $0.type == .quarter && $0.duration == 1 && $0.staff == 1 && $0.voice == 1 })
    }

    @Test func waltzBarWithChordsAndBackup() throws {
        let part = try Fixture.score("waltz-3-4").parts[0]
        #expect(part.staves == 2)
        let m = part.measures[0]
        #expect(m.clefs[1] == Clef(sign: .g, line: 2))
        #expect(m.clefs[2] == Clef(sign: .f, line: 4))
        #expect(m.duration == 3)

        let rh = m.events.filter { $0.staff == 1 }
        #expect(rh.count == 1)
        #expect(rh[0].midis == [76])
        #expect(rh[0].duration == 3)
        #expect(rh[0].type == .half && rh[0].dots == 1)

        let lh = m.events.filter { $0.staff == 2 }
        #expect(lh.map(\.onset) == [0, 1, 2])
        #expect(lh.map(\.midis) == [[48], [52, 55], [52, 55]])
        #expect(lh[1].isChord && !lh[0].isChord)
        #expect(lh.allSatisfy { $0.voice == 5 })
    }

    @Test func tripletsAndGraceNote() throws {
        let part = try Fixture.score("triplets").parts[0]
        let m1 = part.measures[0]
        #expect(m1.events.map(\.onset) == [0, Rational(1, 3), Rational(2, 3), 1])
        #expect(m1.events.prefix(3).allSatisfy { $0.duration == Rational(1, 3) && $0.tuplet?.actual == 3 && $0.tuplet?.normal == 2 })
        #expect(m1.events[0].tuplet?.bracketStart == true)
        #expect(m1.events[2].tuplet?.bracketStop == true)
        #expect(m1.events[0].beams == [Beam(level: 1, value: .begin)])
        #expect(m1.events[3].tuplet == nil)
        #expect(m1.duration == 2)

        let m2 = part.measures[1]
        #expect(m2.events.count == 2)
        #expect(m2.events[0].isGrace && m2.events[0].midis == [74])
        #expect(m2.events[0].onset == 0 && m2.events[0].duration == 0)
        #expect(!m2.events[1].isGrace && m2.events[1].duration == 2)
        #expect(m2.duration == 2, "grace notes take no time")
    }

    @Test func twoVoicesInOneStaffWithForward() throws {
        let m = try Fixture.score("two-voices").parts[0].measures[0]
        #expect(m.events.map(\.onset) == [0, 1, 2, 3])
        #expect(m.events.map(\.voice) == [1, 2, 2, 2])
        #expect(m.events.map(\.midis) == [[76], [72], [71], [69]])
        #expect(m.events[1].stem == .down)
        #expect(m.duration == 4)
    }

    @Test func clefChanges() throws {
        let ms = try Fixture.score("clef-change").parts[0].measures
        #expect(ms[0].clefs[1] == Clef(sign: .f, line: 4))
        #expect(ms[1].clefs[1] == Clef(sign: .g, line: 2), "a clef before any note applies from the measure start")
        #expect(ms[1].clefChanges == [ClefChange(offset: 2, staff: 1, clef: Clef(sign: .f, line: 4))])
        #expect(ms[2].clefs[1] == Clef(sign: .f, line: 4), "a mid-measure change carries into the next measure")
        #expect(ms[2].clefChanges.isEmpty)
    }

    @Test func keyChangeDynamicsAndPedal() throws {
        let ms = try Fixture.score("key-change").parts[0].measures
        #expect(ms[0].key.fifths == 0)
        #expect(ms[1].key == KeySignature(fifths: -2, mode: "major"))

        #expect(ms[0].directions.contains(Direction(offset: 0, staff: 1, kind: .dynamic("p"))))
        #expect(ms[0].directions.contains(Direction(offset: 0, staff: 1, kind: .tempo(72))))
        #expect(ms[0].directions.contains(Direction(offset: 2, staff: nil, kind: .pedal(.stop))))

        let c4 = ms[0].events[0], e4 = ms[0].events[1], bb4 = ms[1].events[0]
        #expect(c4.dynamic == "p" && c4.pedalDown)
        #expect(e4.dynamic == "p" && !e4.pedalDown, "pedal released at the second note")
        #expect(bb4.dynamic == "f" && !bb4.pedalDown)
        #expect(bb4.notes[0].pitch == Pitch(step: .B, alter: -1, octave: 4))
        #expect(bb4.midis == [70])
        #expect(bb4.notes[0].accidental == "flat")
    }

    @Test func pickupAndTies() throws {
        let ms = try Fixture.score("pickup").parts[0].measures
        #expect(ms[0].number == "0")
        #expect(ms[0].isPickup)
        #expect(ms[0].duration == 1)
        #expect(ms[1].isPickup == false)
        #expect(ms[1].start == 1)
        #expect(ms[2].start == 4)

        #expect(ms[1].events[0].notes[0].tie == Tie(start: true, stop: false))
        #expect(ms[2].events[0].notes[0].tie == Tie(start: false, stop: true))
        #expect(ms[2].events[1].notes[0].tie == Tie())
    }

    @Test func repeatWithEndings() throws {
        let score = try Fixture.score("repeat-endings")
        let ms = score.parts[0].measures
        #expect(ms[0].startRepeat)
        #expect(ms[2].endRepeatTimes == 2)
        #expect(ms[2].endingNumbers == [1])
        #expect(ms[3].endingNumbers == [2])
        #expect(ms[4].endingNumbers == nil)
        #expect(score.playedOrder == [0, 1, 2, 0, 1, 3, 4])
    }

    @Test func pitchSpelling() {
        #expect(Pitch(step: .C, alter: 0, octave: 4).midi == 60)
        #expect(Pitch(step: .B, alter: 1, octave: 3).midi == 60)
        #expect(Pitch(step: .A, alter: 0, octave: 0).midi == 21)
        #expect(Pitch(step: .F, alter: 1, octave: 5).name == "F#5")
        #expect(Pitch(step: .E, alter: -1, octave: 4).name == "Eb4")
    }

    @Test func restsAndCompoundTime() throws {
        let score = try Fixture.inline("""
        <measure number="1">
          <attributes><divisions>2</divisions><time><beats>3+3</beats><beat-type>8</beat-type></time></attributes>
          <note><rest measure="yes"/><duration>6</duration><voice>1</voice></note>
        </measure>
        """)
        let m = score.parts[0].measures[0]
        #expect(m.time == TimeSignature(beats: 6, beatType: 8))
        #expect(m.time.measureLength == 3)
        #expect(m.events[0].isRest && m.events[0].isMeasureRest)
        #expect(m.duration == 3)
    }

    @Test func rejectsNonMusicXML() {
        #expect(throws: MusicXMLError.self) { try MusicXMLImporter.parse(data: Data("not xml".utf8)) }
        #expect(throws: MusicXMLError.notMusicXML) { try MusicXMLImporter.parse(data: Data("<html/>".utf8)) }
        #expect(throws: MusicXMLError.unsupportedFormat("score-timewise")) {
            try MusicXMLImporter.parse(data: Data("<score-timewise/>".utf8))
        }
    }
}

#if os(macOS)
import Foundation

struct MXLTests {
    /// Zips a fixture the way notation apps do, with the system `zip` tool.
    func makeArchive(container: Bool) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Fixture.url("waltz-3-4"), to: dir.appendingPathComponent("score.xml"))
        var files = ["score.xml"]
        if container {
            let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <container><rootfiles><rootfile full-path="score.xml" media-type="application/vnd.recordare.musicxml+xml"/></rootfiles></container>
            """
            try xml.write(to: dir.appendingPathComponent("META-INF/container.xml"), atomically: true, encoding: .utf8)
            files.insert("META-INF/container.xml", at: 0)
        }
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = dir
        zip.arguments = ["-q", "-9", "score.mxl"] + files
        try zip.run()
        zip.waitUntilExit()
        return dir.appendingPathComponent("score.mxl")
    }

    @Test(arguments: [true, false]) func readsCompressedMusicXML(container: Bool) throws {
        let score = try MusicXMLImporter.parse(url: makeArchive(container: container))
        #expect(score == (try Fixture.score("waltz-3-4")))
    }

    @Test func rejectsABrokenArchive() {
        #expect(throws: MusicXMLError.self) { try MusicXMLImporter.parse(data: Data([0x50, 0x4B, 0x03, 0x04, 1, 2, 3])) }
    }
}
#endif
