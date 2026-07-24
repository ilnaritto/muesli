import SwiftUI

// MARK: - Layout model

struct SummaryKPI: Equatable, Sendable {
    let value: String
    let label: String
}

struct SummaryPersonChip: Equatable, Sendable {
    let name: String
    let role: String?
}

struct SummaryTimelineEntry: Equatable, Sendable {
    let time: String
    let text: String
}

struct SummaryChartPoint: Equatable, Sendable {
    let label: String
    let value: Double
}

enum SummaryChartKind: Equatable, Sendable {
    case bar
    case line
    case pie
}

struct SummaryChartSpec: Equatable, Sendable {
    let kind: SummaryChartKind
    let title: String
    let points: [SummaryChartPoint]
}

enum SummaryAlertLevel: String, Sendable {
    case info
    case warning
    case critical
}

enum SummaryCardRow: Equatable, Sendable {
    case paragraph(String)
    case bullet(String)
    case numbered(Int, String)
    case todo(assignee: String?, text: String, due: String?, done: Bool)
    /// An alert emitted while a card is open nests inside it as a tinted row
    /// (a standalone alert with no open card stays a top-level block).
    case alert(level: SummaryAlertLevel, text: String)
    /// A substantive point rendered as an icon tile + title + description —
    /// the preferred replacement for walls of plain bullets.
    case item(title: String, description: String?, icon: String)
}

struct SummaryCardSpec: Equatable, Sendable {
    var title: String
    var icon: String
    var colorName: String
    var rows: [SummaryCardRow]
}

enum SummaryLayoutBlock: Equatable, Sendable {
    case header(title: String, subtitle: String?)
    case kpiRow([SummaryKPI])
    case card(SummaryCardSpec)
    case quote(text: String, author: String?)
    case alert(level: SummaryAlertLevel, text: String)
    case personRow([SummaryPersonChip])
    case progress(current: Double, total: Double, label: String?)
    case chart(SummaryChartSpec)
    case timeline([SummaryTimelineEntry])
    case divider
}

// MARK: - Palette

enum SummaryPalette {
    /// Named colors the LLM may reference — mapped to the Insights palette.
    static func color(named name: String) -> Color {
        switch name.lowercased() {
        case "blue": return Color(hex: 0x007AFF)
        case "green": return Color(hex: 0x34C759)
        case "purple": return Color(hex: 0xAF52DE)
        case "orange": return Color(hex: 0xFF9500)
        case "red": return Color(hex: 0xEF4444)
        case "gray", "grey": return Color(hex: 0x8E8E93)
        default: return MuesliTheme.accent
        }
    }

    static func alertColor(_ level: SummaryAlertLevel) -> Color {
        switch level {
        case .info: return Color(hex: 0x007AFF)
        case .warning: return Color(hex: 0xFF9500)
        case .critical: return Color(hex: 0xEF4444)
        }
    }

    /// Cycling series colors for pie/bar charts.
    static let seriesHexes: [Int] = [0x007AFF, 0x34C759, 0xAF52DE, 0xFF9500, 0xEF4444, 0x8E8E93]

    static func seriesColor(at index: Int) -> Color {
        Color(hex: seriesHexes[index % seriesHexes.count])
    }
}

// MARK: - Detection + conversion helpers

enum SummaryLayout {
    /// Cheap check that a stored notes string is designed markup rather than
    /// markdown: the header sentinel, or a majority of component-shaped lines.
    static func isDesignedMarkup(_ text: String) -> Bool {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return false }
        if lineHasComponentShape(first, name: "header") { return true }

