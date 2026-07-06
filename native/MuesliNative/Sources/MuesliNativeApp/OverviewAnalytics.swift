import Foundation
import MuesliCore

// MARK: - Display models

struct WeekdayActivity: Identifiable, Sendable {
    let weekday: Int          // 1 = Monday … 7 = Sunday
    let minutes: Double
    var id: Int { weekday }

    var shortLabel: String {
        let ru = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
        let en = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let idx = min(max(weekday - 1, 0), 6)
        return tr(en[idx], ru[idx])
    }
}

struct WeekPoint: Identifiable, Sendable {
    let weekStart: Date
    let avgMinutes: Double
    var id: Date { weekStart }
}

struct WordFrequency: Identifiable, Sendable {
    let word: String
    let count: Int
    var id: String { word }
}

struct FillerStats: Sendable {
    let totalFillers: Int
    let totalWords: Int
    let top: [WordFrequency]   // most-used filler words
    var percent: Double { totalWords > 0 ? Double(totalFillers) / Double(totalWords) * 100 : 0 }
}

/// The whole non-AI Overview dataset, computed off the main thread.
struct OverviewAnalytics: Sendable {
    var totalVoiceMinutes: Double = 0
    var wordsSavedTypingHours: Double = 0   // words ÷ 40 wpm typing ÷ 60
    var weekday: [WeekdayActivity] = []
    var meetingLengthByWeek: [WeekPoint] = []
    var avgMeetingMinutes: Double = 0
    var topWords: [WordFrequency] = []
    var fillers: FillerStats = FillerStats(totalFillers: 0, totalWords: 0, top: [])

    var isEmpty: Bool { totalVoiceMinutes == 0 && topWords.isEmpty }
}

// MARK: - Computation

enum TextAnalytics {
    static func compute(
        activity rows: [DictationStore.AnalyticsActivityRow],
        corpus: [String]
    ) -> OverviewAnalytics {
        var result = OverviewAnalytics()

        // Local formatters — this runs off the main thread, so don't touch the
        // shared DateFormatters in MeetingBrowserLogic (not concurrency-safe).
        let parse = makeDateParser()

        // Totals + weekday buckets.
        let calendar = Calendar(identifier: .gregorian)
        var weekdayMinutes = [Int: Double]()   // 1…7 (Mon…Sun)
        var totalSeconds: Double = 0
        var meetingDurations: [(date: Date, minutes: Double)] = []

        for row in rows {
            totalSeconds += row.durationSeconds
            guard let date = parse(row.timestamp) else { continue }
            let wd = mondayFirstWeekday(for: date, calendar: calendar)
            weekdayMinutes[wd, default: 0] += row.durationSeconds / 60.0
            if row.isMeeting, row.durationSeconds > 0 {
                meetingDurations.append((date, row.durationSeconds / 60.0))
            }
        }
        result.totalVoiceMinutes = totalSeconds / 60.0
        result.weekday = (1...7).map { WeekdayActivity(weekday: $0, minutes: weekdayMinutes[$0] ?? 0) }

        // Average meeting length + 8-week trend.
        if !meetingDurations.isEmpty {
            result.avgMeetingMinutes = meetingDurations.map(\.minutes).reduce(0, +) / Double(meetingDurations.count)
            result.meetingLengthByWeek = weeklyAverages(meetingDurations, weeks: 8, calendar: calendar)
        }

        // Word frequency + fillers.
        let (topWords, fillers, savedHours) = analyzeWords(corpus)
        result.topWords = topWords
        result.fillers = fillers
        result.wordsSavedTypingHours = savedHours

        return result
    }

    // MARK: word analysis

