import SwiftUI
import MuesliCore

enum MeetingBrowserFilter: Hashable {
    case all, last2Days, lastWeek, last2Weeks, lastMonth, last3Months

    var label: String {
        switch self {
        case .all: return tr("All time", "За всё время")
        case .last2Days: return tr("Last 2 days", "Последние 2 дня")
        case .lastWeek: return tr("Last week", "Последняя неделя")
        case .last2Weeks: return tr("Last 2 weeks", "Последние 2 недели")
        case .lastMonth: return tr("Last month", "Последний месяц")
        case .last3Months: return tr("Last 3 months", "Последние 3 месяца")
        }
    }
}

enum MeetingBrowserSort: Hashable {
    case newestFirst
    case oldestFirst

    var label: String {
        switch self {
        case .newestFirst: return tr("Newest first", "Сначала новые")
        case .oldestFirst: return tr("Oldest first", "Сначала старые")
        }
    }
}

enum MeetingBrowserLogic {
    static func availableFilters(
        for meetings: [MeetingRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MeetingBrowserFilter] {
        var filters: [MeetingBrowserFilter] = [.all]
        let oldestDate = meetings.compactMap { parseDate($0.startTime) }.min()

        guard let oldest = oldestDate else { return filters }
        let daysSinceOldest = calendar.dateComponents([.day], from: oldest, to: now).day ?? 0

        if daysSinceOldest >= 1 { filters.append(.last2Days) }
        if daysSinceOldest >= 3 { filters.append(.lastWeek) }
        if daysSinceOldest >= 8 { filters.append(.last2Weeks) }
        if daysSinceOldest >= 15 { filters.append(.lastMonth) }
        if daysSinceOldest >= 31 { filters.append(.last3Months) }

        return filters
    }

    static func filteredMeetings(
        from meetings: [MeetingRecord],
        filter: MeetingBrowserFilter,
        sort: MeetingBrowserSort,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MeetingRecord] {
        let threshold = threshold(for: filter, now: now, calendar: calendar)
        let filtered = meetings.filter { isAfterThreshold($0, threshold: threshold) }

        return filtered.sorted { lhs, rhs in
            let lhsDate = parseDate(lhs.startTime) ?? .distantPast
            let rhsDate = parseDate(rhs.startTime) ?? .distantPast
            switch sort {
            case .newestFirst:
                return lhsDate > rhsDate
            case .oldestFirst:
                return lhsDate < rhsDate
            }
        }
    }

    private static func threshold(
        for filter: MeetingBrowserFilter,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        switch filter {
        case .all:
            return nil
        case .last2Days:
            return calendar.date(byAdding: .day, value: -2, to: now)
        case .lastWeek:
            return calendar.date(byAdding: .day, value: -7, to: now)
        case .last2Weeks:
            return calendar.date(byAdding: .day, value: -14, to: now)
        case .lastMonth:
            return calendar.date(byAdding: .month, value: -1, to: now)
        case .last3Months:
            return calendar.date(byAdding: .month, value: -3, to: now)
        }
    }

    private static func isAfterThreshold(_ meeting: MeetingRecord, threshold: Date?) -> Bool {
        guard let threshold else { return true }
        guard let date = parseDate(meeting.startTime) else { return false }
        return date >= threshold
    }

    static func parseDate(_ raw: String) -> Date? {
        isoParsers.lazy.compactMap { $0.date(from: raw) }.first
            ?? localParsers.lazy.compactMap { $0.date(from: raw) }.first
    }

    static func formatStartTime(
        _ raw: String,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        guard let date = parseDate(raw) else {
            return formatStartTimeFallback(raw)
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private static func formatStartTimeFallback(_ raw: String) -> String {
        let clean = raw.replacingOccurrences(of: "T", with: " ")
        if clean.count > 16 {
            return String(clean.prefix(16))
        }
        return clean
    }

    private static let isoParsers: [ISO8601DateFormatter] = {
        let iso1 = ISO8601DateFormatter()
        iso1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        return [iso1, iso2]
    }()

    private static let localParsers: [DateFormatter] = {
        let local1: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
            return f
        }()
        let local2: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return f
        }()
        return [local1, local2]
    }()
}

struct MeetingsView: View {
    let appState: AppState
    let controller: MuesliController

    private var currentDocumentMeeting: MeetingRecord? {
        guard case let .document(id) = appState.meetingsNavigationState else { return nil }
        if appState.selectedMeetingID == id, let selectedMeeting = appState.selectedMeeting {
            return selectedMeeting
        }
        return controller.meeting(id: id)
    }

    var body: some View {
        HStack(spacing: 5) {
            PrimaryColumn(appState: appState, title: tr("Meetings", "Встречи")) {
                MeetingsListPane(
                    appState: appState,
                    controller: controller
                )
            } trailing: {
                MeetingsHeaderControls(
                    appState: appState,
                    controller: controller
                )
            }

            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(
            isPresented: Binding(
                get: { appState.isMeetingTemplatesManagerPresented },
                set: { appState.isMeetingTemplatesManagerPresented = $0 }
            )
        ) {
            MeetingTemplatesManagerView(
                appState: appState,
                controller: controller,
                onClose: { appState.isMeetingTemplatesManagerPresented = false },
                startsCreating: appState.meetingTemplatesManagerStartsCreating,
                startsEditingTemplateID: appState.meetingTemplatesManagerStartsEditingID
            )
        }
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let urlString = String(data: data, encoding: .utf8),
                      let url = URL(string: urlString) else { return }
                guard AudioFileImportController.isSupportedFileURL(url) else { return }
                DispatchQueue.main.async {
                    controller.importAudioFileFromURL(url)
                }
            }
            return true
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let meeting = currentDocumentMeeting {
            // No .id(meeting.id): recreating the heavy detail view from scratch
            // on every row click caused visible lag. MeetingDetailView already
            // syncs its local state in place via onChange(of: meeting.id).
            MeetingDetailView(
                meeting: meeting,
                controller: controller,
                appState: appState,
                onBack: nil
            )
        } else {
            VStack(spacing: MuesliTheme.spacing12) {
                Image(systemName: "person.2.wave.2")
                    .font(.system(size: 42, weight: .thin))
                    .foregroundStyle(MuesliTheme.textTertiary)
                Text(tr("Select a meeting", "Выберите встречу"))
                    .font(MuesliTheme.title3())
                    .foregroundStyle(MuesliTheme.textSecondary)
                Text(tr("Choose a meeting from the list or start a new recording.", "Выберите встречу из списка или начните новую запись."))
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
