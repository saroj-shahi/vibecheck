import SwiftUI

// MARK: - Shared building blocks

struct Panel<Content: View>: View {
    let module: Module
    let headline: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    @Environment(SystemStats.self) private var stats
    @Environment(\.deckNamespace) private var namespace
    @Environment(\.deckShowsBack) private var showsBack

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // In the deck the header row is pinned above the scroll view (DeckRoot draws it).
            if !showsBack { PanelHeader(module: module) }
            // Hero: the one number that answers "how is it doing?", with a short summary beside it.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(headline)
                    .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    .tracking(-0.6)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .deckMatched("value.\(module.rawValue)", namespace)
                Spacer(minLength: 4)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                }
            }
            .padding(.top, -6)
            content
            Divider()
            HStack {
                Text("Up \(Fmt.uptime(stats.uptime))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/sarojshahi")!)
                } label: { Label("Support", systemImage: "heart") }
                    .help("Support VibeCheck: Buy Me a Coffee")
                Button {
                    (NSApp.delegate as? AppDelegate)?.showSettings()
                } label: { Image(systemName: "gearshape") }
                    .help("Settings")
                Button {
                    NSApp.terminate(nil)
                } label: { Image(systemName: "power") }
                    .help("Quit VibeCheck")
            }
            .buttonStyle(.borderless)
        }
        .padding([.horizontal, .bottom], 16)
        .padding(.top, showsBack ? 0 : 16)
        .frame(width: Deck.width)
        .background(
            // The tile's background grows into the whole detail view, fading as it goes.
            RoundedRectangle(cornerRadius: Deck.cornerRadius, style: .continuous)
                .fill(.clear)
                .deckMatched("bg.\(module.rawValue)", namespace)
        )
    }
}

/// Icon and title of a detail view; in the deck, a back chevron too.
struct PanelHeader: View {
    let module: Module
    var showsBack = false
    @Environment(SystemStats.self) private var stats
    @Environment(\.deckNamespace) private var namespace
    @Environment(DeckModel.self) private var deckModel: DeckModel?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if showsBack, let deckModel {
                DeckIconButton(symbol: "chevron.left", help: "Back (Esc)") { deckModel.go(.home) }
                    .padding(.leading, -6)
            }
            Image(systemName: module.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(module.accent)
                .networkStatusDot(online: stats.network.interface != nil, size: 6, enabled: module == .network)
                .deckMatched("icon.\(module.rawValue)", namespace)
            Text(module.title).font(.headline)
            Spacer()
        }
    }
}

struct StatRow: View {
    let label: LocalizedStringKey
    let value: String
    var color: Color? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let color {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}

struct SectionTitle: View {
    let text: LocalizedStringKey
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.1)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Secondary rows tucked behind a "Details" toggle; open/closed is remembered per module.
struct DetailsDisclosure<Content: View>: View {
    @AppStorage private var expanded: Bool
    private let content: Content

    init(_ module: Module, @ViewBuilder content: () -> Content) {
        _expanded = AppStorage(wrappedValue: false, "details.\(module.rawValue)")
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(Deck.animation) { expanded.toggle() }
            } label: {
                HStack {
                    Text("Details").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Hide details" : "Show details")

            if expanded {
                VStack(alignment: .leading, spacing: 12) { content }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Module panels

struct ModulePanel: View {
    let module: Module

    var body: some View {
        switch module {
        case .cpu: CPUPanel()
        case .gpu: GPUPanel()
        case .memory: MemoryPanel()
        case .network: NetworkPanel()
        case .disk: DiskPanel()
        case .sensors: SensorsPanel()
        case .battery: BatteryPanel()
        case .clock: ClockPanel()
        case .weather: WeatherPanel()
        case .agents: AgentsPanel()
        }
    }
}
