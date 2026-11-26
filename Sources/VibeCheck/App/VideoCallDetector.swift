import Foundation

/// Supported video-conferencing services detected from calendar event URLs, locations, and notes.
enum VideoCallService: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case zoom
    case googleMeet
    case microsoftTeams
    case webex
    case faceTime
    case slack
    case tuple
    case whereby
    case jitsi
    case discord
    case around
    case loom
    case goToMeeting
    case blueJeans
    case ringCentral
    case chime
    case gather
    case calCom
    case custom

    var title: String {
        switch self {
        case .zoom: "Zoom"
        case .googleMeet: "Google Meet"
        case .microsoftTeams: "Microsoft Teams"
        case .webex: "Webex"
        case .faceTime: "FaceTime"
        case .slack: "Slack"
        case .tuple: "Tuple"
        case .whereby: "Whereby"
        case .jitsi: "Jitsi"
        case .discord: "Discord"
        case .around: "Around"
        case .loom: "Loom"
        case .goToMeeting: "GoTo"
        case .blueJeans: "BlueJeans"
        case .ringCentral: "RingCentral"
        case .chime: "Amazon Chime"
        case .gather: "Gather"
        case .calCom: "Cal Video"
        case .custom: "Video Call"
        }
    }

    var symbol: String { "video.fill" }
}

/// A detected joinable meeting link and its recognized service.
struct VideoCallLink: Equatable, Hashable, Sendable {
    let url: URL
    let service: VideoCallService
}

/// Pure, offline parser that extracts video call URLs from a calendar event's URL, location, and notes.
enum VideoCallDetector {
    /// Scans `url`, `location`, and `notes` in priority order and returns the first recognized video call link.
    nonisolated static func detect(url: URL?, location: String?, notes: String?, customDomains: [String] = []) -> VideoCallLink? {
        if let url, let link = classify(url, customDomains: customDomains) {
            return link
        }
        for field in [location, notes] {
            guard let field, !field.isEmpty else { continue }
            for candidate in extractURLs(from: field) {
                if let link = classify(candidate, customDomains: customDomains) {
                    return link
                }
            }
        }
        return nil
    }

    /// Extracts HTTP(S) and common native meeting scheme URLs from plain text.
    nonisolated static func extractURLs(from text: String) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()