    private static func analyzeWords(_ corpus: [String]) -> ([WordFrequency], FillerStats, Double) {
        var freq = [String: Int]()
        var fillerFreq = [String: Int]()
        var totalWords = 0
        var fillerTotal = 0

        for text in corpus {
            var current = ""
            for scalar in text.unicodeScalars {
                if CharacterSet.letters.contains(scalar) {
                    current.unicodeScalars.append(scalar)
                } else {
                    tally(&current, &freq, &fillerFreq, &totalWords, &fillerTotal)
                    current = ""
                }
            }
            tally(&current, &freq, &fillerFreq, &totalWords, &fillerTotal)
        }

        let top = freq
            .filter { $0.value >= 2 }
            .sorted { $0.value > $1.value }
            .prefix(15)
            .map { WordFrequency(word: $0.key, count: $0.value) }

        let topFillers = fillerFreq
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { WordFrequency(word: $0.key, count: $0.value) }

        let savedHours = Double(totalWords) / 40.0 / 60.0   // ~40 wpm typing
        return (Array(top), FillerStats(totalFillers: fillerTotal, totalWords: totalWords, top: topFillers), savedHours)
    }

    private static func tally(
        _ word: inout String,
        _ freq: inout [String: Int],
        _ fillerFreq: inout [String: Int],
        _ totalWords: inout Int,
        _ fillerTotal: inout Int
    ) {
        guard word.count >= 3 else { word = ""; return }
        let lower = word.lowercased()
        totalWords += 1
        if fillerWords.contains(lower) {
            fillerFreq[lower, default: 0] += 1
            fillerTotal += 1
        } else if !stopWords.contains(lower) {
            freq[lower, default: 0] += 1
        }
    }

    // MARK: date helpers

    /// 1 = Monday … 7 = Sunday.
    private static func mondayFirstWeekday(for date: Date, calendar: Calendar) -> Int {
        let sundayFirst = calendar.component(.weekday, from: date)  // 1 = Sunday
        return sundayFirst == 1 ? 7 : sundayFirst - 1
    }

    private static func weeklyAverages(
        _ points: [(date: Date, minutes: Double)],
        weeks: Int,
        calendar: Calendar
    ) -> [WeekPoint] {
        var cal = calendar
        cal.firstWeekday = 2   // Monday
        var buckets = [Date: [Double]]()
        for point in points {
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: point.date)
            guard let weekStart = cal.date(from: comps) else { continue }
            buckets[weekStart, default: []].append(point.minutes)
        }
        return buckets
            .map { WeekPoint(weekStart: $0.key, avgMinutes: $0.value.reduce(0, +) / Double($0.value.count)) }
            .sorted { $0.weekStart < $1.weekStart }
            .suffix(weeks)
            .map { $0 }
    }

    /// Builds a self-contained ISO/local date parser (thread-safe: formatters
    /// are captured by this one closure, not shared).
    private static func makeDateParser() -> (String) -> Date? {
        let iso1 = ISO8601DateFormatter()
        iso1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
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
        return { raw in
            iso1.date(from: raw) ?? iso2.date(from: raw)
                ?? local1.date(from: raw) ?? local2.date(from: raw)
        }
    }

    // MARK: dictionaries

    private static let fillerWords: Set<String> = [
        // RU
        "короче", "типа", "как-то", "какбы", "значит", "ваще", "вообще",
        "блин", "ну-у", "эмм", "ммм", "получается", "собственно", "допустим",
        // EN
        "like", "basically", "actually", "literally", "honestly",
        "umm", "uhh", "erm", "kinda", "sorta",
    ]

    private static let stopWords: Set<String> = [
        // RU
        "это", "как", "что", "так", "вот", "там", "тут", "уже", "или", "если",
        "нет", "да", "но", "же", "бы", "ли", "не", "на", "по", "из", "от", "до",
        "для", "при", "про", "под", "над", "без", "они", "она", "оно", "мы", "вы",
        "он", "его", "ее", "их", "мне", "нам", "вам", "чтобы", "потому", "когда",
        "тоже", "были", "было", "быть", "есть", "буду", "будет", "может", "надо",
        "нужно", "все", "всё", "весь", "этот", "эта", "эти", "тот", "the", "and",
        // EN
        "that", "this", "with", "for", "you", "are", "was", "were", "have", "has",
        "had", "not", "but", "they", "them", "then", "than", "there", "here", "just",
        "will", "would", "should", "could", "about", "into", "your", "our", "their",
        "what", "which", "who", "when", "how", "some", "all", "any", "can", "get",
        "got", "one", "out", "his", "her", "its", "yeah", "okay",
    ]
}
