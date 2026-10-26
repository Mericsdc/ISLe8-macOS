import SwiftUI

/// Home's calendar column: the month with a dot on days that have events, and the events of
/// the day picked in it (today to begin with). "+" adds an event to that day in a line:
/// "14:30 Toplantı".
struct CalendarColumn: View {
    @Environment(CalendarModule.self) private var calendar
    @Environment(IslandModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @State private var month = CalendarColumn.monthStart(of: .now)
    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var dots: [Date: String] = [:]
    @State private var dayEvents: [DayEvent] = []
    @State private var isAdding = false
    @State private var draft = ""
    @FocusState private var isDraftFocused: Bool

    var body: some View {
        if settings.homeStyle == .minimal {
            minimal
        } else {
            full
        }
    }

    /// The minimal strip: the next thing coming up, in one line.
    private var minimal: some View {
        HStack(spacing: 8) {
            switch calendar.access {
            case .granted:
                if let item = calendar.upcoming.first {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(hex: item.colorHex))
                        .frame(width: 3, height: 28)
                    TimelineView(.everyMinute) { context in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Text(UpcomingText.when(item, now: context.date))
                                .font(.system(size: 10))
                                .foregroundStyle(Color.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                } else {
                    Image(systemName: "calendar")
                        .foregroundStyle(.tint)
                    Text("Etkinlik yok")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                }
            case .notDetermined:
                PillButton(title: "Takvimi bağla", systemImage: "calendar") { calendar.requestAccess() }
            case .denied:
                Image(systemName: "calendar.badge.exclamationmark")
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .islandTile()
    }

    /// Dashboard: the month and the picked day. Compact: the day alone.
    private var full: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch calendar.access {
            case .granted:
                if settings.homeStyle == .dashboard {
                    header
                    MonthGrid(month: month, selected: selected, dots: dots) { selected = $0 }
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                }
                dayList
            case .notDetermined:
                Spacer(minLength: 0)
                Image(systemName: "calendar")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.tint)
                Text("Toplantılarını burada gör")
                    .font(.system(size: 12, weight: .semibold))
                PillButton(title: "Takvimi bağla", systemImage: "calendar") { calendar.requestAccess() }
                Spacer(minLength: 0)
            case .denied:
                Spacer(minLength: 0)
                Text("Takvim erişimi kapalı. Sistem Ayarları > Gizlilik ve Güvenlik > Takvimler'den ISLe8'e izin ver.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer(minLength: 0)
            }
        }
        .padding(settings.homeStyle == .dashboard ? 12 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .islandTile()
        .task(id: "\(month.timeIntervalSince1970)|\(selected.timeIntervalSince1970)|\(calendar.revision)") { reload() }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Button {
                month = Self.monthStart(of: .now)
                selected = Calendar.current.startOfDay(for: .now)
            } label: {
                HStack(spacing: 5) {
                    Text(month, format: .dateTime.month(.wide))
                        .font(.system(size: 15, weight: .semibold))
                    Text(month, format: .dateTime.year())
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
            .buttonStyle(.plain)
            .help("Bugüne dön")
            Spacer(minLength: 0)
            MonthArrow(systemImage: "chevron.left", help: "Önceki ay") { shiftMonth(-1) }
            MonthArrow(systemImage: "chevron.right", help: "Sonraki ay") { shiftMonth(1) }
        }
    }

    private var dayList: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(dayTitle)
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Button {
                    isAdding.toggle()
                    if isAdding {
                        model.requestKeyboard()
                        isDraftFocused = true
                    }
                } label: {
                    Image(systemName: isAdding ? "xmark" : "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help(isAdding ? "Vazgeç" : "Etkinlik ekle")
                .accessibilityLabel(isAdding ? "Vazgeç" : "Etkinlik ekle")
            }
            if isAdding {
                TextField("14:30 Toplantı", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.08)))
                    .focused($isDraftFocused)
                    .onSubmit(addDraft)
                    .onExitCommand { isAdding = false }
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 5) {
                    if dayEvents.isEmpty && !isAdding {
                        Text("Bu gün için etkinlik yok")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                    ForEach(dayEvents) { event in
                        DayEventRow(event: event)
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private var dayTitle: String {
        let date = selected.formatted(.dateTime.day().month(.abbreviated).weekday(.abbreviated))
        return Calendar.current.isDateInToday(selected) ? String(localized: "Bugün · \(date)") : date
    }

    private func shiftMonth(_ step: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: step, to: month) else { return }
        month = next
        // The pick follows to the same day of the new month, or today when that's the month.
        let calendar = Calendar.current
        if calendar.isDate(next, equalTo: .now, toGranularity: .month) {
            selected = calendar.startOfDay(for: .now)
        } else {
            selected = next
        }
    }

    private func addDraft() {
        if calendar.addEvent(draft, on: selected) {
            draft = ""
            isAdding = false
        }
    }

    private func reload() {
        let range = MonthGrid.visibleRange(for: month)
        dots = calendar.eventDays(from: range.start, to: range.end)
        dayEvents = calendar.events(on: selected)
    }

    static func monthStart(of date: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)?.start ?? Calendar.current.startOfDay(for: date)
    }
}

private struct MonthArrow: View {
    let systemImage: String
    let help: LocalizedStringKey
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 22)
                .background(Capsule().fill(Color.white.opacity(isHovering ? 0.1 : 0)))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(help))
        .onHover { isHovering = $0 }
    }
}

/// Weekday initials, then the weeks of the month, starting on the user's first weekday.
private struct MonthGrid: View {
    let month: Date
    let selected: Date
    let dots: [Date: String]
    let select: (Date) -> Void

