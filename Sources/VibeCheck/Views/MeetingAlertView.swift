import SwiftUI

/// Premium colorful fullscreen meeting overlay spanning connected displays right before a meeting starts.
struct MeetingAlertView: View {
    let event: CalendarEvent
    let isPreview: Bool
    let onJoin: () -> Void
    let onSnooze: (Int) -> Void
    let onOpenCalendar: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var drift = false

    private var accentColor: Color { Color(red: event.red, green: event.green, blue: event.blue) }

    // VibeCheck brand gradient tones harmonized with the meeting's calendar color.
    private static let mint = Color(red: 0.24, green: 0.88, blue: 0.71)
    private static let sky = Color(red: 0.21, green: 0.71, blue: 0.95)
    private static let violet = Color(red: 0.55, green: 0.42, blue: 1.00)
    private static let night = Color(red: 0.05, green: 0.07, blue: 0.16)
    private static let dusk = Color(red: 0.13, green: 0.16, blue: 0.34)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            ZStack {
                colorfulBackdrop
                    .onTapGesture(perform: onDismiss)

                VStack(spacing: 22) {
                    // Top metadata row: calendar badge + optional preview pill
                    HStack(spacing: 8) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(accentColor)
                                .frame(width: 9, height: 9)
                                .shadow(color: accentColor.opacity(0.85), radius: 5)
                            Text(event.calendarTitle.isEmpty ? String(localized: "Calendar") : event.calendarTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.92))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.12)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.75))

                        if isPreview {
                            Text("Preview")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(.white.opacity(0.14)))
                        }
                    }

                    // Event title
                    Text(event.title)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .tracking(-0.5)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)

                    // Countdown + time range
                    VStack(spacing: 6) {
                        Text(countdownHeadline(now: context.date))
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(
                                LinearGradient(colors: [Self.mint, Self.sky], startPoint: .leading, endPoint: .trailing)
                            )
                        HStack(spacing: 8) {
                            Label(timeRange, systemImage: "clock")
                            if !event.attendeeNames.isEmpty {
                                Text("·")
                                Label("\(event.attendeeNames.count)", systemImage: "person.2.fill")
                            }
                        }
                        .font(.callout.weight(.medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.78))
                    }

                    if let loc = event.location, !loc.isEmpty, event.videoCall == nil {
                        Label(loc, systemImage: "mappin.and.ellipse")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(2)
                    }

                    // Primary CTA
                    VStack(spacing: 12) {
                        if let link = event.videoCall {
                            Button(action: onJoin) {
                                HStack(spacing: 9) {
                                    Image(systemName: link.service.symbol)
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("Join \(link.service.title)")
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                }
                                .foregroundStyle(Self.night)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 13)
                                .background(
                                    Capsule().fill(
                                        LinearGradient(colors: [Self.mint, Self.sky],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                                    )
                                )
                                .shadow(color: Self.sky.opacity(0.45), radius: 18, y: 6)
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.return, modifiers: [])
                        } else {
                            Button(action: onOpenCalendar) {
                                HStack(spacing: 8) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 15, weight: .semibold))
                                    Text("Open in Calendar")
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                }
                                .foregroundStyle(Self.night)
                                .padding(.horizontal, 26)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule().fill(
                                        LinearGradient(colors: [Self.mint, Self.sky],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                                    )
                                )
                                .shadow(color: Self.sky.opacity(0.4), radius: 16, y: 5)
                            }
                            .buttonStyle(.plain)
                        }

                        // Secondary controls
                        HStack(spacing: 8) {
                            glassActionButton("Snooze 1m", symbol: "bell.badge") { onSnooze(1) }
                            glassActionButton("Snooze 5m", symbol: "clock.arrow.circlepath") { onSnooze(5) }
                            if event.videoCall != nil {
                                glassActionButton("Calendar", symbol: "calendar", action: onOpenCalendar)
                            }
                            glassActionButton("Dismiss", symbol: "xmark", action: onDismiss)
                                .keyboardShortcut(.escape, modifiers: [])
                        }
                    }
                    .padding(.top, 4)

                    Text(event.videoCall != nil ? "Press ↩ to join · Esc to dismiss" : "Press Esc to dismiss")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 36)
                .frame(minWidth: 460, maxWidth: 560)
                .background(cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.42), accentColor.opacity(0.5), Self.mint.opacity(0.35), .white.opacity(0.16)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.25
                        )
                )
                .shadow(color: .black.opacity(0.42), radius: 42, y: 18)
                .scaleEffect(appeared ? 1 : 0.94)
                .opacity(appeared ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .preferredColorScheme(.dark)
            .onAppear {
                if reduceMotion {
                    appeared = true
                } else {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) { appeared = true }
                    withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) { drift = true }
                }
            }
        }
    }

    private func glassActionButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(Capsule().fill(.white.opacity(0.12)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.75))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var cardSurface: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Self.dusk.opacity(0.96))
        } else {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(colors: [Self.night.opacity(0.55), Self.dusk.opacity(0.45)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                )
        }
    }

    @ViewBuilder
    private var colorfulBackdrop: some View {
        GeometryReader { geo in
            ZStack {
                if !reduceTransparency {
                    MeetingBackdropBlur()
                }
                LinearGradient(
                    colors: [Self.night.opacity(reduceTransparency ? 1 : 0.78),
                             Self.dusk.opacity(reduceTransparency ? 1 : 0.72),
                             Self.night.opacity(reduceTransparency ? 1 : 0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Vibrant ambient color orbs (brand Mint / Sky / Violet + calendar accent)
                Circle()
                    .fill(RadialGradient(colors: [Self.mint.opacity(0.55), .clear], center: .center, startRadius: 10, endRadius: geo.size.width * 0.42))
                    .frame(width: geo.size.width * 0.84, height: geo.size.width * 0.84)
                    .offset(x: -geo.size.width * 0.28 + (drift ? 36 : -18),
                            y: -geo.size.height * 0.22 + (drift ? -20 : 24))
                    .blendMode(.screen)

                Circle()
                    .fill(RadialGradient(colors: [Self.violet.opacity(0.58), .clear], center: .center, startRadius: 10, endRadius: geo.size.width * 0.45))
                    .frame(width: geo.size.width * 0.9, height: geo.size.width * 0.9)
                    .offset(x: geo.size.width * 0.28 + (drift ? -32 : 20),
                            y: geo.size.height * 0.20 + (drift ? 24 : -18))
                    .blendMode(.screen)

                Circle()
                    .fill(RadialGradient(colors: [accentColor.opacity(0.52), .clear], center: .center, startRadius: 10, endRadius: geo.size.width * 0.36))
                    .frame(width: geo.size.width * 0.72, height: geo.size.width * 0.72)
                    .offset(x: geo.size.width * 0.16 + (drift ? 20 : -24),
                            y: -geo.size.height * 0.24 + (drift ? 16 : -14))
                    .blendMode(.screen)

                Circle()
                    .fill(RadialGradient(colors: [Self.sky.opacity(0.45), .clear], center: .center, startRadius: 10, endRadius: geo.size.width * 0.34))
                    .frame(width: geo.size.width * 0.68, height: geo.size.width * 0.68)
                    .offset(x: -geo.size.width * 0.22 + (drift ? -20 : 26),
                            y: geo.size.height * 0.26 + (drift ? -18 : 22))
                    .blendMode(.screen)
            }
            .ignoresSafeArea()
        }
    }

    private func countdownHeadline(now: Date) -> String {
        if event.isHappening(at: now) { return String(localized: "Starting now") }
        let until = event.startDate.timeIntervalSince(now)
        if until <= 45 { return String(localized: "Starting now") }
        return String(localized: "Starts \(CalendarLogic.countdownText(for: event, now: now))")
    }

    private var timeRange: String {
        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}

private struct MeetingBackdropBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .fullScreenUI
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
