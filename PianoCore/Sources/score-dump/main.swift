// Prints a summary of a MusicXML file, to check the importer against real scores
// without copying them into the repo:  swift run score-dump ~/Music/song.musicxml [--events]
import Foundation
import PianoCore

let arguments = CommandLine.arguments.dropFirst()
guard let path = arguments.first(where: { !$0.hasPrefix("--") }) else {
    print("usage: score-dump <file.musicxml> [--events]")
    exit(2)
}
let showEvents = arguments.contains("--events")

do {
    let score = try MusicXMLImporter.parse(url: URL(fileURLWithPath: path))
    print("Title: \(score.title ?? "-")   Composer: \(score.composer ?? "-")")
    for part in score.parts {
        let notes = part.measures.flatMap(\.events).reduce(0) { $0 + $1.notes.count }
        print("Part \(part.id) \(part.name ?? ""): \(part.measures.count) measures, \(part.staves) staves, \(notes) notes")
        for m in part.measures {
            let clefs = m.clefs.keys.sorted().map { "\(m.clefs[$0]!.sign.rawValue)\(m.clefs[$0]!.line)" }.joined(separator: "/")
            var flags: [String] = []
            if m.isPickup { flags.append("pickup") }
            if m.startRepeat { flags.append("|:") }
            if let t = m.endRepeatTimes { flags.append(":|x\(t)") }
            if let e = m.endingNumbers { flags.append("ending \(e.map(String.init).joined(separator: ","))") }
            if m.duration != m.time.measureLength { flags.append("len \(m.duration)") }
            print("  m\(m.number)\t\(m.time.beats)/\(m.time.beatType) key \(m.key.fifths) \(clefs)\t\(m.events.count) events \(flags.joined(separator: " "))")
            guard showEvents else { continue }
            for e in m.events {
                let what = e.isRest ? "rest" : e.notes.map { n in n.pitch.name + (n.fingering.map { "(\($0))" } ?? "") }.joined(separator: " ")
                print("      @\(e.onset)\t+\(e.duration)\ts\(e.staff) v\(e.voice)\t\(what)\(e.isGrace ? " grace" : "")\(e.tuplet.map { " \($0.actual):\($0.normal)" } ?? "")")
            }
        }
    }
    print("Played order: \(score.playedOrder.map { score.parts[0].measures[$0].number }.joined(separator: " "))")
} catch {
    print("Import failed: \(error)")
    exit(1)
}
