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
                    Text("Alerts")
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            settings.alertRules.insert(AlertRule.starter(for: .cpu), at: 0)
                        }
                    } label: { Label("Add Alert", systemImage: "plus") }
                        .buttonStyle(.borderless)
                }
            } footer: {
                Text("Click a highlighted word to change it; drag a number sideways to adjust it (hold ⌥ for fine steps). Each alert fires once, then waits until things recover and at least 5 minutes pass.")
                    .settingsFooter()
            }
            Section {
                Toggle("An app's memory keeps climbing", isOn: $settings.smartAlertMemoryLeak)
                Toggle("macOS is throttling your Mac", isOn: $settings.smartAlertThrottling)
                Toggle("The charger can't keep up", isOn: $settings.smartAlertSlowCharger)
            } header: {
                Text("Smart alerts")
            } footer: {
                Text("Built-in checks, off by default. Each one waits for the problem to last (an app grows 1 GB or more over 45 minutes and keeps climbing; throttling or a slow charger for 5 minutes) and sends at most one alert per app or problem every 2 hours.")
                    .settingsFooter()
            }
            AdvancedSection {
                HStack {
                    Button("Restore Default Alerts") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { settings.alertRules = AlertRule.defaults }
                    }
                    Spacer()
                    Button("Send Test Notification", action: onTestNotification)
                }
            }
        }
        .settingsForm()
    }
}

/// "Tell me when [CPU usage] is [above] [90%] for [1 min]."
struct AlertRuleRow: View {
    @Binding var rule: AlertRule
    /// The metrics its first word can switch to (a module's page offers only that module's).
    var metrics: [AlertMetric] = AlertMetric.allCases
    let onDelete: () -> Void
    @State private var showPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Toggle("Enabled", isOn: $rule.enabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    .padding(.top, 2)
                FlowLayout(spacing: 5, lineSpacing: 6) {
                    Text("Tell me when")
                    TokenMenu(title: rule.metric.title) {
                        ForEach(metrics) { metric in
                            Button(metric.title) { select(metric) }
                        }
                    }
                    Text("is")
                    TokenMenu(title: rule.comparison.label) {
                        ForEach(AlertComparison.allCases) { comparison in
                            Button(comparison.label) { rule.comparison = comparison }
                        }
                    }
                    NumberToken(value: $rule.threshold, unit: rule.metric.unit, range: rule.metric.range)
                    if rule.duration > 0 { Text("for") } // "below 15% instantly", not "for instantly"
                    TokenMenu(title: AlertRule.durationLabel(rule.duration)) {
                        ForEach(AlertRule.durations, id: \.0) { seconds, label in
                            Button(label) { rule.duration = seconds }
                        }
                    }
                }
                .opacity(rule.enabled ? 1 : 0.45)
                .disabled(!rule.enabled)
                Spacer(minLength: 0)
                Button { preview() } label: { Image(systemName: "eye") }
                    .buttonStyle(.borderless)
                    .help("Preview the notification")
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Delete alert")
            }
            if showPreview {
                NotificationPreview(title: String(localized: "VibeCheck · \(rule.metric.title)"), message: rule.describe(current: exampleValue))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.vertical, 2)
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

    private func preview() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showPreview = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation(.easeOut(duration: 0.25)) { showPreview = false }
        }
    }
}

/// A highlighted word that opens a menu.
private struct TokenMenu<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        Menu { content } label: {
            Text(title).fontWeight(.medium)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 7)
        .padding(.vertical, 1)
        .background(Capsule().fill(Color.accentColor.opacity(0.14)))
        .foregroundStyle(Color.accentColor)
    }
}

/// Converts a horizontal drag into a value change: 1 unit per 4 pt, or per 12 pt with ⌥ held.
enum AlertScrub {
    static func value(start: Double, dx: CGFloat, fine: Bool, range: ClosedRange<Double>) -> Double {
        let perPoint = fine ? 1.0 / 12 : 1.0 / 4
        return min(max((start + Double(dx) * perPoint).rounded(), range.lowerBound), range.upperBound)
    }
}

/// A number you can drag sideways to adjust (with a trackpad tick every 5) or click to type.
private struct NumberToken: View {
    @Binding var value: Double
    let unit: String
    let range: ClosedRange<Double>
    @State private var editing = false
    @State private var dragStart: Double?
    @State private var lastTick: Int?
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if editing {
                TextField("Value", value: Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) }),
                          format: .number)
                    .labelsHidden()
                    .frame(width: 48)
                    .focused($focused)
                    .onSubmit { editing = false }
                    .onChange(of: focused) { _, isFocused in if !isFocused { editing = false } }
                    .onAppear { focused = true }
            } else {
                Text("\(Int(value))\(unit)")
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: value))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(dragStart == nil ? 0.14 : 0.26)))
                    .foregroundStyle(Color.accentColor)
                    .onHover { inside in inside ? NSCursor.resizeLeftRight.push() : NSCursor.pop() }
                    .gesture(DragGesture(minimumDistance: 2)
                        .onChanged { drag in
                            if dragStart == nil { dragStart = value }
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
                        .onEnded { _ in dragStart = nil; lastTick = nil })
                    .onTapGesture { editing = true }
                    .help("Drag sideways to adjust (⌥ for fine steps), or click to type")
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Threshold")
        .accessibilityValue("\(Int(value)) \(unit)")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 1.0 : -1.0
            value = min(max(value + step, range.lowerBound), range.upperBound)
        }
    }
}

/// A miniature of the banner the alert will post.
private struct NotificationPreview: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
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
