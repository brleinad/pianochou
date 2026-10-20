import SwiftUI
import PianoCore

/// Placeholder Home. The clef proves Bravura loaded; the title proves Hanken Grotesk loaded.
struct HomeView: View {
    /// Launch with `-listen-test` to open the listen screen directly (for simulator checks).
    @State private var showListenTest = ProcessInfo.processInfo.arguments.contains("-listen-test")

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Text("\u{E050}") // SMuFL gClef
                    .font(Theme.music(96))
                    .foregroundStyle(Theme.ink)
                    .accessibilityHidden(true)
                Text("Pianochou")
                    .font(Theme.text(44, relativeTo: .largeTitle).weight(.light))
                    .foregroundStyle(Theme.ink)
                Spacer()
                NavigationLink("Listen test") { ListenTestView() }
                    .font(Theme.text(18))
                    .foregroundStyle(Theme.paper)
                    .frame(maxWidth: 320, minHeight: 58)
                    .background(Capsule().fill(Theme.ink))
                Text("v\(PianoCore.version)")
                    .font(Theme.text(15))
                    .foregroundStyle(Theme.muted)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.paper)
            .navigationDestination(isPresented: $showListenTest) { ListenTestView() }
        }
    }
}

#Preview {
    HomeView()
}
