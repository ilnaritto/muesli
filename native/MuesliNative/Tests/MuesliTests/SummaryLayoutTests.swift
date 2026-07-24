import Foundation
import Testing
@testable import MuesliNativeApp

// MARK: - Detection

@Suite("SummaryLayout detection")
struct SummaryLayoutDetectionTests {
    @Test func headerSentinelDetects() {
        let markup = """
        header | Синк по продукту | 45 минут
        card | Решения | checkmark.seal.fill | purple
        li | Релиз 15 июля
        """
        #expect(SummaryLayout.isDesignedMarkup(markup))
    }

    @Test func majorityComponentLinesDetect() {
        let markup = """
        card | Решения | checkmark.seal.fill | purple
        li | Релиз 15 июля
        li | Бюджет утверждён
        """
        #expect(SummaryLayout.isDesignedMarkup(markup))
    }

    @Test func plainMarkdownIsNotDetected() {
        let markdown = """
        # Синк по продукту

        ## Решения
        - Релиз 15 июля
        - Бюджет утверждён
        """
        #expect(!SummaryLayout.isDesignedMarkup(markdown))
    }

    @Test func failureNotesAreNotDetected() {
        let failure = MeetingSummaryClient.summaryFailureNotes(
            transcript: "тестовый транскрипт",
            meetingTitle: "Встреча",
            error: NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        )
        #expect(!SummaryLayout.isDesignedMarkup(failure))
    }

    @Test func emptyStringIsNotDetected() {
        #expect(!SummaryLayout.isDesignedMarkup(""))
    }
}

// MARK: - Markup → markdown conversion

@Suite("SummaryLayout markdown conversion")
struct SummaryLayoutMarkdownTests {
    @Test func convertsFullDocument() {
        let markup = """
        header | Синк по продукту | 45 минут
        kpi | 3 | Решения
        kpi | 5 | Задачи
        card | Решения | checkmark.seal.fill | purple
        li | Релиз переносится на 15 июля
        card | Задачи | checklist | green
        todo | Илья | Подготовить лендинг | до пятницы
        quote | Лучше сдвинуть срок | Андрей
        alert | warning | Дизайнер в отпуске
        """
        let markdown = SummaryLayout.markdownFromMarkup(markup)
        #expect(markdown.contains("# Синк по продукту"))
        #expect(markdown.contains("## Решения"))
        #expect(markdown.contains("- Релиз переносится на 15 июля"))
        #expect(markdown.contains("- [ ] Илья: Подготовить лендинг — до пятницы"))
        #expect(markdown.contains("> Лучше сдвинуть срок — Андрей"))
        #expect(!markdown.contains("|"))
    }

    @Test func plainTextPassesThroughMarkdown() {
        let markdown = "## Обычные заметки\n- пункт"
        #expect(SummaryLayout.plainText(markdown) == markdown)
    }

    @Test func plainTextConvertsMarkup() {
        let markup = """
        header | Встреча
        card | Итоги | text.alignleft | blue
        p | Всё обсудили
        """
        let plain = SummaryLayout.plainText(markup)
        #expect(plain.contains("# Встреча"))
        #expect(plain.contains("## Итоги"))
    }
}

// MARK: - Repair