        guard lines.count >= 3 else { return false }
        let componentLines = lines.filter { line in
            guard let head = line.split(separator: "|", maxSplits: 1).first else { return false }
            let name = head.trimmingCharacters(in: .whitespaces).lowercased()
            return SummaryComponentRegistry.componentsByName[name] != nil && line.contains("|")
        }
        return Double(componentLines.count) / Double(lines.count) >= 0.5
    }

    private static func lineHasComponentShape(_ line: String, name: String) -> Bool {
        let lowered = line.lowercased()
        guard lowered.hasPrefix(name) else { return false }
        let rest = lowered.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
        return rest.hasPrefix("|")
    }

    /// Repairs + parses markup into renderable blocks. nil when the quality
    /// gate fails (fewer than 2 meaningful blocks) — callers fall back to the
    /// plain markdown view so the user is never left without notes.
    static func blocks(from text: String) -> [SummaryLayoutBlock]? {
        SummaryLayoutRepair.repairAndParse(text)
    }

    /// Deterministic markup→markdown conversion for every consumer that needs
    /// plain text (chat context, export, list previews, insights aggregation).
    static func markdownFromMarkup(_ text: String) -> String {
        guard let blocks = SummaryLayoutRepair.repairAndParse(text) else { return text }
        var lines: [String] = []
        for block in blocks {
            switch block {
            case .header(let title, let subtitle):
                lines.append("# \(title)")
                if let subtitle, !subtitle.isEmpty { lines.append(subtitle) }
                lines.append("")
            case .kpiRow(let kpis):
                lines.append(kpis.map { "**\($0.value)** \($0.label)" }.joined(separator: " · "))
                lines.append("")
            case .card(let card):
                lines.append("## \(card.title)")
                var numberedIndex = 0
                for row in card.rows {
                    switch row {
                    case .paragraph(let text):
                        lines.append(text)
                    case .bullet(let text):
                        lines.append("- \(text)")
                    case .numbered(let number, let text):
                        numberedIndex = number
                        lines.append("\(numberedIndex). \(text)")
                    case .todo(let assignee, let text, let due, let done):
                        var item = done ? "- [x] " : "- [ ] "
                        if let assignee, !assignee.isEmpty { item += "\(assignee): " }
                        item += text
                        if let due, !due.isEmpty { item += " — \(due)" }
                        lines.append(item)
                    case .alert(let level, let text):
                        let marker = level == .critical ? "🔴" : (level == .info ? "ℹ️" : "⚠️")
                        lines.append("- \(marker) \(text)")
                    case .item(let title, let description, _):
                        if let description, !description.isEmpty {
                            lines.append("- **\(title)** — \(description)")
                        } else {
                            lines.append("- **\(title)**")
                        }
                    }
                }
                lines.append("")
            case .quote(let text, let author):
                lines.append("> \(text)\(author.map { " — \($0)" } ?? "")")
                lines.append("")
            case .alert(let level, let text):
                let marker: String
                switch level {
                case .info: marker = "ℹ️"
                case .warning: marker = "⚠️"
                case .critical: marker = "🔴"
                }
                lines.append("> \(marker) \(text)")
                lines.append("")
            case .personRow(let people):
                let names = people.map { person -> String in
                    if let role = person.role, !role.isEmpty { return "\(person.name) (\(role))" }
                    return person.name
                }
                lines.append(names.joined(separator: ", "))
                lines.append("")
            case .progress(let current, let total, let label):
                let currentText = formattedNumber(current)
                let totalText = formattedNumber(total)
                lines.append("\(label ?? "")\(label == nil ? "" : ": ")\(currentText)/\(totalText)")
                lines.append("")
            case .chart(let chart):
                lines.append("**\(chart.title)**")
                for point in chart.points {
                    lines.append("- \(point.label) — \(formattedNumber(point.value))")
                }
                lines.append("")
            case .timeline(let entries):
                for entry in entries {
                    lines.append("- \(entry.time) — \(entry.text)")
                }
                lines.append("")
            case .divider:
                lines.append("---")
                lines.append("")
            }
        }
        let result = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? text : result
    }

    /// Markdown consumers call this on any stored notes string: designed
    /// markup is converted, plain markdown passes through untouched.
    static func plainText(_ text: String) -> String {
        guard isDesignedMarkup(text) else { return text }
        return markdownFromMarkup(text)
    }

    private static func formattedNumber(_ value: Double) -> String {
        if value.rounded() == value && abs(value) < 1_000_000 {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}
