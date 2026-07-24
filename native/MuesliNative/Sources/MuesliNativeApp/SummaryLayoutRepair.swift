import Foundation

/// Deterministic repair + parse of LLM-emitted designed-summary markup.
///
/// Unlike vanilla OpenUI (which drops invalid output), this layer actively
/// FIXES it so even weak local models produce a working design: fuzzy
/// component names, arity padding, markdown-slip conversion, icon/color
/// whitelisting, structural grouping. Pure functions — fully unit-testable.
enum SummaryLayoutRepair {
    // MARK: - Entry point

    /// Returns renderable blocks, or nil when the quality gate fails
    /// (fewer than 2 meaningful blocks after repair).
    static func repairAndParse(_ raw: String) -> [SummaryLayoutBlock]? {
        let lines = precleaned(raw)
        var statements: [Statement] = []
        for line in lines {
            if let statement = repairLine(line) {
                statements.append(statement)
            }
        }
        let blocks = assemble(statements)
        let meaningful = blocks.filter { block in
            if case .divider = block { return false }
            return true
        }
        guard meaningful.count >= 2 else { return nil }
        return blocks
    }

    // MARK: - Intermediate representation

    /// One repaired line before structural grouping.
    enum Statement {
        case header(title: String, subtitle: String?)
        case kpi(SummaryKPI)
        case openCard(SummaryCardSpec)
        case row(SummaryCardRow)
        case quote(text: String, author: String?)
        case alert(level: SummaryAlertLevel, text: String)
        case person(SummaryPersonChip)
        case progress(current: Double, total: Double, label: String?)
        case chart(SummaryChartSpec)
        case timelineEntry(SummaryTimelineEntry)
        case divider
    }

    // MARK: - Stage 1: pre-clean

    /// Strips code fences, <think> blocks, chatter before the first
    /// component-shaped line and trailing junk like "[end of text]".
    static func precleaned(_ raw: String) -> [String] {
        var text = raw
        text = text.replacingOccurrences(
            of: #"<think>[\s\S]*?</think>"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?is)<think\b[^>]*>[\s\S]*$"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"```[A-Za-z0-9_-]*"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?i)\[end of text\]"#,
            with: "",
            options: .regularExpression
        )

        var lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Drop leading chatter ("Вот разметка:", "Sure, here is...") until the
        // first line that looks like a component or a markdown structure we
        // can convert.
        while let first = lines.first, !isParseableLine(first) {
            lines.removeFirst()
        }
        return lines
    }

    private static func isParseableLine(_ line: String) -> Bool {
        if resolvedComponentName(for: headToken(of: line)) != nil { return true }
        return isConvertibleMarkdown(line)
    }