        func append(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}>'\""))
            guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return }
            let unwrapped = unwrapRedirect(url)
            if seen.insert(unwrapped.absoluteString).inserted {
                urls.append(unwrapped)
            }
        }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: range) {
                if let u = match.url { append(u.absoluteString) }
            }
        }

        // Native meeting schemes that NSDataDetector doesn't always match.
        let pattern = #"(?:zoommtg|zoomus|msteams|facetime|webex|slack)://[^\s<>"'\)\]]+"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                if let r = Range(match.range, in: text) { append(String(text[r])) }
            }
        }

        return urls
    }

    /// Unwraps Outlook SafeLinks and Google redirect wrappers to get the actual meeting URL.
    nonisolated static func unwrapRedirect(_ url: URL) -> URL {
        guard let host = url.host?.lowercased(),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        if host.hasSuffix("safelinks.protection.outlook.com"),
           let inner = comps.queryItems?.first(where: { $0.name.lowercased() == "url" })?.value,
           let parsed = URL(string: inner) {
            return parsed
        }
        if (host == "www.google.com" || host == "google.com"), url.path == "/url",
           let inner = comps.queryItems?.first(where: { $0.name == "q" || $0.name == "url" })?.value,
           let parsed = URL(string: inner) {
            return parsed
        }
        return url
    }

    /// Classifies a single URL into a `VideoCallLink` if it matches a known meeting service or custom domain.
    nonisolated static func classify(_ rawURL: URL, customDomains: [String] = []) -> VideoCallLink? {
        let url = unwrapRedirect(rawURL)
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()

        // Native app schemes
        switch scheme {
        case "zoommtg", "zoomus": return VideoCallLink(url: url, service: .zoom)
        case "msteams": return VideoCallLink(url: url, service: .microsoftTeams)
        case "facetime": return VideoCallLink(url: url, service: .faceTime)
        case "webex": return VideoCallLink(url: url, service: .webex)
        case "https", "http": break
        default: return nil
        }

        guard !host.isEmpty else { return nil }

        // Zoom: zoom.us/j/..., *.zoom.us/j/..., /s/..., /my/..., /w/..., /wc/join/...
        if host == "zoom.us" || host.hasSuffix(".zoom.us") || host == "zoom.com" || host.hasSuffix(".zoom.com") || host.hasSuffix(".zoomgov.com") {
            let validPrefixes = ["/j/", "/s/", "/my/", "/w/", "/wc/join/", "/meeting/"]
            if validPrefixes.contains(where: { path.hasPrefix($0) }) {
                return VideoCallLink(url: url, service: .zoom)
            }
            return nil
        }

        // Google Meet: meet.google.com/abc-defg-hij or /lookup/... or /_meet/...
        if host == "meet.google.com" || host == "g.co" && path.hasPrefix("/meet/") {
            if path.count > 1, !path.hasPrefix("/about"), !path.hasPrefix("/landing") {
                return VideoCallLink(url: url, service: .googleMeet)
            }
            return nil
        }

        // Microsoft Teams
        if host == "teams.microsoft.com" || host == "teams.live.com" || host == "gov.teams.microsoft.us" {
            if path.contains("/meetup-join/") || path.hasPrefix("/meet/") || path.hasPrefix("/l/call/") {
                return VideoCallLink(url: url, service: .microsoftTeams)
            }
            return nil
        }

        // Webex
        if host.hasSuffix(".webex.com") || host == "webex.com" {
            if path.contains("/meet/") || path.contains("/join/") || path.contains("/j.php") || path.contains("/m/") {
                return VideoCallLink(url: url, service: .webex)
            }
            return nil
        }

        // FaceTime web link
        if host == "facetime.apple.com" && path.hasPrefix("/join") {
            return VideoCallLink(url: url, service: .faceTime)
        }

        // Slack Huddles
        if host == "app.slack.com" && path.hasPrefix("/huddle/") {
            return VideoCallLink(url: url, service: .slack)
        }

        // Tuple
        if host == "tuple.app" || host.hasSuffix(".tuple.app") {
            return VideoCallLink(url: url, service: .tuple)
        }

        // Whereby
        if host == "whereby.com" || host.hasSuffix(".whereby.com") {
            if path.count > 1 { return VideoCallLink(url: url, service: .whereby) }
            return nil
        }

        // Jitsi
        if host == "meet.jit.si" || host == "8x8.vc" {
            if path.count > 1 { return VideoCallLink(url: url, service: .jitsi) }
            return nil
        }

        // Discord voice / stage / events
        if host == "discord.gg" || (host == "discord.com" && (path.hasPrefix("/channels/") || path.hasPrefix("/events/"))) {
            return VideoCallLink(url: url, service: .discord)
        }

        // Around
        if host == "meet.around.co" || host == "around.co" && path.hasPrefix("/r/") {
            return VideoCallLink(url: url, service: .around)
        }

        // GoToMeeting
        if host == "meet.goto.com" || host == "global.gotomeeting.com" || host == "app.gotomeeting.com" {
            return VideoCallLink(url: url, service: .goToMeeting)
        }

        // BlueJeans
        if host == "bluejeans.com" || host.hasSuffix(".bluejeans.com") {
            if path.count > 1 { return VideoCallLink(url: url, service: .blueJeans) }
            return nil
        }

        // RingCentral
        if host == "v.ringcentral.com" || host == "meetings.ringcentral.com" {
            return VideoCallLink(url: url, service: .ringCentral)
        }

        // Amazon Chime
        if host == "chime.aws" && path.count > 1 {
            return VideoCallLink(url: url, service: .chime)
        }

        // Gather
        if host == "app.gather.town" && path.hasPrefix("/app/") {
            return VideoCallLink(url: url, service: .gather)
        }

        // Cal.com Video
        if host == "app.cal.com" && path.hasPrefix("/video/") {
            return VideoCallLink(url: url, service: .calCom)
        }

        // Loom
        if host == "www.loom.com" && path.hasPrefix("/meet/") {
            return VideoCallLink(url: url, service: .loom)
        }

        // User-configured custom meeting domains
        for domain in customDomains {
            let clean = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !clean.isEmpty else { continue }
            if host == clean || host.hasSuffix(".\(clean)") {
                return VideoCallLink(url: url, service: .custom)
            }
        }

        return nil
    }
}
