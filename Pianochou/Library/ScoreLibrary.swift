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
            .compactMap { url in score(at: url).map { ScoreEntry(url: url, title: Self.title(of: $0, url: url)) } }
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
        return ScoreEntry(url: destination, title: Self.title(of: score, url: destination))
    }

    func delete(_ entry: ScoreEntry) {
        try? FileManager.default.removeItem(at: entry.url)
        cache[entry.id] = nil
        UserDefaults.standard.removeObject(forKey: Self.settingsKey(entry))
        reload()
    }

    func score(_ entry: ScoreEntry) -> Score? { score(at: entry.url) }

    private func score(at url: URL) -> Score? {
        if let cached = cache[url.lastPathComponent] { return cached }
        guard let score = try? MusicXMLImporter.parse(url: url) else { return nil }
        cache[url.lastPathComponent] = score
        return score
    }

    private static func title(of score: Score, url: URL) -> String {
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
}

/// What to practice: which bars (indices into the part's measures), which hands, how fast.
struct PracticeSettings: Codable, Hashable {
    var firstBar: Int
    var lastBar: Int
    var hands: String
    /// Quarter notes per minute.
    var tempo: Double

    var bars: ClosedRange<Int> { firstBar...lastBar }
    var handsValue: Hands { Hands(rawValue: hands) ?? .both }

    /// Bars 1–2, both hands, at 60% of the marked tempo (or 60 when unmarked). The tempo ladder comes later (M7).
    static func defaults(for score: Score) -> PracticeSettings {
        let measures = score.parts[0].measures
        // Start on the first full bar; a pickup goes with it.
        let last = min(measures.count - 1, measures.first?.isPickup == true ? 2 : 1)
        var tempo = 60.0
        for measure in measures {
            if let marked = measure.directions.lazy.compactMap({ direction -> Double? in
                if case let .tempo(bpm) = direction.kind { return bpm } else { return nil }
            }).first {
                tempo = max(40, (marked * 0.6 / 5).rounded() * 5)
                break
            }
        }
        return PracticeSettings(firstBar: 0, lastBar: last, hands: Hands.both.rawValue, tempo: tempo)
    }
}
