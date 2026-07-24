import Foundation

/// One entry of the designed-summary component registry (OpenUI's
/// `defineComponent` adapted to Swift): the LLM-facing name, the allowed
/// field count and the doc line that is injected into the generated prompt.
struct SummaryComponentSpec {
    let name: String
    let minFields: Int
    /// nil = variadic (charts take an arbitrary number of data fields).
    let maxFields: Int?
    let doc: String
}

/// Registry of every visual component the designed-summary LLM may emit.
///
/// OpenUI principle: the system prompt is not hand-written per template — it
/// is generated from this registry (syntax rules + component signatures), so
/// adding a component here automatically teaches every designed template
/// about it.
enum SummaryComponentRegistry {
    /// Bump when components or their fields change; reserved for future
    /// stored-artifact migrations.
    static let version = 2

    /// Broad SF Symbols palette so the model can match icons to meaning
    /// instead of recycling the same three glyphs. All names are long-stable
    /// symbols available on macOS 14.
    static let iconWhitelist: [String] = [
        "text.alignleft", "checklist", "list.bullet", "doc.text", "folder.fill",
        "checkmark.seal.fill", "checkmark.circle.fill", "xmark.octagon.fill",
        "exclamationmark.triangle.fill", "questionmark.circle.fill", "info.circle.fill",
        "person.2.fill", "person.3.fill", "person.crop.circle.fill",
        "calendar", "clock.fill", "timer", "flag.fill", "target",
        "lightbulb.fill", "sparkles", "brain.head.profile", "star.fill",
        "heart.fill", "bolt.fill", "flame.fill", "leaf.fill",
        "shield.fill", "lock.fill", "key.fill",
        "dollarsign.circle.fill", "creditcard.fill", "cart.fill", "banknote", "percent",
        "chart.bar.fill", "chart.pie.fill", "chart.line.uptrend.xyaxis",
        "megaphone.fill", "paintbrush.fill", "hammer.fill", "wrench.and.screwdriver.fill",
        "gearshape.fill", "link", "paperclip", "tag.fill", "bell.fill",
        "envelope.fill", "phone.fill", "video.fill", "mic.fill",
        "bubble.left.and.bubble.right.fill", "hand.thumbsup.fill", "hand.raised.fill",
        "globe", "map.fill", "house.fill", "building.2.fill", "briefcase.fill",
        "graduationcap.fill", "book.fill", "tray.full.fill",
        "cpu", "desktopcomputer", "iphone", "network", "cloud.fill",
        "magnifyingglass", "arrow.up.right", "arrow.triangle.branch",
        "puzzlepiece.fill", "plus.circle.fill", "signature", "pencil"
    ]

    static let colorWhitelist: [String] = ["blue", "green", "purple", "orange", "red", "gray"]

    static let components: [SummaryComponentSpec] = [
        SummaryComponentSpec(
            name: "header",
            minFields: 1,
            maxFields: 2,
            doc: "header | заголовок встречи | подзаголовок (тема/длительность) — ровно один, первой строкой"
        ),
        SummaryComponentSpec(
            name: "kpi",
            minFields: 2,
            maxFields: 2,
            doc: "kpi | значение | подпись — ключевая метрика; 2–4 подряд образуют ряд плиток"
        ),
        SummaryComponentSpec(
            name: "card",
            minFields: 1,
            maxFields: 3,
            doc: "card | заголовок | иконка | цвет — открывает карточку-раздел; следующие строки p/li/todo попадают внутрь неё"
        ),
        SummaryComponentSpec(
            name: "p",
            minFields: 1,
            maxFields: 1,
            doc: "p | абзац текста"
        ),
        SummaryComponentSpec(
            name: "li",
            minFields: 1,
            maxFields: 1,
            doc: "li | пункт списка — только для коротких перечислений из 3+ однотипных пунктов"
        ),
        SummaryComponentSpec(
            name: "item",
            minFields: 1,
            maxFields: 3,
            doc: "item | заголовок пункта | пояснение | иконка — содержательный пункт с иконкой и раскрытием; ПРЕДПОЧИТАЙ его обычному li для важных мыслей"
        ),
        SummaryComponentSpec(
            name: "todo",
            minFields: 1,
            maxFields: 3,
            doc: "todo | исполнитель или - | задача | срок или пусто — задача с чекбоксом"
        ),
        SummaryComponentSpec(
            name: "quote",
            minFields: 1,
            maxFields: 2,
            doc: "quote | дословная цитата | автор — важная фраза из встречи"
        ),
        SummaryComponentSpec(
            name: "alert",
            minFields: 1,
            maxFields: 2,
            doc: "alert | info или warning или critical | текст — риск, блокер или важное предупреждение"
        ),
        SummaryComponentSpec(
            name: "person",
            minFields: 1,
            maxFields: 2,
            doc: "person | имя | роль (коротко, до 5 слов) — участник; несколько подряд образуют ряд"
        ),
        SummaryComponentSpec(
            name: "progress",
            minFields: 1,
            maxFields: 2,
            doc: "progress | 3/5 | подпись — прогресс вида «текущее/всего»"
        ),
        SummaryComponentSpec(
            name: "barchart",
            minFields: 2,
            maxFields: nil,
            doc: "barchart | заголовок | метка: число | метка: число … — столбчатый график (минимум 2 точки)"
        ),
        SummaryComponentSpec(
            name: "linechart",
            minFields: 2,
            maxFields: nil,
            doc: "linechart | заголовок | метка: число | метка: число … — линейный график динамики"
        ),
        SummaryComponentSpec(
            name: "piechart",
            minFields: 2,
            maxFields: nil,
            doc: "piechart | заголовок | метка: число | метка: число … — круговая диаграмма долей"
        ),
        SummaryComponentSpec(
            name: "timeline",
            minFields: 2,
            maxFields: 2,
            doc: "timeline | время или этап | событие — веха; несколько подряд образуют таймлайн"
        ),
        SummaryComponentSpec(
            name: "divider",
            minFields: 0,
            maxFields: 0,
            doc: "divider — разделитель между смысловыми зонами"
        )
    ]

