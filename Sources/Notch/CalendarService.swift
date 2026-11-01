import AppKit
import EventKit
import NotchCore

struct CalendarInfo: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
}

/// Reads upcoming events off the main actor. Access is requested only when the user turns
/// the agenda on; nothing is written to the calendar.
actor CalendarService {
    private let store = EKEventStore()

    nonisolated static var undetermined: Bool { EKEventStore.authorizationStatus(for: .event) == .notDetermined }
    nonisolated static var authorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    nonisolated static var denied: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .denied || status == .restricted || status == .writeOnly
    }

    func requestAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        // A store created before the grant does not see the calendars until reset.
        if granted { store.reset() }
        return granted
    }

    func calendars() -> [CalendarInfo] {
        guard Self.authorized else { return [] }
        return store.calendars(for: .event)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Timed events from shortly before now until `hours` ahead; all-day, canceled and declined ones are left out.
    func meetings(from date: Date, hours: Double, excluding excluded: Set<String>) -> [Meeting] {
        guard Self.authorized else { return [] }
        store.refreshSourcesIfNecessary()
        let calendars = store.calendars(for: .event).filter { !excluded.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: date.addingTimeInterval(-MeetingSchedule.nowWindow),
                                                 end: date.addingTimeInterval(hours * 3600), calendars: calendars)
        return store.events(matching: predicate).compactMap { event in
            guard !event.isAllDay, event.status != .canceled,
                  event.attendees?.first(where: \.isCurrentUser)?.participantStatus != .declined else { return nil }
            let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Meeting(id: "\(event.calendarItemIdentifier)@\(Int(event.startDate.timeIntervalSince1970))",
                           title: title.isEmpty ? "Reunião" : title, start: event.startDate, end: event.endDate,
                           link: MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes]))
        }
    }

    nonisolated static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}
