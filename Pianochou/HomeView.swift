import SwiftUI
import PianoCore

/// Placeholder Home. The clef proves Bravura loaded; the title proves Hanken Grotesk loaded.
struct HomeView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("\u{E050}") // SMuFL gClef
                .font(Theme.music(96))
                .foregroundStyle(Theme.ink)
                .accessibilityHidden(true)
            Text("Pianochou")
                .font(Theme.text(44, relativeTo: .largeTitle).weight(.light))
                .foregroundStyle(Theme.ink)
            Text("v\(PianoCore.version)")
                .font(Theme.text(15))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
    }
}

#Preview {
    HomeView()
}