    static let componentsByName: [String: SummaryComponentSpec] = {
        var map: [String: SummaryComponentSpec] = [:]
        for component in components {
            map[component.name] = component
        }
        return map
    }()

    static var componentNames: [String] { components.map(\.name) }

    /// The full designed-mode system prompt: syntax rules + component
    /// signatures generated from the registry + anti-garbage rules + the
    /// template's own prompt embedded as the content assignment.
    static func designedInstructions(templatePrompt: String) -> String {
        let componentDocs = components.map { "- \($0.doc)" }.joined(separator: "\n")
        let icons = iconWhitelist.joined(separator: ", ")
        let colors = colorWhitelist.joined(separator: ", ")
        let trimmedTemplate = templatePrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        return """
        Ты — дизайнер сводок встреч. По транскрипту собери сводку в виде компактной разметки карточек и блоков.

        ФОРМАТ ОТВЕТА — строго построчная разметка:
        - Каждая строка — один блок: имя компонента, затем поля через символ «|».
        - Отвечай ТОЛЬКО строками разметки. Без markdown, без пояснений, без вступлений и заключений.
        - Первой строкой ОБЯЗАТЕЛЬНО идёт header.
        - Пиши на языке, на котором говорили на встрече.

        ДОСТУПНЫЕ КОМПОНЕНТЫ:
        \(componentDocs)

        Иконки для card (только из списка): \(icons)
        Цвета (только из списка): \(colors)

        ПРАВИЛА КАЧЕСТВА:
        - Ничего не выдумывай: используй только факты, прозвучавшие во встрече.
        - Для kpi, progress и графиков бери ТОЛЬКО числа, реально названные во встрече. Если чисел нет — не используй графики и kpi.
        - Подбирай состав блоков под содержание: решения → card + item, задачи → card + todo, риски → alert, участники → person, метрики → kpi или barchart, важные фразы → quote.
        - БОЛЬШЕ ДИЗАЙНА, МЕНЬШЕ СПЛОШНОГО ТЕКСТА: для каждой значимой мысли используй item с точной иконкой по смыслу и коротким пояснением. Голый li — только для перечислений из 3+ коротких однотипных пунктов. Сплошные абзацы p — в крайнем случае.
        - БАЛАНС КАРТОЧЕК: 2–5 строк содержимого на карточку. Если материала больше — раздели на несколько карточек по подтемам, а не раздувай одну. Пиши кратко: пункт — одна-две строки, без «воды».
        - Строки p/li/item/todo всегда идут после card, к которой относятся.

        СОДЕРЖАТЕЛЬНОЕ ЗАДАНИЕ ШАБЛОНА — какие разделы и что выделять; ориентируйся на него, но результат выдай разметкой выше, а не текстом:
        «\(trimmedTemplate)»
        """
    }
}
