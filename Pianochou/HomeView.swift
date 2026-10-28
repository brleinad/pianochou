import PianoCore
import SwiftUI

/// The imported scores, and the way to add one.
struct HomeView: View {
    @State private var library = ScoreLibrary()
    @State private var path: [ScoreEntry] = []
    @State private var importing = false
    @State private var importError: String?
    @State private var renaming: ScoreEntry?
    @State private var newTitle = ""
    /// Launch with `-listen-test` or `-staff-gallery` to open those screens directly (for simulator checks).
    @State private var showListenTest = ProcessInfo.processInfo.arguments.contains("-listen-test")
    @State private var showStaffGallery = ProcessInfo.processInfo.arguments.contains("-staff-gallery")

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Pianochou")
                    .font(Theme.text(40, relativeTo: .largeTitle))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 24)

                if library.entries.isEmpty {
                    Spacer()
                    Text("\u{E050}") // SMuFL gClef
                        .font(Theme.music(96))
                        .foregroundStyle(Theme.hairline)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                    Spacer()
                } else {
                    List {
                        ForEach(library.entries) { entry in
                            NavigationLink(value: entry) {
                                Text(entry.title)
                                    .font(Theme.text(19))
                                    .foregroundStyle(Theme.ink)
                                    .padding(.vertical, 10)
                            }
                            .listRowBackground(Theme.paper)
                            .listRowSeparatorTint(Theme.hairline)
                            .swipeActions(edge: .leading) {
                                Button("Rename") { startRenaming(entry) }.tint(Theme.now)
                            }
                            .contextMenu {
                                Button("Rename", systemImage: "pencil") { startRenaming(entry) }
                            }
                        }
                        .onDelete { offsets in offsets.map { library.entries[$0] }.forEach(library.delete) }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }

                if let importError {
                    Text(importError)
                        .font(Theme.text(15))
                        .foregroundStyle(Theme.fix)
                }
                Button("Add a score") { importing = true }
                    .buttonStyle(PillStyle(filled: true))

                HStack(spacing: 20) {
                    NavigationLink("Listen test") { ListenTestView() }
                    NavigationLink("Staff gallery") { StaffGalleryView() }
                    Spacer()
                    Text("v\(PianoCore.version)")
                }
                .font(Theme.text(14))
                .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.paper)
            .navigationDestination(for: ScoreEntry.self) { entry in
                SetupView(library: library, entry: entry)
            }
            .navigationDestination(isPresented: $showListenTest) { ListenTestView() }
            .navigationDestination(isPresented: $showStaffGallery) { StaffGalleryView() }
            .onAppear {
                // Debug: `-openScore <file name>` jumps to a score's setup.
                if path.isEmpty, let name = UserDefaults.standard.string(forKey: "openScore"),
                   let entry = library.entries.first(where: { $0.id == name }) {
                    path = [entry]
                }
            }
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Title", text: $newTitle)
                Button("Cancel", role: .cancel) {}
                Button("Save") { if let renaming { library.rename(renaming, to: newTitle) } }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.musicXML, .compressedMusicXML, .xml]) { result in
                importError = nil
                do {
                    let entry = try library.importScore(from: result.get())
                    path.append(entry)
                } catch {
                    importError = "Couldn't read that file. Export it as MusicXML and try again."
                }
            }
        }
    }
}

extension HomeView {
    private func startRenaming(_ entry: ScoreEntry) {
        newTitle = entry.title
        renaming = entry
    }
}

/// The app's pill button: 58 pt tall, ink-filled for the main action, outlined otherwise.
struct PillStyle: ButtonStyle {
    var filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.text(18).weight(.medium))
            .foregroundStyle(filled ? Theme.paper : Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Capsule().fill(filled ? Theme.ink : .clear))
            .overlay(Capsule().stroke(filled ? .clear : Theme.hairline))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

#Preview {
    HomeView()
}
