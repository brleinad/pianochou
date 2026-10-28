import Foundation
import Observation
import PianoCore
import UniformTypeIdentifiers

extension UTType {
    static let musicXML = UTType(importedAs: "com.recordare.musicxml.uncompressed")
    static let compressedMusicXML = UTType(importedAs: "com.recordare.musicxml")
}

/// A score the user imported. The file lives in the app's Documents/scores folder and never leaves the phone.
struct ScoreEntry: Identifiable, Hashable {
    let url: URL
    let title: String
    var id: String { url.lastPathComponent }
}

/// Imported scores, plus the practice settings last used for each.
@MainActor
@Observable
final class ScoreLibrary {
    private(set) var entries: [ScoreEntry] = []
    private var cache: [String: Score] = [:]

    private let folder: URL = URL.documentsDirectory.appending(path: "scores", directoryHint: .isDirectory)

    init() {
        reload()
    }

    func reload() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        entries = files
            .filter { ["musicxml", "xml", "mxl"].contains($0.pathExtension.lowercased()) }
            .compactMap { url in score(at: url).map { ScoreEntry(url: url, title: title(of: $0, url: url)) } }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Copies a picked file into the library after checking it parses. Returns the new entry.
    func importScore(from source: URL) throws -> ScoreEntry {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: source)
        let score = try MusicXMLImporter.parse(data: data)
        guard let part = score.parts.first, !part.measures.isEmpty else { throw MusicXMLError.malformed("the score has no bars") }

        var destination = folder.appending(path: source.lastPathComponent)
        var n = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = folder.appending(path: "\(source.deletingPathExtension().lastPathComponent) \(n).\(source.pathExtension)")
            n += 1
        }
        try data.write(to: destination)
        cache[destination.lastPathComponent] = score
        reload()
        return ScoreEntry(url: destination, title: title(of: score, url: destination))
    }

    func delete(_ entry: ScoreEntry) {
        try? FileManager.default.removeItem(at: entry.url)
        cache[entry.id] = nil
        UserDefaults.standard.removeObject(forKey: Self.settingsKey(entry))
        UserDefaults.standard.removeObject(forKey: Self.titleKey(entry.id))
        reload()
    }

    /// Gives a score the user's own name; an empty name goes back to the one in the file.
    func rename(_ entry: ScoreEntry, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.titleKey(entry.id))
        } else {
            UserDefaults.standard.set(title, forKey: Self.titleKey(entry.id))
        }
        reload()
    }

    func score(_ entry: ScoreEntry) -> Score? { score(at: entry.url) }

    private func score(at url: URL) -> Score? {
        if let cached = cache[url.lastPathComponent] { return cached }
        guard let score = try? MusicXMLImporter.parse(url: url) else { return nil }
        cache[url.lastPathComponent] = score
        return score
    }

    /// The user's name for it, else the score's title, else the file name.
    private func title(of score: Score, url: URL) -> String {
        if let custom = UserDefaults.standard.string(forKey: Self.titleKey(url.lastPathComponent)) { return custom }
        if let title = score.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { return title }
        return url.deletingPathExtension().lastPathComponent
    }

    // MARK: Settings

    func settings(for entry: ScoreEntry) -> PracticeSettings? {
        guard let data = UserDefaults.standard.data(forKey: Self.settingsKey(entry)) else { return nil }
        return try? JSONDecoder().decode(PracticeSettings.self, from: data)
    }

    func save(_ settings: PracticeSettings, for entry: ScoreEntry) {
        UserDefaults.standard.set(try? JSONEncoder().encode(settings), forKey: Self.settingsKey(entry))
    }

    private static func settingsKey(_ entry: ScoreEntry) -> String { "settings.\(entry.id)" }
    private static func titleKey(_ id: String) -> String { "title.\(id)" }
}

/// What to practice: which bars (indices into the part's measures), which hands, how fast.
struct PracticeSettings: Codable, Hashable {
    var firstBar: Int
    var lastBar: Int
    var hands: String
    /// Quarter notes per minute.
    var tempo: Double
    /// Click on every beat while practicing.
    var metronome = false

    var bars: ClosedRange<Int> { firstBar...lastBar }
    var handsValue: Hands { Hands(rawValue: hands) ?? .both }

    /// Bars 1–2, both hands, at 60% of the marked tempo (or 60 when unmarked). The tempo ladder comes later (M7).
    static func defaults(for score: Score) -> PracticeSettings {
        let measures = score.parts[0].measures
        // Start on the first full bar; a pickup goes with it.
        let last = min(measures.count - 1, measures.first?.isPickup == true ? 2 : 1)
        var tempo = 60.0
        if let marked = songTempo(score, at: 0) { tempo = max(40, (marked * 0.6 / 5).rounded() * 5) }
        return PracticeSettings(firstBar: 0, lastBar: last, hands: Hands.both.rawValue, tempo: tempo)
    }

    /// The tempo the score marks for bar `index`: the last marking at or before it, else the song's first.
    /// Nil when the score marks none.
    static func songTempo(_ score: Score, at index: Int) -> Double? {
        func marking(_ measure: Measure) -> Double? {
            measure.directions.lazy.compactMap { direction -> Double? in
                if case let .tempo(bpm) = direction.kind { return bpm } else { return nil }
            }.first
        }
        let measures = score.parts[0].measures
        let marked = measures[...index].reversed().lazy.compactMap(marking).first ?? measures.lazy.compactMap(marking).first
        return marked.map { min(max($0, Tuning.tempoRange.lowerBound), Tuning.tempoRange.upperBound) }
    }
}

extension PracticeSettings {
    /// Settings saved before the metronome existed have no `metronome`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        firstBar = try c.decode(Int.self, forKey: .firstBar)
        lastBar = try c.decode(Int.self, forKey: .lastBar)
        hands = try c.decode(String.self, forKey: .hands)
        tempo = try c.decode(Double.self, forKey: .tempo)
        metronome = try c.decodeIfPresent(Bool.self, forKey: .metronome) ?? false
    }
}
