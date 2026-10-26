import AppKit
import EventKit
import SwiftUI

/// An upcoming calendar event or a reminder due today, ready to show.
nonisolated struct UpcomingItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let isReminder: Bool
    /// The calendar's color as hex, so the struct stays simple to pass around.
    let colorHex: String?
    /// A Zoom, Meet, Teams, Webex or FaceTime link found in the event.
    let meetingLink: URL?
}

/// One event on the day picked in the month view.
nonisolated struct DayEvent: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let colorHex: String?
    /// Where it happens: the meeting service ("Google Meet"), else the location, else the calendar.
    let detail: String?
    let meetingLink: URL?
}

/// "Up next" from the user's calendars, plus a heads-up shortly before a meeting starts.
/// EventKit announces every change; between changes the module sleeps until the next
/// moment that matters (a heads-up, an event ending, midnight).
@Observable
final class CalendarModule: IslandModule {
    enum Access {
        case notDetermined
        case granted
        case denied
    }

    let id = "calendar"
    var activity: LiveActivity? { nil }
    private(set) var access: Access = .notDetermined
    private(set) var upcoming: [UpcomingItem] = []
    /// Goes up on every change EventKit reports, so the month view knows to read again.
    private(set) var revision = 0

    @ObservationIgnored var onActivityChange: (() -> Void)?
    @ObservationIgnored var onMeetingSoon: ((UpcomingItem) -> Void)?

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var changeObserver: NSObjectProtocol?
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var announced: Set<String> = []
    @ObservationIgnored private var reminders: [UpcomingItem] = []
    @ObservationIgnored private var isStarted = false

