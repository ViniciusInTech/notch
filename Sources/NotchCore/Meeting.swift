import Foundation

/// A calendar event reduced to what the island shows.
public struct Meeting: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    /// Video call link found in the event, if any.
    public let link: URL?

    public init(id: String, title: String, start: Date, end: Date, link: URL? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.link = link
    }
}

public enum MeetingLink {
    /// Only known video services are offered as "Entrar"; any other link stays in the calendar.
    static let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com",
                        "whereby.com", "meet.jit.si", "facetime.apple.com", "chime.aws"]

    /// First link to a known video service in the event's URL, location or notes. Calendars often
    /// store just "meet.google.com/abc-defg-hij"; links to known services are opened over HTTPS.
    public static func find(in texts: [String?]) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for text in texts.compactMap({ $0 }) where !text.isEmpty {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: range) {
                guard let found = match.url, ["https", "http"].contains(found.scheme?.lowercased() ?? ""),
                      let host = found.host?.lowercased(),
                      hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { continue }
                var parts = URLComponents(url: found, resolvingAgainstBaseURL: false)
                parts?.scheme = "https"
                if let url = parts?.url { return url }
            }
        }
        return nil
    }
}

public struct MeetingAlert: Equatable, Sendable {
    public enum Phase: Sendable { case soon, now }
    public let meeting: Meeting
    public let phase: Phase

    /// Whole minutes until the start, rounded up; zero once it started.
    public func minutesLeft(at date: Date) -> Int {
        max(0, Int(ceil(meeting.start.timeIntervalSince(date) / 60)))
    }
}

public enum MeetingSchedule {
    /// How long a started meeting stays on the island, unless it ends first.
    public static let nowWindow: TimeInterval = 600
    public static let leadOptions = [1, 5, 10, 15]

    static func shownUntil(_ meeting: Meeting) -> Date {
        let end = min(meeting.end, meeting.start.addingTimeInterval(nowWindow))
        return max(end, meeting.start.addingTimeInterval(60))
    }

    private static func eligible(_ meetings: [Meeting], linkOnly: Bool, dismissed: Set<String>) -> [Meeting] {
        meetings.filter { !dismissed.contains($0.id) && (!linkOnly || $0.link != nil) }
    }

    /// The earliest meeting between `lead` minutes before its start and the end of its "now" window.
    public static func alert(in meetings: [Meeting], at date: Date, leadMinutes: Int, linkOnly: Bool,
                             dismissed: Set<String> = []) -> MeetingAlert? {
        let lead = Double(max(0, leadMinutes)) * 60
        let shown = eligible(meetings, linkOnly: linkOnly, dismissed: dismissed)
            .filter { date >= $0.start.addingTimeInterval(-lead) && date < shownUntil($0) }
            .min { $0.start < $1.start }
        return shown.map { MeetingAlert(meeting: $0, phase: date >= $0.start ? .now : .soon) }
    }

    /// The next moment the alert can change: a lead time, a start or the end of a "now" window.
    public static func nextChange(in meetings: [Meeting], after date: Date, leadMinutes: Int, linkOnly: Bool,
                                  dismissed: Set<String> = []) -> Date? {
        let lead = Double(max(0, leadMinutes)) * 60
        return eligible(meetings, linkOnly: linkOnly, dismissed: dismissed)
            .flatMap { [$0.start.addingTimeInterval(-lead), $0.start, shownUntil($0)] }
            .filter { $0 > date }
            .min()
    }
}
