import AppKit
import SwiftUI

// MARK: - Alerts

struct AlertSettings: View {
    let onTestNotification: () -> Void
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                if settings.alertRules.isEmpty {
                    Text("No alerts yet.").foregroundStyle(.secondary)
                }
                ForEach($settings.alertRules) { $rule in
                    AlertRuleRow(rule: $rule) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            settings.alertRules.removeAll { $0.id == rule.id }
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            } header: {
                HStack {
                    Text("Threshold alerts")
                        .settingsAnchor("alerts.rules")
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            settings.alertRules.insert(AlertRule.starter(for: .cpu), at: 0)
                        }
                    } label: { Label("Add Alert", systemImage: "plus") }
                        .buttonStyle(.borderless)
                }
            } footer: {
                Text("Click a capsule to change it, or drag a number sideways (hold ⌥ for fine steps, or press ↑/↓ when focused). Each alert fires once, then waits for recovery and at least 5 minutes.")
                    .settingsFooter()
            }

            Section {
                Toggle("An app's memory keeps climbing", isOn: $settings.smartAlertMemoryLeak)
                    .settingsAnchor("alerts.smart")
                Toggle("macOS is throttling your Mac", isOn: $settings.smartAlertThrottling)
                Toggle("The charger can't keep up", isOn: $settings.smartAlertSlowCharger)
                Toggle(isOn: $settings.keepAwake.notifyAgentFinished) {
                    Text("An AI agent finishes a run of 10 minutes or more")
                    Text("Sends one notification when Claude Code, Codex, Copilot CLI, or OpenCode wraps up a long session.")
                }
            } header: {
                Text("Smart & activity alerts")
            } footer: {
                Text("Built-in checks wait for the problem to persist (an app grows 1 GB+ over 45 minutes; throttling or a slow charger for 5 minutes) and notify at most once every 2 hours.")
                    .settingsFooter()
            }

            Section("Meeting reminders") {
                LabeledContent {
                    Button("Configure…") {
                        if let entry = SettingsSearchIndex.entries.first(where: { $0.id == "clock.meetingAlerts" }) {
                            SettingsRouter.shared.reveal(entry)
                        } else {
                            SettingsRouter.shared.clockTab = .calendar
                            SettingsRouter.shared.open(.module(.clock))
                        }
                    }
                } label: {
                    Text("Upcoming meeting alerts")
                    Text(settings.clock.meetingAlertStyle == .off
                         ? String(localized: "Currently off. Fullscreen or banner reminders with one-click Join.")
                         : String(localized: "\(settings.clock.meetingAlertStyle.title) reminders active in Date & Time."))
                }
            }

            AdvancedSection(id: "alerts.advanced", title: "Defaults & testing") {
                HStack {
                    Button("Restore Default Alerts") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { settings.alertRules = AlertRule.defaults }
                    }
                    Spacer()
                    Button("Send Test Notification", action: onTestNotification)
                }
                .settingsAnchor("alerts.advanced")
            }
        }
        .settingsForm()
    }
}

/// "Alert when [CPU usage] is [above] [90%] for [1 min]."
struct AlertRuleRow: View {
    @Binding var rule: AlertRule
    /// The metrics its first token can switch to (a module's page offers only that module's).
    var metrics: [AlertMetric] = AlertMetric.allCases
    let onDelete: () -> Void
    @Environment(SystemStats.self) private var stats
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showPreview = false
    @State private var isScrubbing = false

    private var liveValue: Double? { AlertEngine.value(for: rule.metric, in: stats) }