@Suite("SummaryLayoutRepair")
struct SummaryLayoutRepairTests {
    @Test func parsesCleanMarkup() throws {
        let markup = """
        header | Синк | 45 минут
        kpi | 3 | Решения
        kpi | 5 | Задачи
        card | Решения | checkmark.seal.fill | purple
        li | Релиз 15 июля
        """
        let blocks = try #require(SummaryLayoutRepair.repairAndParse(markup))
        guard case .header(let title, let subtitle) = blocks[0] else {
            Issue.record("first block is not header")
            return
        }
        #expect(title == "Синк")
        #expect(subtitle == "45 минут")
        #expect(blocks.contains { block in
            if case .kpiRow(let kpis) = block { return kpis.count == 2 }
            return false
        })
    }

    @Test func fuzzyFixesComponentNames() throws {
        let markup = """
        header | Встреча
        crd | Решения | checkmark.seal.fill | purple
        li | Пункт первый
        tdoo | Илья | Сделать лендинг | завтра
        """
        let blocks = try #require(SummaryLayoutRepair.repairAndParse(markup))
        let card = blocks.compactMap { block -> SummaryCardSpec? in
            if case .card(let card) = block { return card }
            return nil
        }.first
        #expect(card?.title == "Решения")
        #expect(card?.rows.count == 2)
        if case .todo(let assignee, _, let due, _) = card?.rows.last {
            #expect(assignee == "Илья")
            #expect(due == "завтра")
        } else {
            Issue.record("todo row was not repaired")
        }
    }

    @Test func convertsMarkdownSlips() throws {
        let markup = """
        header | Встреча
        ## Решения
        - Релиз 15 июля
        - [ ] Проверить бюджет
        """
        let blocks = try #require(SummaryLayoutRepair.repairAndParse(markup))
        let card = blocks.compactMap { block -> SummaryCardSpec? in
            if case .card(let card) = block { return card }
            return nil
        }.first
        #expect(card?.title == "Решения")
        #expect(card?.icon == "checkmark.seal.fill")
        #expect(card?.rows.count == 2)
    }

    @Test func pipesInsideTextSurviveViaLastField() throws {
        let markup = """
        header | Встреча
        card | Цитаты | text.alignleft | blue
        p | Он сказал: важно | срочно | и точно
        """
        let blocks = try #require(SummaryLayoutRepair.repairAndParse(markup))
        let card = blocks.compactMap { block -> SummaryCardSpec? in
            if case .card(let card) = block { return card }
            return nil
        }.first
        if case .paragraph(let text) = card?.rows.first {
            #expect(text.contains("срочно"))
            #expect(text.contains("точно"))
        } else {
            Issue.record("paragraph row missing")
        }
    }

    @Test func stripsFencesAndChatter() throws {
        let markup = """
        Вот разметка вашей встречи:
        ```
        header | Встреча | Итоги
        card | Дайджест | text.alignleft | blue
        p | Обсудили запуск
        ```
        [end of text]
        """
        let blocks = try #require(SummaryLayoutRepair.repairAndParse(markup))
        guard case .header = blocks[0] else {
            Issue.record("header not first after preclean")
            return
        }
    }

    @Test func unknownIconAndColorFallBack() throws {
        let markup = """
        header | Встреча
        card | Раздел | nonexistent.icon.name | chartreuse
        p | Текст
        """
        let blocks = try #require(SummaryLayoutRepair.repairAndParse(markup))
        let card = blocks.compactMap { block -> SummaryCardSpec? in
            if case .card(let card) = block { return card }
            return nil
        }.first
        #expect(card?.icon == "circle.fill")
        #expect(card?.colorName == "accent")
    }

    @Test func chartNumbersAreCoerced() throws {
        let markup = """
        header | Метрики
        barchart | Выручка | Январь: 12,5 | Февраль: 30 | Март: не число
        """
        let blocks = try #require(SummaryLayoutRepair.repairAndParse(markup))
        let chart = blocks.compactMap { block -> SummaryChartSpec? in
            if case .chart(let chart) = block { return chart }
            return nil
        }.first
        #expect(chart?.points.count == 2)
        #expect(chart?.points.first?.value == 12.5)
    }

    @Test func singlePointChartIsDropped() {
        let markup = """
        header | Метрики
        piechart | Доли | Один: 100
        """
        // Header alone is 1 meaningful block → gate fails → nil.
        #expect(SummaryLayoutRepair.repairAndParse(markup) == nil)
    }

    @Test func orphanRowsWrapIntoImplicitCard() throws {
        let markup = """
        header | Встреча
        li | Пункт без карточки
        li | Второй пункт
        """
        let blocks = try #require(SummaryLayoutRepair.repairAndParse(markup))
        #expect(blocks.contains { block in
            if case .card(let card) = block { return card.rows.count == 2 }
            return false
        })
    }

    @Test func garbageFailsQualityGate() {
        #expect(SummaryLayoutRepair.repairAndParse("случайный текст без структуры") == nil)
        #expect(SummaryLayoutRepair.repairAndParse("") == nil)
    }

    @Test func alertsNestInsideOpenCard() throws {
        // The screenshot bug: "Риски" card rendered empty with alerts spilled
        // outside. Alerts after an open card must nest into it as rows.
        let markup = """
        header | Встреча
        card | Риски и открытые вопросы | exclamationmark.triangle.fill | orange
        alert | warning | Виджет ломается после зачеркивания
        alert | warning | Ноль в числовых полях требует проверки
        card | Задачи | checklist | green
        todo | - | Проверить виджет |
        """
        let blocks = try #require(SummaryLayoutRepair.repairAndParse(markup))
        let risksCard = blocks.compactMap { block -> SummaryCardSpec? in
            if case .card(let card) = block, card.title.contains("Риски") { return card }
            return nil
        }.first
        #expect(risksCard?.rows.count == 2)
        if case .alert(let level, _) = risksCard?.rows.first {
            #expect(level == .warning)
        } else {
            Issue.record("alert row missing inside card")
        }
        // No standalone alert blocks leaked out of the card.
        #expect(!blocks.contains { block in
            if case .alert = block { return true }
            return false
        })
    }

    @Test func itemRowsParseWithIconRepairAndDefaults() throws {
        let markup = """
        header | Встреча
        card | Обсуждение | text.alignleft | blue
        item | Тарифы | Сделать акцент на базовом тарифе | creditcard.fill
        item | Решение по виджету | Починить ввод после зачеркивания
        """
        let blocks = try #require(SummaryLayoutRepair.repairAndParse(markup))
        let card = blocks.compactMap { block -> SummaryCardSpec? in
            if case .card(let card) = block { return card }
            return nil
        }.first
        #expect(card?.rows.count == 2)
        if case .item(let title, let description, let icon) = card?.rows.first {
            #expect(title == "Тарифы")
            #expect(description == "Сделать акцент на базовом тарифе")
            #expect(icon == "creditcard.fill")
        } else {
            Issue.record("first item row missing")
        }
        if case .item(_, _, let icon) = card?.rows.last {
            // No icon supplied → keyword default (решени → checkmark.seal.fill).
            #expect(icon == "checkmark.seal.fill")
        } else {
            Issue.record("second item row missing")
        }
    }

    @Test func titleOnlyCardIsDropped() throws {
        let markup = """
        header | Встреча
        card | Пустой раздел | doc.text | gray
        card | Задачи | checklist | green
        todo | - | Сделать дело |
        """
        let blocks = try #require(SummaryLayoutRepair.repairAndParse(markup))
        #expect(!blocks.contains { block in
            if case .card(let card) = block { return card.title == "Пустой раздел" }
            return false
        })
    }

    @Test func consecutivePeopleGroup() throws {
        let markup = """
        header | Встреча
        person | Илья | Продакт
        person | Мария | Дизайн
        person | Андрей
        """
        let blocks = try #require(SummaryLayoutRepair.repairAndParse(markup))
        let people = blocks.compactMap { block -> [SummaryPersonChip]? in
            if case .personRow(let people) = block { return people }
            return nil
        }.first
        #expect(people?.count == 3)
        #expect(people?.last?.role == nil)
    }

    @Test func progressParsesFractionAndPercent() throws {
        let markup = """
        header | Встреча
        progress | 3/5 | Задачи закрыты
        progress | 60% | Готовность
        """
        let blocks = try #require(SummaryLayoutRepair.repairAndParse(markup))
        let progresses = blocks.compactMap { block -> (Double, Double)? in
            if case .progress(let current, let total, _) = block { return (current, total) }
            return nil
        }
        #expect(progresses.count == 2)
        #expect(progresses[0] == (3, 5))
        #expect(progresses[1] == (60, 100))
    }
}