    private static let headsUp: TimeInterval = 5 * 60
    private static let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "facetime.apple.com"]

    init(settings: SettingsStore) {
        self.settings = settings
        settings.onModuleSettingsChange { [weak self] in self?.refresh() }
    }

    func start() {
        isStarted = true
        access = Self.currentAccess()
        changeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func stop() {
        isStarted = false
        wakeTask?.cancel()
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
        changeObserver = nil
    }

    /// Asks for calendar access (and reminders, if they are switched on). Only ever called
    /// from a button, so the system prompt never appears out of nowhere.
    func requestAccess() {
        store.requestFullAccessToEvents { @Sendable _, _ in
            Task { @MainActor in
                self.access = Self.currentAccess()
                self.requestRemindersIfNeeded()
                self.refresh()
            }
        }
    }

    func requestRemindersIfNeeded() {
        guard settings.showReminders, EKEventStore.authorizationStatus(for: .reminder) == .notDetermined else { return }
        store.requestFullAccessToReminders { @Sendable _, _ in
            Task { @MainActor in self.refresh() }
        }
    }

    func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: Refreshing

    func refresh() {
        guard isStarted else { return }
        access = Self.currentAccess()
        guard access == .granted else {
            upcoming = []
            return
        }
        let events = loadEvents()
        if settings.showReminders && EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            loadReminders()
        } else {
            reminders = []
        }
        upcoming = Array((events + reminders).sorted(by: Self.order).prefix(4))
        scheduleWake(events: events)
        revision += 1
    }

    // MARK: Month view

    /// Each day in the range that has an event, with the first event's calendar colour.
    func eventDays(from start: Date, to end: Date) -> [Date: String] {
        guard access == .granted else { return [:] }
        let calendar = Calendar.current
        var days: [Date: String] = [:]
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        for event in store.events(matching: predicate) where !Self.isDeclined(event) {
            var day = calendar.startOfDay(for: max(event.startDate, start))
            // A multi-day event marks every day it covers.
            while day < min(event.endDate, end) {
                if days[day] == nil {
                    days[day] = event.calendar.map { Self.hex($0.color) } ?? "#8E8E93"
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return days
    }

    func events(on day: Date) -> [DayEvent] {
        guard access == .granted else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !Self.isDeclined($0) }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map { event in
                let link = Self.meetingLink(in: event)
                return DayEvent(
                    id: event.calendarItemIdentifier + "@" + String(event.startDate.timeIntervalSince1970),
                    title: event.title ?? "",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    colorHex: event.calendar.map { Self.hex($0.color) },
                    detail: link.flatMap(Self.serviceName) ?? event.location.flatMap { $0.isEmpty ? nil : $0 } ?? event.calendar?.title,
                    meetingLink: link
                )
            }
    }

    /// "14:30 Toplantı" or just "Toplantı" (next full hour), an hour long, in the default
    /// calendar. Returns false when there is nothing to add or no calendar to add it to.
    @discardableResult
    func addEvent(_ text: String, on day: Date) -> Bool {
        guard access == .granted, let target = store.defaultCalendarForNewEvents else { return false }
        var title = text.trimmingCharacters(in: .whitespaces)
        let calendar = Calendar.current
        var start: Date?
        if let match = title.firstMatch(of: /^(\d{1,2})[:.](\d{2})\s+/), let hour = Int(match.1), let minute = Int(match.2), hour < 24, minute < 60 {
            start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
            title = String(title[match.range.upperBound...])
        }
        guard !title.isEmpty else { return false }
        if start == nil {
            let base = calendar.isDateInToday(day) ? Date() : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
            let hour = calendar.dateInterval(of: .hour, for: base)?.start ?? base
            start = calendar.isDateInToday(day) ? calendar.date(byAdding: .hour, value: 1, to: hour) : hour
        }
        guard let start else { return false }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(3600)
        event.calendar = target
        do {
            try store.save(event, span: .thisEvent)
            return true
        } catch {
            NSLog("ISLe8: could not add the event: \(error)")
            return false
        }
    }

    private func loadEvents() -> [UpcomingItem] {
        let now = Date()
        let calendar = Calendar.current
        guard let end = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now)) else { return [] }
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { $0.endDate > now && !Self.isDeclined($0) }
            .filter { !$0.isAllDay || calendar.isDateInToday($0.startDate) || $0.startDate < now }
            .map { event in
                UpcomingItem(
                    id: event.calendarItemIdentifier + "@" + String(event.startDate.timeIntervalSince1970),
                    title: event.title ?? "",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    isReminder: false,
                    colorHex: event.calendar.map { Self.hex($0.color) },
                    meetingLink: Self.meetingLink(in: event)
                )
            }
    }

    /// Reminders arrive through a callback; the list updates again when they do.
    private func loadReminders() {
        let calendar = Calendar.current
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: endOfToday, calendars: nil)
        store.fetchReminders(matching: predicate) { @Sendable found in
            let items: [UpcomingItem] = (found ?? []).compactMap { reminder in
                guard let due = reminder.dueDateComponents.flatMap({ Calendar.current.date(from: $0) }) else { return nil }
                return UpcomingItem(
                    id: reminder.calendarItemIdentifier,
                    title: reminder.title ?? "",
                    start: due,
                    end: due,
                    isAllDay: reminder.dueDateComponents?.hour == nil,
                    isReminder: true,
                    colorHex: reminder.calendar.map { Self.hex($0.color) },
                    meetingLink: nil
                )
            }
            Task { @MainActor in self.remindersLoaded(items) }
        }
    }

    private func remindersLoaded(_ items: [UpcomingItem]) {
        guard items != reminders else { return }
        reminders = items
        let events = upcoming.filter { !$0.isReminder }
        upcoming = Array((events + items).sorted(by: Self.order).prefix(4))
    }

    /// Sleeps until the next heads-up, the end of the current event, or midnight.
    private func scheduleWake(events: [UpcomingItem]) {
        wakeTask?.cancel()
        let now = Date()
        let calendar = Calendar.current
        var moments: [Date] = []
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            moments.append(midnight)
        }
        for event in events where !event.isAllDay {
            moments.append(event.end)
            if settings.meetingHeadsUp && !announced.contains(event.id) {
                moments.append(event.start.addingTimeInterval(-Self.headsUp))
            }
        }
        // Anything already due fires at once.
        let next = moments.map { max($0, now) }.min() ?? now.addingTimeInterval(3600)
        wakeTask = Task {
            try? await Task.sleep(for: .seconds(max(next.timeIntervalSinceNow, 0) + 0.5))
            guard !Task.isCancelled else { return }
            self.announceDueMeetings()
            self.refresh()
        }
    }

    private func announceDueMeetings() {
        guard settings.meetingHeadsUp else { return }
        let now = Date()
        for event in upcoming where !event.isReminder && !event.isAllDay && !announced.contains(event.id) {
            let until = event.start.timeIntervalSince(now)
            if until <= Self.headsUp && until > -60 {
                announced.insert(event.id)
                onMeetingSoon?(event)
            }
        }
    }

    // MARK: Helpers

    private static func order(_ a: UpcomingItem, _ b: UpcomingItem) -> Bool {
        if a.isAllDay != b.isAllDay { return a.isAllDay }
        return a.start < b.start
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    private static func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
    }

    private static func meetingLink(in event: EKEvent) -> URL? {
        if let url = event.url, isMeeting(url) {
            return url
        }
        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
        guard !text.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url).first(where: isMeeting)
    }

    private static func serviceName(_ url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        if host.contains("zoom") { return "Zoom" }
        if host.contains("meet.google") { return "Google Meet" }
        if host.contains("teams") { return "Microsoft Teams" }
        if host.contains("webex") { return "Webex" }
        if host.contains("facetime") { return "FaceTime" }
        return nil
    }

    private static func isMeeting(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return meetingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    nonisolated private static func hex(_ color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "#8E8E93" }
        return String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
    }
}

extension Color {
    /// "#RRGGBB" to a color; gray if it can't be read.
    init(hex: String?) {
        guard let hex, hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else {
            self = .gray
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