    private var liveReadingText: String? {
        guard let current = liveValue else { return nil }
        let formatted = rule.metric == .agentTokens
            ? String(format: "%.1f%@", current, rule.metric.unit)
            : "\(Int(current.rounded()))\(rule.metric.unit)"
        return String(localized: "Now \(formatted)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Toggle("Enabled", isOn: $rule.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                FlowLayout(spacing: 5, lineSpacing: 5) {
                    Text("Alert when")
                        .foregroundStyle(.secondary)
                    TokenMenu(title: rule.metric.shortTitle) {
                        ForEach(metrics) { metric in
                            Button(metric.title) { select(metric) }
                        }
                    }
                    Text("is")
                        .foregroundStyle(.secondary)
                    TokenMenu(title: rule.comparison.label) {
                        ForEach(AlertComparison.allCases) { comparison in
                            Button(comparison.label) { rule.comparison = comparison }
                        }
                    }
                    NumberToken(value: $rule.threshold,
                                unit: rule.metric.unit,
                                range: rule.metric.range,
                                isInteracting: $isScrubbing)
                    if rule.duration > 0 {
                        Text("for").foregroundStyle(.secondary)
                    }
                    TokenMenu(title: AlertRule.durationLabel(rule.duration)) {
                        ForEach(AlertRule.durations, id: \.0) { seconds, label in
                            Button(label) { rule.duration = seconds }
                        }
                    }
                }
                .opacity(rule.enabled ? 1 : 0.45)
                .disabled(!rule.enabled)

                Spacer(minLength: 4)

                if let live = liveReadingText {
                    Text(live)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(isScrubbing ? Color.accentColor : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(isScrubbing ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.10)))
                }

                Button {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.82)) {
                        showPreview.toggle()
                    }
                } label: {
                    Image(systemName: showPreview ? "eye.fill" : "eye")
                        .foregroundStyle(showPreview ? Color.accentColor : .secondary)
                }
                .buttonStyle(.borderless)
                .help(showPreview ? "Hide notification preview" : "Preview the notification")
                .accessibilityLabel(showPreview ? "Hide notification preview" : "Preview notification")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Delete alert")
                .accessibilityLabel("Delete alert")
            }

            if rule.enabled, let current = liveValue {
                LiveThresholdMeter(current: current,
                                   threshold: rule.threshold,
                                   range: rule.metric.range,
                                   comparison: rule.comparison,
                                   active: isScrubbing)
                    .padding(.leading, 34)
                    .padding(.trailing, 4)
            }

            if showPreview {
                NotificationPreview(title: String(localized: "VibeCheck · \(rule.metric.title)"),
                                    message: rule.describe(current: exampleValue)) {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.2)) {
                        showPreview = false
                    }
                }
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.vertical, 3)
        .onKeyPress(.escape) {
            guard showPreview else { return .ignored }
            withAnimation(.easeOut(duration: 0.18)) { showPreview = false }
            return .handled
        }
    }

    private var exampleValue: Double {
        let r = rule.metric.range
        return min(max(rule.threshold + (rule.comparison == .above ? 6 : -6), r.lowerBound), r.upperBound)
    }

    private func select(_ metric: AlertMetric) {
        rule.metric = metric
        rule.comparison = metric.defaultComparison
        rule.threshold = min(max(rule.threshold, metric.range.lowerBound), metric.range.upperBound)
    }
}

/// Shared high-contrast capsule chrome for both menu and numeric tokens.
private struct AlertTokenCapsule: ViewModifier {
    var active: Bool = false
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let fillOpacity: Double = active ? 0.26 : (contrast == .increased ? 0.22 : 0.15)
        let strokeOpacity: Double = contrast == .increased ? 0.85 : (active ? 0.65 : 0.30)
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor.opacity(fillOpacity)))
            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(strokeOpacity),
                                            lineWidth: contrast == .increased ? 1 : 0.5))
    }
}

/// A highlighted word that opens a native menu.
private struct TokenMenu<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        Menu { content } label: {
            Text(title)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .modifier(AlertTokenCapsule())
    }
}

/// Converts a horizontal drag into a value change: 1 unit per 4 pt, or per 12 pt with ⌥ held.
enum AlertScrub {
    static func value(start: Double, dx: CGFloat, fine: Bool, range: ClosedRange<Double>) -> Double {
        let perPoint = fine ? 1.0 / 12 : 1.0 / 4
        return min(max((start + Double(dx) * perPoint).rounded(), range.lowerBound), range.upperBound)
    }
}

/// A number you can drag sideways (with a trackpad tick every 5), click to type, or step with keyboard arrows.
private struct NumberToken: View {
    @Binding var value: Double
    let unit: String
    let range: ClosedRange<Double>
    @Binding var isInteracting: Bool
    @State private var editing = false
    @State private var dragStart: Double?
    @State private var lastTick: Int?
    @State private var hovering = false
    @FocusState private var fieldFocused: Bool
    @FocusState private var tokenFocused: Bool

