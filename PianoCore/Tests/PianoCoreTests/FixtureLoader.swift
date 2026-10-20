import Foundation
@testable import PianoCore

enum Fixture {
    static func url(_ name: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: "musicxml", subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: name])
        }
        return url
    }

    static func score(_ name: String) throws -> Score {
        try MusicXMLImporter.parse(url: url(name))
    }

    /// Wraps measure XML in a minimal one-part score, for small inline tests.
    static func inline(_ measures: String) throws -> Score {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.0">
          <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
          <part id="P1">\(measures)</part>
        </score-partwise>
        """
        return try MusicXMLImporter.parse(data: Data(xml.utf8))
    }
}

extension Event {
    var midis: [Int] { notes.map(\.pitch.midi) }
}