    var body: some View {
        let days = Self.days(for: month)
        let calendar = Calendar.current
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(Self.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 2)
            ForEach(0..<(days.count / 7), id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(days[(week * 7)..<(week * 7 + 7)], id: \.self) { day in
                        DayCell(
                            day: day,
                            isInMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                            isToday: calendar.isDateInToday(day),
                            isSelected: calendar.isDate(day, inSameDayAs: selected),
                            dot: dots[day]
                        )
                        .onTapGesture { select(day) }
                    }
                }
            }
        }
    }

    static var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Whole weeks covering the month: five or six rows.
    static func days(for month: Date) -> [Date] {
        let range = visibleRange(for: month)
        var days: [Date] = []
        var day = range.start
        let calendar = Calendar.current
        while day < range.end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    static func visibleRange(for month: Date) -> DateInterval {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfMonth, for: month)?.start ?? month
        let last = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: month) ?? month
        let end = calendar.dateInterval(of: .weekOfMonth, for: last)?.end ?? last
        return DateInterval(start: start, end: end)
    }
}

private struct DayCell: View {
    let day: Date
    let isInMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let dot: String?

    var body: some View {
        ZStack {
            if isToday {
                Circle().fill(.tint)
            } else if isSelected {
                Circle().strokeBorder(.tint, lineWidth: 1.5)
            }
            Text(day, format: .dateTime.day())
                .font(.system(size: 11, weight: isToday ? .bold : .medium).monospacedDigit())
                .foregroundStyle(isToday ? Color.white : Color.white.opacity(isInMonth ? 0.9 : 0.28))
        }
        .frame(width: 22, height: 22)
        .overlay(alignment: .bottom) {
            if let dot, !isToday {
                Circle()
                    .fill(Color(hex: dot))
                    .frame(width: 3.5, height: 3.5)
                    .offset(y: 3)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

private struct DayEventRow: View {
    let event: DayEvent

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(hex: event.colorHex))
                .frame(width: 3, height: 16)
            Text(event.isAllDay ? String(localized: "Tüm gün") : event.start.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                if let detail = event.detail {
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let link = event.meetingLink {
                Button {
                    NSWorkspace.shared.open(link)
                } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 20, height: 18)
                        .background(Capsule().fill(.tint.opacity(0.25)))
                }
                .buttonStyle(.plain)
                .help("Katıl")
                .accessibilityLabel("Katıl")
            }
        }
    }
}

/// The heads-up banner a few minutes before a meeting.
struct MeetingAlertView: View {
    @Environment(IslandModel.self) private var model
    let item: UpcomingItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: item.colorHex))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color(hex: item.colorHex).opacity(0.2)))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                TimelineView(.everyMinute) { context in
                    Text(UpcomingText.when(item, now: context.date))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.65))
                }
            }
            Spacer(minLength: 6)
            if let link = item.meetingLink {
                PillButton(title: "Katıl", systemImage: "video.fill") {
                    NSWorkspace.shared.open(link)
                    model.dismissAlert()
                }
            }
        }
    }
}

enum UpcomingText {
    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    /// "Now · ends 15:30", "In 5 min · 15:00", "15:00 – 16:00", "Tomorrow 09:30", "All day".
    static func when(_ item: UpcomingItem, now: Date) -> String {
        let calendar = Calendar.current
        if item.isAllDay {
            return calendar.isDateInToday(item.start) || item.start < now ? String(localized: "Tüm gün") : String(localized: "Yarın · tüm gün")
        }
        if item.isReminder {
            return item.start < now ? String(localized: "Gecikti · \(time.string(from: item.start))") : String(localized: "Hatırlatıcı · \(time.string(from: item.start))")
        }
        if item.start <= now {
            return String(localized: "Şimdi · bitiş \(time.string(from: item.end))")
        }
        let minutes = Int(item.start.timeIntervalSince(now) / 60)
        if minutes < 60 {
            return String(localized: "\(max(minutes, 1)) dk sonra · \(time.string(from: item.start))")
        }
        let range = "\(time.string(from: item.start)) – \(time.string(from: item.end))"
        return calendar.isDateInTomorrow(item.start) ? String(localized: "Yarın · \(range)") : range
    }
}
