import SwiftUI
import Charts

/// Renders a designed summary (parsed + repaired layout blocks) in the app
/// theme: header, KPI tiles, Insights-style cards, quotes, alerts, people
/// chips, progress bars, Swift Charts and timelines.
///
/// Drop-in replacement for `MeetingNotesView` — owns its own ScrollView.
struct SummaryLayoutView: View {
    let blocks: [SummaryLayoutBlock]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                ForEach(Array(renderGroups.enumerated()), id: \.offset) { _, group in
                    renderGroup(group)
                }
            }
            .frame(maxWidth: 880, alignment: .leading)
            .padding(.horizontal, MuesliTheme.spacing24)
            .padding(.vertical, MuesliTheme.spacing16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Grouping (consecutive cards form an adaptive grid)

    private enum RenderGroup {
        case single(SummaryLayoutBlock)
        case cardGrid([SummaryCardSpec])
    }

    private var renderGroups: [RenderGroup] {
        var groups: [RenderGroup] = []
        var cardBuffer: [SummaryCardSpec] = []

        func flushCards() {
            guard !cardBuffer.isEmpty else { return }
            if cardBuffer.count == 1 {
                groups.append(.single(.card(cardBuffer[0])))
            } else {
                groups.append(.cardGrid(cardBuffer))
            }
            cardBuffer = []
        }

        for block in blocks {
            if case .card(let card) = block {
                cardBuffer.append(card)
            } else {
                flushCards()
                groups.append(.single(block))
            }
        }
        flushCards()
        return groups
    }

    @ViewBuilder
    private func renderGroup(_ group: RenderGroup) -> some View {
        switch group {
        case .single(let block):
            renderBlock(block)
        case .cardGrid(let cards):
            // Rows of two with equalized heights: each cell stretches to the
            // tallest card in its row (fixedSize caps the row at the ideal
            // height, so nothing balloons past its content).
            VStack(spacing: MuesliTheme.spacing12) {
                ForEach(Array(stride(from: 0, to: cards.count, by: 2)), id: \.self) { start in
                    HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
                        cardView(cards[start])
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if start + 1 < cards.count {
                            cardView(cards[start + 1])
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Blocks

    @ViewBuilder
    private func renderBlock(_ block: SummaryLayoutBlock) -> some View {
        switch block {
        case .header(let title, let subtitle):
            VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                Text(title)
                    .font(MuesliTheme.title2())
                    .foregroundStyle(MuesliTheme.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(MuesliTheme.callout())
                        .foregroundStyle(MuesliTheme.textSecondary)
                }
            }
            .padding(.bottom, MuesliTheme.spacing4)
        case .kpiRow(let kpis):
            kpiRowView(kpis)
        case .card(let card):
            cardView(card)
        case .quote(let text, let author):
            quoteView(text: text, author: author)
        case .alert(let level, let text):
            alertView(level: level, text: text)
        case .personRow(let people):
            personRowView(people)
        case .progress(let current, let total, let label):
            progressView(current: current, total: total, label: label)
        case .chart(let chart):
            chartView(chart)
        case .timeline(let entries):
            timelineView(entries)
        case .divider:
            Rectangle()
                .fill(MuesliTheme.surfaceBorder)
                .frame(height: 1)
                .padding(.vertical, MuesliTheme.spacing4)
        }
    }

    // MARK: - KPI tiles

    private func kpiRowView(_ kpis: [SummaryKPI]) -> some View {
        HStack(spacing: MuesliTheme.spacing12) {
            ForEach(Array(kpis.prefix(4).enumerated()), id: \.offset) { index, kpi in
                VStack(alignment: .leading, spacing: 2) {
                    Text(kpi.value)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(SummaryPalette.seriesColor(at: index))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(kpi.label)
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(MuesliTheme.spacing12)
                .background(RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge).fill(MuesliTheme.backgroundBase))
                .overlay(RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge).strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Card (Insights style)

    private func cardView(_ card: SummaryCardSpec) -> some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack(spacing: MuesliTheme.spacing8) {
                Image(systemName: card.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 8).fill(SummaryPalette.color(named: card.colorName)))
                Text(card.title)
                    .font(MuesliTheme.headline())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                ForEach(Array(card.rows.enumerated()), id: \.offset) { _, row in
                    cardRowView(row)
                }
            }
        }
        .padding(MuesliTheme.spacing16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).fill(MuesliTheme.backgroundBase))
        .overlay(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
    }

    @ViewBuilder
    private func cardRowView(_ row: SummaryCardRow) -> some View {
        switch row {
        case .paragraph(let text):
            Text(text)
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textSecondary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: MuesliTheme.spacing8) {
                Circle()
                    .fill(MuesliTheme.textTertiary)
                    .frame(width: 4, height: 4)
                    .offset(y: -2)
                    .frame(width: 14, alignment: .center)
                Text(text)
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .numbered(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: MuesliTheme.spacing8) {
                Text("\(number).")
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .frame(width: 22, alignment: .trailing)
                Text(text)
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .item(let title, let description, let icon):
            // Nested outlined sub-block: plain gray icon (no background tile),
            // title + description inside a hairline-bordered container for a
            // layered, multi-level look.
            HStack(alignment: .top, spacing: MuesliTheme.spacing8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .frame(width: 18, alignment: .center)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textPrimary)
                        .lineSpacing(2)
                    if let description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 12))
                            .foregroundStyle(MuesliTheme.textSecondary)
                            .lineSpacing(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(MuesliTheme.spacing12)
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        case .alert(let level, let text):
            let color = SummaryPalette.alertColor(level)
            HStack(alignment: .firstTextBaseline, spacing: MuesliTheme.spacing8) {
                Image(systemName: level == .critical ? "exclamationmark.octagon.fill" : (level == .info ? "info.circle.fill" : "exclamationmark.triangle.fill"))
                    .font(.system(size: 11))
                    .foregroundStyle(color)
                Text(text)
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(MuesliTheme.spacing8)
            .background(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium).fill(color.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium).strokeBorder(color.opacity(0.30), lineWidth: 1))
        case .todo(let assignee, let text, let due, let done):
            HStack(alignment: .firstTextBaseline, spacing: MuesliTheme.spacing8) {
                Image(systemName: done ? "checkmark.square" : "square")
                    .font(.system(size: 12))
                    .foregroundStyle(done ? MuesliTheme.success : MuesliTheme.textTertiary)
                    .frame(width: 14, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text)
                        .font(MuesliTheme.body())
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if assignee != nil || due != nil {
                        HStack(spacing: MuesliTheme.spacing8) {
                            if let assignee {
                                Text(assignee)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(MuesliTheme.accent)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(MuesliTheme.accentSubtle))
                            }
                            if let due {
                                HStack(spacing: 3) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 9))
                                    Text(due)
                                        .font(.system(size: 11))
                                }
                                .foregroundStyle(MuesliTheme.textTertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Quote

    private func quoteView(text: String, author: String?) -> some View {
        // Big accent quote glyph on the side + the author as an avatar chip —
        // livelier than the old left rule.
        HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
            Image(systemName: "quote.opening")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(MuesliTheme.accent)
                .frame(width: 36, height: 36)
                .background(Circle().fill(MuesliTheme.accentSubtle))

            VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                Text(text)
                    .font(.system(size: 14, weight: .regular).italic())
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .lineSpacing(3)
                if let author, !author.isEmpty {
                    HStack(spacing: 6) {
                        Text(initials(for: author))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(SummaryPalette.seriesColor(at: stableColorIndex(for: author))))
                        Text(author)
                            .font(MuesliTheme.captionMedium())
                            .foregroundStyle(MuesliTheme.textSecondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(MuesliTheme.spacing16)
        .background(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).fill(MuesliTheme.backgroundBase))
        .overlay(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Alert

    private func alertView(level: SummaryAlertLevel, text: String) -> some View {
        let color = SummaryPalette.alertColor(level)
        let icon: String
        switch level {
        case .info: icon = "info.circle.fill"
        case .warning: icon = "exclamationmark.triangle.fill"
        case .critical: icon = "exclamationmark.octagon.fill"
        }
        return HStack(alignment: .firstTextBaseline, spacing: MuesliTheme.spacing8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
            Text(text)
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textPrimary)
                .lineSpacing(3)
            Spacer(minLength: 0)
        }
        .padding(MuesliTheme.spacing12)
        .background(RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge).fill(color.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge).strokeBorder(color.opacity(0.35), lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - People chips

    private func personRowView(_ people: [SummaryPersonChip]) -> some View {
        // Header-style chips in a single row: equal flexible widths, long role
        // text wraps downward instead of inflating the chip. Uniform padding —
        // the avatar sits as far from the left edge as from top and bottom.
        HStack(alignment: .top, spacing: MuesliTheme.spacing8) {
            ForEach(Array(people.enumerated()), id: \.offset) { index, person in
                HStack(alignment: .center, spacing: MuesliTheme.spacing8) {
                    Text(initials(for: person.name))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(SummaryPalette.seriesColor(at: index)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(person.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MuesliTheme.textPrimary)
                        if let role = person.role, !role.isEmpty {
                            Text(role)
                                .font(.system(size: 11))
                                .foregroundStyle(MuesliTheme.textTertiary)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(MuesliTheme.spacing8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).fill(MuesliTheme.backgroundBase))
                .overlay(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Deterministic per-name color (String.hashValue is randomized per run).
    private func stableColorIndex(for name: String) -> Int {
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return sum % SummaryPalette.seriesHexes.count
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }

    // MARK: - Progress

    private func progressView(current: Double, total: Double, label: String?) -> some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack {
                if let label, !label.isEmpty {
                    Text(label)
                        .font(MuesliTheme.captionMedium())
                        .foregroundStyle(MuesliTheme.textSecondary)
                }
                Spacer()
                Text(progressCaption(current: current, total: total))
                    .font(MuesliTheme.captionMedium())
                    .foregroundStyle(MuesliTheme.textPrimary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(MuesliTheme.surfacePrimary)
                    Capsule()
                        .fill(MuesliTheme.accent)
                        .frame(width: max(0, min(1, current / max(total, 1))) * proxy.size.width)
                }
            }
            .frame(height: 8)
        }
        .padding(MuesliTheme.spacing16)
        .background(RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge).fill(MuesliTheme.backgroundBase))
        .overlay(RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge).strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
    }

    private func progressCaption(current: Double, total: Double) -> String {
        func short(_ value: Double) -> String {
            value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
        }
        return "\(short(current))/\(short(total))"
    }

    // MARK: - Charts (Swift Charts, Overview-dashboard style)

    private func chartView(_ spec: SummaryChartSpec) -> some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            Text(spec.title)
                .font(MuesliTheme.headline())
                .foregroundStyle(MuesliTheme.textPrimary)

            switch spec.kind {
            case .bar:
                Chart(Array(spec.points.enumerated()), id: \.offset) { _, point in
                    BarMark(
                        x: .value("Label", point.label),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(MuesliTheme.accent)
                    .cornerRadius(4)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 150)
            case .line:
                Chart(Array(spec.points.enumerated()), id: \.offset) { index, point in
                    LineMark(
                        x: .value("Label", point.label),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(MuesliTheme.accent)
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("Label", point.label),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(MuesliTheme.accent)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 150)
            case .pie:
                HStack(spacing: MuesliTheme.spacing16) {
                    Chart(Array(spec.points.enumerated()), id: \.offset) { index, point in
                        SectorMark(
                            angle: .value("Value", point.value),
                            innerRadius: .ratio(0.6),
                            angularInset: 1.5
                        )
                        .foregroundStyle(SummaryPalette.seriesColor(at: index))
                        .cornerRadius(3)
                    }
                    .frame(height: 150)

                    VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                        ForEach(Array(spec.points.enumerated()), id: \.offset) { index, point in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(SummaryPalette.seriesColor(at: index))
                                    .frame(width: 8, height: 8)
                                Text(point.label)
                                    .font(MuesliTheme.caption())
                                    .foregroundStyle(MuesliTheme.textSecondary)
                                    .lineLimit(1)
                                Text(chartValueText(point.value))
                                    .font(MuesliTheme.captionMedium())
                                    .foregroundStyle(MuesliTheme.textPrimary)
                            }
                        }
                    }
                }
            }
        }
        .padding(MuesliTheme.spacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).fill(MuesliTheme.backgroundBase))
        .overlay(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
    }

    private func chartValueText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    // MARK: - Timeline

    private func timelineView(_ entries: [SummaryTimelineEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(MuesliTheme.accent)
                            .frame(width: 8, height: 8)
                            .padding(.top, 5)
                        if index < entries.count - 1 {
                            Rectangle()
                                .fill(MuesliTheme.surfaceBorder)
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        if !entry.time.isEmpty {
                            Text(entry.time)
                                .font(MuesliTheme.captionMedium())
                                .foregroundStyle(MuesliTheme.textTertiary)
                        }
                        Text(entry.text)
                            .font(MuesliTheme.body())
                            .foregroundStyle(MuesliTheme.textSecondary)
                            .lineSpacing(3)
                            .padding(.bottom, index < entries.count - 1 ? MuesliTheme.spacing12 : 0)
                    }
                    Spacer(minLength: 0)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(MuesliTheme.spacing16)
        .background(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).fill(MuesliTheme.backgroundBase))
        .overlay(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
    }
}