    var body: some View {
        Group {
            if editing {
                TextField("Value", value: Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) }),
                          format: .number)
                    .labelsHidden()
                    .frame(width: 52)
                    .focused($fieldFocused)
                    .onSubmit { editing = false }
                    .onChange(of: fieldFocused) { _, isFocused in if !isFocused { editing = false } }
                    .onAppear { fieldFocused = true }
            } else {
                HStack(spacing: 3) {
                    if hovering || dragStart != nil {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    Text("\(Int(value))\(unit)")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText(value: value))
                    if hovering || dragStart != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .modifier(AlertTokenCapsule(active: dragStart != nil || tokenFocused))
                    .focusable()
                    .focused($tokenFocused)
                    .onHover { inside in
                        if inside, !hovering { NSCursor.resizeLeftRight.push() }
                        else if !inside, hovering { NSCursor.pop() }
                        hovering = inside
                    }
                    .onDisappear {
                        if hovering { NSCursor.pop(); hovering = false }
                    }
                    .gesture(DragGesture(minimumDistance: 2)
                        .onChanged { drag in
                            if dragStart == nil { dragStart = value; isInteracting = true }
                            let fine = NSEvent.modifierFlags.contains(.option)
                            let next = AlertScrub.value(start: dragStart ?? value, dx: drag.translation.width, fine: fine, range: range)
                            if next != value {
                                withAnimation(.snappy(duration: 0.12)) { value = next }
                                let tick = Int(next) / 5
                                if tick != lastTick {
                                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                                    lastTick = tick
                                }
                            }
                        }
                        .onEnded { _ in
                            dragStart = nil
                            lastTick = nil
                            isInteracting = editing || tokenFocused
                        })
                    .onTapGesture {
                        if hovering { NSCursor.pop(); hovering = false }
                        editing = true
                    }
                    .onKeyPress(.return) { editing = true; return .handled }
                    .onKeyPress(.space) { editing = true; return .handled }
                    .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                        let step = press.modifiers.contains(.option) ? 1.0 : 5.0
                        let delta = press.key == .upArrow ? step : -step
                        withAnimation(.snappy(duration: 0.12)) {
                            value = min(max((value + delta).rounded(), range.lowerBound), range.upperBound)
                        }
                        return .handled
                    }
                    .help("Drag sideways to adjust (⌥ for fine steps), click to type, or press ↑/↓")
            }
        }
        .onChange(of: editing) { _, on in isInteracting = on || dragStart != nil || tokenFocused }
        .onChange(of: tokenFocused) { _, on in isInteracting = on || dragStart != nil || editing }
        .accessibilityElement()
        .accessibilityLabel("Threshold")
        .accessibilityValue("\(Int(value)) \(unit)")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 1.0 : -1.0
            value = min(max(value + step, range.lowerBound), range.upperBound)
        }
    }
}

/// Hairline live sensor bar showing current reading vs. the rule's threshold marker.
private struct LiveThresholdMeter: View {
    let current: Double
    let threshold: Double
    let range: ClosedRange<Double>
    let comparison: AlertComparison
    let active: Bool

    private func fraction(_ value: Double) -> CGFloat {
        let span = max(range.upperBound - range.lowerBound, 1)
        return CGFloat(min(max((value - range.lowerBound) / span, 0), 1))
    }

    private var triggered: Bool {
        comparison == .above ? current >= threshold : current <= threshold
    }

    var body: some View {
        let currentFrac = fraction(current)
        let limitFrac = fraction(threshold)
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary.opacity(0.6)).frame(height: active ? 4 : 3)
                Capsule()
                    .fill(triggered ? Color.orange : Color.mint.opacity(0.85))
                    .frame(width: max(3, w * currentFrac), height: active ? 4 : 3)
                RoundedRectangle(cornerRadius: 1)
                    .fill(active ? Color.accentColor : Color.primary.opacity(0.55))
                    .frame(width: active ? 3 : 2, height: active ? 10 : 8)
                    .offset(x: min(max(w * limitFrac - 1, 0), max(w - 3, 0)))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 10)
        .animation(.easeOut(duration: 0.14), value: active)
        .accessibilityHidden(true)
    }
}

/// A miniature of the banner the alert will post; stays visible until explicitly dismissed.
private struct NotificationPreview: View {
    let title: String
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .help("Dismiss preview")
            .accessibilityLabel("Dismiss notification preview")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Notification preview: \(title). \(message)")
    }
}

/// Wraps its children onto new lines when they don't fit, like words in a sentence.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += row.indices.isEmpty ? size.width : size.width + spacing
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