    private static func isConvertibleMarkdown(_ line: String) -> Bool {
        line.hasPrefix("#") || line.hasPrefix("- ") || line.hasPrefix("* ")
            || line.hasPrefix("> ") || line.range(of: #"^\d+[.)]\s"#, options: .regularExpression) != nil
    }

    // MARK: - Stage 2: per-line repair

    static func repairLine(_ rawLine: String) -> Statement? {
        var line = rawLine

        // Normalize exotic separators the model may invent. Tabs and " ; "
        // become pipes only when the line has no pipes of its own.
        if !line.contains("|") {
            if line.contains("\t") {
                line = line.replacingOccurrences(of: "\t", with: "|")
            } else if line.contains(" ; ") {
                line = line.replacingOccurrences(of: " ; ", with: "|")
            }
        }

        let head = headToken(of: line)
        if let name = resolvedComponentName(for: head) {
            return buildStatement(name: name, line: line)
        }

        // Markdown slips: a model that fell back to markdown still yields design.
        return statementFromMarkdown(line)
    }

    private static func headToken(of line: String) -> String {
        let head = line.split(separator: "|", maxSplits: 1).first.map(String.init) ?? line
        return head
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":=-–—•"))
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }

    /// Exact match, then Levenshtein-bounded fuzzy match against the registry.
    /// Distance budget scales with name length so `p`/`li` never false-match.
    static func resolvedComponentName(for token: String) -> String? {
        guard !token.isEmpty, token.count <= 24 else { return nil }
        if SummaryComponentRegistry.componentsByName[token] != nil { return token }
        var best: (name: String, distance: Int)?
        for name in SummaryComponentRegistry.componentNames {
            let allowed = name.count <= 2 ? 0 : (name.count <= 4 ? 1 : 2)
            guard allowed > 0 else { continue }
            let distance = levenshtein(token, name, cap: allowed)
            if distance <= allowed, distance < (best?.distance ?? Int.max) {
                best = (name, distance)
            }
        }
        return best?.name
    }

    /// Splits the payload respecting the component's arity: the LAST text
    /// field swallows any surplus pipes, so `|` inside quoted meeting speech
    /// never breaks parsing.
    static func fields(of line: String, spec: SummaryComponentSpec) -> [String] {
        let parts = line.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count > 1 else { return [] }
        var payload = Array(parts.dropFirst())
        if let maxFields = spec.maxFields, payload.count > maxFields, maxFields > 0 {
            let head = payload.prefix(maxFields - 1)
            let tail = payload.dropFirst(maxFields - 1).joined(separator: " | ")
            payload = Array(head) + [tail]
        }
        while let last = payload.last, last.isEmpty {
            payload.removeLast()
        }
        return payload
    }

    private static func buildStatement(name: String, line: String) -> Statement? {
        guard let spec = SummaryComponentRegistry.componentsByName[name] else { return nil }
        let fields = fields(of: line, spec: spec)
        if fields.count < spec.minFields && name != "divider" {
            // Arity repair: a single-field variant is acceptable for most
            // components; anything below that is unusable.
            guard !fields.isEmpty else { return name == "divider" ? .divider : nil }
        }

        switch name {
        case "header":
            guard let title = fields.first, !title.isEmpty else { return nil }
            return .header(title: title, subtitle: fields.count > 1 ? nonEmpty(fields[1]) : nil)
        case "kpi":
            guard let value = fields.first, !value.isEmpty else { return nil }
            let label = fields.count > 1 ? fields[1] : ""
            return .kpi(SummaryKPI(value: value, label: label))
        case "card":
            guard let title = fields.first, !title.isEmpty else { return nil }
            let icon = fields.count > 1 ? repairedIcon(fields[1]) : defaultIcon(forTitle: title)
            let color = fields.count > 2 ? repairedColor(fields[2]) : defaultColor(forTitle: title)
            return .openCard(SummaryCardSpec(title: title, icon: icon, colorName: color, rows: []))
        case "p":
            guard let text = fields.first, !text.isEmpty else { return nil }
            return .row(.paragraph(text))
        case "li":
            guard let text = fields.first, !text.isEmpty else { return nil }
            return .row(.bullet(text))
        case "item":
            guard let title = fields.first, !title.isEmpty else { return nil }
            let description = fields.count > 1 ? nonEmpty(fields[1]) : nil
            let icon = fields.count > 2 && !fields[2].isEmpty
                ? repairedIcon(fields[2])
                : defaultIcon(forTitle: title)
            return .row(.item(title: title, description: description, icon: icon))
        case "todo":
            return todoStatement(fields: fields)
        case "quote":
            guard let text = fields.first, !text.isEmpty else { return nil }
            return .quote(text: text, author: fields.count > 1 ? nonEmpty(fields[1]) : nil)
        case "alert":
            return alertStatement(fields: fields)
        case "person":
            guard let name = fields.first, !name.isEmpty else { return nil }
            return .person(SummaryPersonChip(name: name, role: fields.count > 1 ? nonEmpty(fields[1]) : nil))
        case "progress":
            return progressStatement(fields: fields)
        case "barchart", "linechart", "piechart":
            return chartStatement(name: name, fields: fields)
        case "timeline":
            guard fields.count >= 2, !fields[1].isEmpty else {
                guard let only = fields.first, !only.isEmpty else { return nil }
                return .timelineEntry(SummaryTimelineEntry(time: "", text: only))
            }
            return .timelineEntry(SummaryTimelineEntry(time: fields[0], text: fields[1]))
        case "divider":
            return .divider
        default:
            return nil
        }
    }

    private static func todoStatement(fields: [String]) -> Statement? {
        guard !fields.isEmpty else { return nil }
        var assignee: String?
        var text: String
        var due: String?
        switch fields.count {
        case 1:
            text = fields[0]
        case 2:
            assignee = normalizedAssignee(fields[0])
            text = fields[1]
        default:
            assignee = normalizedAssignee(fields[0])
            text = fields[1]
            due = nonEmpty(fields[2])
        }
        var done = false
        if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
            done = true
            text = String(text.dropFirst(4))
        }
        guard !text.isEmpty else { return nil }
        return .row(.todo(assignee: assignee, text: text, due: due, done: done))
    }

    private static func alertStatement(fields: [String]) -> Statement? {
        guard let first = fields.first, !first.isEmpty else { return nil }
        if fields.count >= 2, let level = repairedAlertLevel(first), !fields[1].isEmpty {
            return .alert(level: level, text: fields[1])
        }
        // Single field (or unknown level): the whole payload is the text.
        let text = fields.joined(separator: " — ")
        return .alert(level: repairedAlertLevel(first) != nil && fields.count == 1 ? .info : .warning, text: text)
    }

    private static func progressStatement(fields: [String]) -> Statement? {
        guard let first = fields.first else { return nil }
        let label = fields.count > 1 ? nonEmpty(fields[1]) : nil
        if let (current, total) = parsedFraction(first) {
            return .progress(current: current, total: total, label: label)
        }
        // "60%" form
        if first.hasSuffix("%"), let value = coercedNumber(String(first.dropLast())) {
            return .progress(current: value, total: 100, label: label)
        }
        return nil
    }

    private static func chartStatement(name: String, fields: [String]) -> Statement? {
        guard let title = fields.first, !title.isEmpty else { return nil }
        var points: [SummaryChartPoint] = []
        for field in fields.dropFirst() {
            guard let separatorIndex = field.lastIndex(of: ":") else { continue }
            let label = String(field[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
            let valueText = String(field[field.index(after: separatorIndex)...])
            guard !label.isEmpty, let value = coercedNumber(valueText) else { continue }
            points.append(SummaryChartPoint(label: label, value: value))
        }
        guard points.count >= 2 else { return nil }
        let kind: SummaryChartKind
        switch name {
        case "barchart": kind = .bar
        case "linechart": kind = .line
        default: kind = .pie
        }
        return .chart(SummaryChartSpec(kind: kind, title: title, points: points))
    }

    // MARK: - Markdown slip conversion

    private static func statementFromMarkdown(_ line: String) -> Statement? {
        if line.hasPrefix("# ") {
            return .header(title: String(line.dropFirst(2)), subtitle: nil)
        }
        if line.hasPrefix("## ") || line.hasPrefix("### ") {
            let title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return nil }
            return .openCard(SummaryCardSpec(
                title: title,
                icon: defaultIcon(forTitle: title),
                colorName: defaultColor(forTitle: title),
                rows: []
            ))
        }
        if line.hasPrefix("- [ ] ") {
            return .row(.todo(assignee: nil, text: String(line.dropFirst(6)), due: nil, done: false))
        }
        if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
            return .row(.todo(assignee: nil, text: String(line.dropFirst(6)), due: nil, done: true))
        }
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return .row(.bullet(String(line.dropFirst(2))))
        }
        if line.hasPrefix("> ") {
            return .quote(text: String(line.dropFirst(2)), author: nil)
        }
        if let match = line.range(of: #"^\d+[.)]\s"#, options: .regularExpression) {
            let number = Int(line[..<match.upperBound].prefix { $0.isNumber }) ?? 1
            return .row(.numbered(number, String(line[match.upperBound...])))
        }
        if line == "---" || line == "***" {
            return .divider
        }
        // Bare prose inside a design response: keep it as a paragraph so the
        // content survives; assemble() wraps orphans into an implicit card.
        return .row(.paragraph(line))
    }

    // MARK: - Stage 3: assembly (grouping + implicit containers)

    static func assemble(_ statements: [Statement]) -> [SummaryLayoutBlock] {
        var blocks: [SummaryLayoutBlock] = []
        var openCard: SummaryCardSpec?
        var kpiBuffer: [SummaryKPI] = []
        var personBuffer: [SummaryPersonChip] = []
        var timelineBuffer: [SummaryTimelineEntry] = []
        var sawHeader = false

        func closeCard() {
            // A title-only card renders as a broken empty box — drop it.
            if let card = openCard, !card.rows.isEmpty {
                blocks.append(.card(card))
            }
            openCard = nil
        }

        func flushKPIs() {
            if !kpiBuffer.isEmpty {
                blocks.append(.kpiRow(kpiBuffer))
                kpiBuffer = []
            }
        }

        func flushPeople() {
            if !personBuffer.isEmpty {
                blocks.append(.personRow(personBuffer))
                personBuffer = []
            }
        }

        func flushTimeline() {
            if !timelineBuffer.isEmpty {
                blocks.append(.timeline(timelineBuffer))
                timelineBuffer = []
            }
        }

        func flushGroups() {
            flushKPIs()
            flushPeople()
            flushTimeline()
        }

        for statement in statements {
            switch statement {
            case .header(let title, let subtitle):
                if sawHeader {
                    // Duplicate headers degrade into cards.
                    flushGroups()
                    closeCard()
                    openCard = SummaryCardSpec(
                        title: title,
                        icon: defaultIcon(forTitle: title),
                        colorName: defaultColor(forTitle: title),
                        rows: []
                    )
                } else {
                    sawHeader = true
                    flushGroups()
                    closeCard()
                    blocks.insert(.header(title: title, subtitle: subtitle), at: 0)
                }
            case .kpi(let kpi):
                flushPeople()
                flushTimeline()
                kpiBuffer.append(kpi)
            case .openCard(let card):
                flushGroups()
                closeCard()
                openCard = card
            case .row(let row):
                flushGroups()
                if openCard == nil {
                    openCard = SummaryCardSpec(
                        title: L10n.shared.isRussian ? "Сводка" : "Summary",
                        icon: "text.alignleft",
                        colorName: "blue",
                        rows: []
                    )
                }
                openCard?.rows.append(row)
            case .quote(let text, let author):
                flushGroups()
                closeCard()
                blocks.append(.quote(text: text, author: author))
            case .alert(let level, let text):
                flushGroups()
                if openCard != nil {
                    // The model announced a section card and then listed its
                    // risks as alerts — keep them inside the card so the
                    // section doesn't render as an empty box.
                    openCard?.rows.append(.alert(level: level, text: text))
                } else {
                    blocks.append(.alert(level: level, text: text))
                }
            case .person(let person):
                flushKPIs()
                flushTimeline()
                personBuffer.append(person)
            case .progress(let current, let total, let label):
                flushGroups()
                closeCard()
                blocks.append(.progress(current: current, total: total, label: label))
            case .chart(let chart):
                flushGroups()
                closeCard()
                blocks.append(.chart(chart))
            case .timelineEntry(let entry):
                flushKPIs()
                flushPeople()
                timelineBuffer.append(entry)
            case .divider:
                flushGroups()
                closeCard()
                if case .divider = blocks.last { continue }
                blocks.append(.divider)
            }
        }
        flushGroups()
        closeCard()

        // Trailing divider is noise.
        if case .divider = blocks.last {
            blocks.removeLast()
        }
        return blocks
    }

    // MARK: - Field repair helpers

    static func repairedIcon(_ raw: String) -> String {
        let token = raw.lowercased().trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else { return "circle.fill" }
        if SummaryComponentRegistry.iconWhitelist.contains(token) { return token }
        var best: (icon: String, distance: Int)?
        for icon in SummaryComponentRegistry.iconWhitelist {
            let distance = levenshtein(token, icon, cap: 3)
            if distance <= 3, distance < (best?.distance ?? Int.max) {
                best = (icon, distance)
            }
        }
        return best?.icon ?? "circle.fill"
    }

    static func repairedColor(_ raw: String) -> String {
        let token = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if SummaryComponentRegistry.colorWhitelist.contains(token) { return token }
        var best: (color: String, distance: Int)?
        for color in SummaryComponentRegistry.colorWhitelist {
            let distance = levenshtein(token, color, cap: 2)
            if distance <= 2, distance < (best?.distance ?? Int.max) {
                best = (color, distance)
            }
        }
        return best?.color ?? "accent"
    }

    private static func repairedAlertLevel(_ raw: String) -> SummaryAlertLevel? {
        let token = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if let exact = SummaryAlertLevel(rawValue: token) { return exact }
        for level in [SummaryAlertLevel.info, .warning, .critical] {
            if levenshtein(token, level.rawValue, cap: 2) <= 2 { return level }
        }
        switch token {
        case "инфо", "информация": return .info
        case "риск", "внимание", "предупреждение": return .warning
        case "критично", "критический", "блокер": return .critical
        default: return nil
        }
    }

    /// RU/EN keyword mapping used when the model omitted icon/color or slipped
    /// into markdown headings.
    static func defaultIcon(forTitle title: String) -> String {
        let lowered = title.lowercased()
        if lowered.contains("решени") || lowered.contains("decision") { return "checkmark.seal.fill" }
        if lowered.contains("задач") || lowered.contains("action") || lowered.contains("поручен") || lowered.contains("next step") { return "checklist" }
        if lowered.contains("риск") || lowered.contains("вопрос") || lowered.contains("блокер") || lowered.contains("risk") || lowered.contains("question") || lowered.contains("blocker") { return "exclamationmark.triangle.fill" }
        if lowered.contains("участник") || lowered.contains("люди") || lowered.contains("people") || lowered.contains("attendee") { return "person.2.fill" }
        if lowered.contains("иде") || lowered.contains("idea") || lowered.contains("предложени") { return "lightbulb.fill" }
        if lowered.contains("срок") || lowered.contains("план") || lowered.contains("календар") || lowered.contains("schedule") || lowered.contains("deadline") { return "calendar" }
        if lowered.contains("итог") || lowered.contains("дайджест") || lowered.contains("summary") || lowered.contains("digest") || lowered.contains("обсу") { return "text.alignleft" }
        return "doc.text"
    }

    static func defaultColor(forTitle title: String) -> String {
        let lowered = title.lowercased()
        if lowered.contains("решени") || lowered.contains("decision") { return "purple" }
        if lowered.contains("задач") || lowered.contains("action") || lowered.contains("поручен") { return "green" }
        if lowered.contains("риск") || lowered.contains("вопрос") || lowered.contains("блокер") || lowered.contains("risk") { return "orange" }
        if lowered.contains("участник") || lowered.contains("people") { return "blue" }
        return "blue"
    }

    private static func normalizedAssignee(_ raw: String) -> String? {
        let token = raw.trimmingCharacters(in: .whitespaces)
        if token.isEmpty || token == "-" || token == "—" || token.lowercased() == "none" { return nil }
        return token
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parsedFraction(_ raw: String) -> (Double, Double)? {
        let parts = raw.split(separator: "/")
        guard parts.count == 2,
              let current = coercedNumber(String(parts[0])),
              let total = coercedNumber(String(parts[1])),
              total > 0 else { return nil }
        return (current, total)
    }

    /// "12,5" → 12.5; strips currency/percent/space noise around digits.
    static func coercedNumber(_ raw: String) -> Double? {
        var text = raw
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        text = text.filter { $0.isNumber || $0 == "." || $0 == "-" }
        guard !text.isEmpty else { return nil }
        return Double(text)
    }

    /// Capped Damerau-Levenshtein distance (adjacent transpositions cost 1 —
    /// the most common LLM typo, e.g. "tdoo" → "todo"). Bails out past `cap`.
    static func levenshtein(_ a: String, _ b: String, cap: Int) -> Int {
        if a == b { return 0 }
        let aChars = Array(a)
        let bChars = Array(b)
        if abs(aChars.count - bChars.count) > cap { return cap + 1 }
        var beforePrevious = [Int](repeating: 0, count: bChars.count + 1)
        var previous = Array(0...bChars.count)
        var current = [Int](repeating: 0, count: bChars.count + 1)
        for i in 1...aChars.count {
            current[0] = i
            var rowMin = current[0]
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                var best = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
                if i > 1, j > 1, aChars[i - 1] == bChars[j - 2], aChars[i - 2] == bChars[j - 1] {
                    best = min(best, beforePrevious[j - 2] + 1)
                }
                current[j] = best
                rowMin = min(rowMin, best)
            }
            if rowMin > cap { return cap + 1 }
            beforePrevious = previous
            previous = current
        }
        return previous[bChars.count]
    }
}
