import EventKit
import Foundation
import Observation

struct CalendarEvent: Equatable {
    let title: String
    let start: Date
    let end: Date
    let calendarTitle: String
}

/// Finds the calendar event happening around now so a new note can be named after it.
@MainActor @Observable
final class CalendarContext {
    private(set) var currentEvent: CalendarEvent?
    private(set) var status = EKEventStore.authorizationStatus(for: .event)
    private let store = EKEventStore()

    var canRequestAccess: Bool { status == .notDetermined }
    var hasAccess: Bool { status == .fullAccess }

    func requestAccess() async {
        _ = try? await store.requestFullAccessToEvents()
        status = EKEventStore.authorizationStatus(for: .event)
        refresh()
    }

    func refresh() {
        status = EKEventStore.authorizationStatus(for: .event)
        guard hasAccess else {
            currentEvent = nil
            return
        }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3 * 60 * 60),
                                                 end: now.addingTimeInterval(30 * 60), calendars: nil)
        let event = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now && !($0.title ?? "").isEmpty }
            .min { abs($0.startDate.timeIntervalSince(now)) < abs($1.startDate.timeIntervalSince(now)) }
        currentEvent = event.map {
            CalendarEvent(title: $0.title ?? "", start: $0.startDate, end: $0.endDate,
                          calendarTitle: $0.calendar?.title ?? "")
        }
    }
}
