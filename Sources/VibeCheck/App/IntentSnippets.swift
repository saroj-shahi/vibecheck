import SwiftUI

/// The card Shortcuts and Siri show under "Get Mac Vibe": the ring, the state and why. Fixed size, system
/// colors only, so it reads in Light and Dark.
struct VibeSnippetView: View {
    let vibe: Vibe
    let verdict: String

    var body: some View {
        HStack(spacing: 14) {
            VibeRing(vibe: vibe, size: 48, lineWidth: 5, monochromeWhenVibing: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(vibe.title).font(.title2.weight(.semibold)).foregroundStyle(.primary)
                Text(verdict).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding()
    }
}
