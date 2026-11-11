#if os(macOS)
import EventKit
import Foundation

/// Mirrors due dates into a "Skyward Plus" list in Reminders or a "Skyward Plus"
/// calendar. Items are matched by a link stored on each one, so repeated syncs
/// update instead of duplicating, and items that are no longer due are removed.
actor CalendarExport {
    static let shared = CalendarExport()
    static let name = "Skyward Plus"

    private let store = EKEventStore()

    enum Access { case granted, denied }

    func requestAccess(for target: ExportTarget) async -> Access {
        do {
            switch target {
            case .off: return .granted
            case .reminders: return try await store.requestFullAccessToReminders() ? .granted : .denied
            case .calendar: return try await store.requestFullAccessToEvents() ? .granted : .denied
            }
        } catch {
            return .denied
        }
    }

    private func link(_ id: String) -> URL? {
        var comps = URLComponents()
        comps.scheme = "skywardplus"
        comps.host = "item"
        comps.path = "/" + id
        return comps.url
    }

    func sync(target: ExportTarget, items: [AppModel.DueItem], student: String) async {
        guard target != .off, await requestAccess(for: target) == .granted else { return }
        switch target {
        case .reminders: syncReminders(items)
        case .calendar: syncEvents(items)
        case .off: break
        }
    }

    // MARK: Reminders

    private func remindersList() -> EKCalendar? {
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == CalendarExport.name }) { return existing }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = CalendarExport.name
        list.source = store.defaultCalendarForNewReminders()?.source ?? store.sources.first { $0.sourceType == .local }
        guard list.source != nil, (try? store.saveCalendar(list, commit: true)) != nil else { return nil }
        return list
    }

    private func syncReminders(_ items: [AppModel.DueItem]) {
        guard let list = remindersList() else { return }
        let predicate = store.predicateForReminders(in: [list])
        let semaphore = DispatchSemaphore(value: 0)
        var existing: [EKReminder] = []
        store.fetchReminders(matching: predicate) { found in
            existing = found ?? []
            semaphore.signal()
        }
        semaphore.wait()

        var byLink: [String: EKReminder] = [:]
        for reminder in existing { if let url = reminder.url?.absoluteString { byLink[url] = reminder } }
        var keep = Set<String>()
        for item in items {
            guard let url = link(item.id) else { continue }
            keep.insert(url.absoluteString)
            let reminder = byLink[url.absoluteString] ?? EKReminder(eventStore: store)
            reminder.calendar = list
            reminder.title = item.course.isEmpty ? item.title : "\(item.title) (\(item.course))"
            reminder.notes = item.notes.isEmpty ? nil : item.notes
            reminder.url = url
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: item.due)
            if item.done { reminder.isCompleted = true }
            try? store.save(reminder, commit: false)
        }
        // Remove items that are gone from Skyward, but keep ones the person ticked off.
        for reminder in existing {
            guard let url = reminder.url?.absoluteString, url.hasPrefix("skywardplus://"), !keep.contains(url), !reminder.isCompleted else { continue }
            try? store.remove(reminder, commit: false)
        }
        try? store.commit()
    }

    // MARK: Calendar

    private func calendar() -> EKCalendar? {
        if let existing = store.calendars(for: .event).first(where: { $0.title == CalendarExport.name }) { return existing }
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = CalendarExport.name
        cal.cgColor = CGColor(red: 0.18, green: 0.5, blue: 0.93, alpha: 1)
        cal.source = store.defaultCalendarForNewEvents?.source ?? store.sources.first { $0.sourceType == .local }
        guard cal.source != nil, (try? store.saveCalendar(cal, commit: true)) != nil else { return nil }
        return cal
    }

    private func syncEvents(_ items: [AppModel.DueItem]) {
        guard let cal = calendar() else { return }
        let start = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        let end = Calendar.current.date(byAdding: .day, value: 365, to: Date()) ?? Date()
        let existing = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: [cal]))
        var byLink: [String: EKEvent] = [:]
        for event in existing { if let url = event.url?.absoluteString { byLink[url] = event } }
        var keep = Set<String>()
        for item in items where !item.done {
            guard let url = link(item.id) else { continue }
            keep.insert(url.absoluteString)
            let event = byLink[url.absoluteString] ?? EKEvent(eventStore: store)
            event.calendar = cal
            event.title = item.course.isEmpty ? item.title : "\(item.title) (\(item.course))"
            event.notes = item.notes.isEmpty ? nil : item.notes
            event.url = url
            event.isAllDay = true
            event.startDate = Calendar.current.startOfDay(for: item.due)
            event.endDate = event.startDate
            try? store.save(event, span: .thisEvent, commit: false)
        }
        let today = Calendar.current.startOfDay(for: Date())
        for event in existing {
            guard let url = event.url?.absoluteString, url.hasPrefix("skywardplus://"), !keep.contains(url), event.startDate >= today else { continue }
            try? store.remove(event, span: .thisEvent, commit: false)
        }
        try? store.commit()
    }
}
#endif