// MARK: - Registry

@Suite("SummaryComponentRegistry")
struct SummaryComponentRegistryTests {
    @Test func promptContainsEveryComponent() {
        let prompt = SummaryComponentRegistry.designedInstructions(templatePrompt: "Тестовый шаблон")
        for component in SummaryComponentRegistry.components {
            #expect(prompt.contains(component.name), "prompt is missing \(component.name)")
        }
        #expect(prompt.contains("Тестовый шаблон"))
    }

    @Test func promptListsWhitelists() {
        let prompt = SummaryComponentRegistry.designedInstructions(templatePrompt: "x")
        for icon in SummaryComponentRegistry.iconWhitelist {
            #expect(prompt.contains(icon))
        }
        for color in SummaryComponentRegistry.colorWhitelist {
            #expect(prompt.contains(color))
        }
    }

    @Test func designedInstructionsUsedForDesignedTemplates() {
        let snapshot = MeetingTemplateSnapshot(
            id: "auto",
            name: "Auto",
            kind: .builtin,
            prompt: "Сделай краткую сводку"
        )
        let designed = MeetingSummaryClient.summaryInstructions(for: snapshot, designed: true)
        #expect(designed.contains("header"))
        #expect(designed.contains("Сделай краткую сводку"))
        let normal = MeetingSummaryClient.summaryInstructions(for: snapshot, designed: false)
        #expect(!normal.contains("ДОСТУПНЫЕ КОМПОНЕНТЫ"))
    }
}

// MARK: - Manual notes retention in designed markup

@Suite("Designed manual notes retention")
struct DesignedManualNotesTests {
    @Test func manualNotesAppendAsCard() {
        let markup = """
        header | Встреча
        card | Итоги | text.alignleft | blue
        p | Обсудили запуск
        """
        let result = MeetingSummaryClient.notesByRetainingManualNotes(
            generatedNotes: markup,
            manualNotes: "- проверить договор"
        )
        #expect(result.contains("card | "))
        #expect(result.contains("li | проверить договор"))
        #expect(!result.contains("### Written notes"))
    }
}
