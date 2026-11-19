import SwiftUI

/// Every enabled module's compact label, side by side in one status item.
struct CombinedLabel: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SystemStats.self) private var stats
    /// Set only on the real menu bar item; the Settings preview always shows everything.
    @Environment(CombinedFit.self) private var fit: CombinedFit?

    var body: some View {
        let all = settings.orderedModules
        let shown = fit?.visibleCount.map { Array(all.prefix($0)) } ?? all
        HStack(spacing: settings.menuBarSpacing.between) {
            if settings.ringVisible { VibeRing(vibe: stats.vibe.vibe, awake: AwakeCup.inRing(settings)).frame(height: 22) }
            if AwakeCup.isShown(settings) { AwakeCup() }
            ForEach(shown) { MenuBarLabel(module: $0, padded: false) }
            if shown.count < all.count {
                HiddenCountChip(count: all.count - shown.count)
            }
        }
        .padding(.horizontal, settings.menuBarSpacing.padding)
    }
}

/// "+3": stats hidden to keep the item clear of the camera notch (they're all in the deck).
struct HiddenCountChip: View {
    let count: Int

    var body: some View {
        Text("+\(count)")
            .font(.system(size: 9, weight: .bold).monospacedDigit())
            .padding(.horizontal, 4)
            .frame(height: 14)
            .background(Capsule().fill(.primary.opacity(0.14)))
            .frame(height: 22)
            .help("\(count) more in the deck. Click to see everything.")
            .accessibilityLabel("\(count) more stats in the deck")
    }
}

/// Small cup shown in the menu bar while a keep-awake session runs.
struct AwakeCup: View {
    /// A session runs and the cup is wanted in the ring (not while the standalone item shows the state).
    @MainActor static func wanted(_ settings: AppSettings) -> Bool {
        settings.keepAwakeShowInMenuBar && KeepAwake.shared.isActive && !settings.keepAwakeMenuBarItem
    }

    /// The cup is drawn inside the ring's centre, so the item's width never changes.
    @MainActor static func inRing(_ settings: AppSettings) -> Bool { wanted(settings) && settings.ringVisible }

    /// A separate cup beside the other content: only when there is no ring to hold it.
    @MainActor static func isShown(_ settings: AppSettings) -> Bool { wanted(settings) && !settings.ringVisible }

    var body: some View {
        if let session = KeepAwake.shared.session, session.focus {
            // Focus: a timer with the minutes left, at a fixed width so the item never resizes.
            TimelineView(.periodic(from: .now, by: 20)) { context in
                HStack(spacing: 2) {
                    Image(systemName: "timer").font(.system(size: 10, weight: .semibold))
                    Text("\(session.minutesLeft(now: context.date) ?? 0)m")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .frame(width: 20, alignment: .leading)
                }
                .frame(height: 22)
                .help("Focus: \(session.remaining(now: context.date))")
                .accessibilityLabel("Focus session, \(session.remaining(now: context.date))")
            }
        } else {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 11, weight: .medium))
                .frame(height: 22)
                .help("Keeping your Mac awake")
                .accessibilityLabel("Keeping your Mac awake")
        }
    }
}

/// The standalone Keep Awake item: an outlined cup while off; the filled cup (or focus timer) while on.
struct KeepAwakeItemLabel: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Group {
            if KeepAwake.shared.isActive {
                AwakeCup().foregroundStyle(settings.colorfulMenuBar ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
            } else {
                Image(systemName: "cup.and.saucer")
                    .font(.system(size: 11, weight: .medium))
                    .frame(height: 22)
                    .help("Keep awake: click to start, right-click for options")
                    .accessibilityLabel("Keep awake, off")
            }
        }
        .padding(.horizontal, max(settings.menuBarSpacing.padding, 3))
    }
}
