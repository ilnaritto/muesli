import Foundation
import MuesliCore

struct CustomMeetingTemplate: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var prompt: String
    var icon: String
    /// MeetingOutputLanguage code; nil = system (app UI language).
    var outputLanguage: String?

    init(
        id: String = UUID().uuidString,
        name: String,
        prompt: String,
        icon: String = MeetingTemplates.customIconFallback,
        outputLanguage: String? = nil
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.icon = MeetingTemplates.normalizedCustomIcon(named: icon)
        self.outputLanguage = outputLanguage
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case prompt
        case icon
        case outputLanguage = "output_language"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decode(String.self, forKey: .name)
        prompt = try c.decode(String.self, forKey: .prompt)
        icon = MeetingTemplates.normalizedCustomIcon(
            named: try c.decodeIfPresent(String.self, forKey: .icon)
        )
        outputLanguage = try c.decodeIfPresent(String.self, forKey: .outputLanguage)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(prompt, forKey: .prompt)
        try c.encode(MeetingTemplates.normalizedCustomIcon(named: icon), forKey: .icon)
        try c.encodeIfPresent(outputLanguage, forKey: .outputLanguage)
    }
}

struct MeetingTemplateSnapshot: Equatable, Sendable {
    let id: String
    let name: String
    let kind: MeetingTemplateKind
    let prompt: String
    /// MeetingOutputLanguage code; nil = system (app UI language). Resolved
    /// live from the current template config, not persisted per meeting.
    var outputLanguage: String? = nil
}

struct MeetingTemplateDefinition: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let category: String?
    let icon: String
    let kind: MeetingTemplateKind
    let promptBody: String
    var outputLanguage: String? = nil

    var snapshot: MeetingTemplateSnapshot {
        MeetingTemplateSnapshot(
            id: id,
            name: title,
            kind: kind,
            prompt: promptBody,
            outputLanguage: outputLanguage
        )
    }
}

/// Output language options for meeting summaries. The instruction is
/// appended to the summary prompt in English; nil/system resolves to the
/// app UI language at generation time.
enum MeetingOutputLanguage {
    static let systemCode = "system"

    /// (code, English name for the prompt, display name for pickers)
    static let options: [(code: String, promptName: String, displayName: String)] = [
        ("en", "English", "English"),
        ("ru", "Russian", "Русский"),
        ("es", "Spanish", "Español"),
        ("de", "German", "Deutsch"),
        ("fr", "French", "Français"),
        ("it", "Italian", "Italiano"),
        ("pt", "Portuguese", "Português"),
        ("uk", "Ukrainian", "Українська"),
        ("tr", "Turkish", "Türkçe"),
        ("zh", "Chinese", "中文"),
        ("ja", "Japanese", "日本語"),
        ("ko", "Korean", "한국어"),
    ]

    /// English language name used in the prompt instruction.
    /// nil or "system" → the current app UI language.
    static func promptName(for code: String?) -> String {
        if let code, code != systemCode,
           let option = options.first(where: { $0.code == code }) {
            return option.promptName
        }
        return L10n.shared.isRussian ? "Russian" : "English"
    }

    /// Picker label for a stored code (nil = system).
    static func displayName(for code: String?) -> String {
        if let code, code != systemCode,
           let option = options.first(where: { $0.code == code }) {
            return option.displayName
        }
        let systemLanguage = L10n.shared.isRussian ? "Русский" : "English"
        return tr("System (\(systemLanguage))", "Системный (\(systemLanguage))")
    }
}

enum MeetingTemplates {
    static let autoID = "auto"
    static let customIconFallback = "square.and.pencil"

    struct CustomIconOption: Identifiable, Equatable, Sendable {
        let symbolName: String
        let label: String

        var id: String { symbolName }
    }

    static let auto = MeetingTemplateDefinition(
        id: autoID,
        title: "Auto",
        category: nil,
        icon: "sparkles",
        kind: .auto,
        promptBody: """
        Use this structure exactly:

        ## Meeting Summary
        A 2-3 sentence overview of what was discussed.

        ## Key Discussion Points
        - Bullet points of the main topics discussed

        ## Decisions Made
        - Bullet points of any decisions reached

        ## Action Items
        - [ ] Bullet points of tasks assigned or agreed upon, with owners if mentioned

        ## Notable Quotes
        - Any important or notable statements, if applicable
        """
    )

    static let builtIns: [MeetingTemplateDefinition] = [
        MeetingTemplateDefinition(
            id: "one-to-one",
            title: "1 to 1",
            category: "Team",
            icon: "person.2.fill",
            kind: .builtin,
            promptBody: """
            Use this structure exactly:

            ## Check-In
            A brief summary of how the conversation opened and the overall tone.

            ## Topics Discussed
            - Main themes raised by either person

            ## Support Needed
            - Blockers, concerns, or asks for help

            ## Commitments
            - [ ] Follow-ups or commitments made by either person

            ## Manager Notes
            - Coaching, feedback, or context that should be remembered
            """
        ),
        MeetingTemplateDefinition(
            id: "customer-discovery",
            title: "Customer: Discovery",
            category: "Commercial",
            icon: "person.crop.circle.badge.questionmark",
            kind: .builtin,
            promptBody: """
            Use this structure exactly:

            ## Customer Context
            - Company, role, or situation if mentioned

            ## Problems and Pain Points
            - Explicit frustrations, blockers, or unmet needs

            ## Current Workflow
            - How they currently solve the problem today

            ## Buying Signals
            - Indicators of urgency, budget, timing, or decision process

            ## Next Steps
            - [ ] Follow-up actions, owners, and dates if mentioned
            """
        ),
        MeetingTemplateDefinition(
            id: "hiring",
            title: "Hiring",
            category: "Recruiting",
            icon: "briefcase.fill",
            kind: .builtin,
            promptBody: """
            Use this structure exactly:

            ## Candidate Snapshot
            A concise overview of the candidate and relevant background.

            ## Strengths
            - Positive signals from the conversation

            ## Concerns
            - Risks, gaps, or open questions

            ## Role Fit
            - Why they do or do not fit the role as discussed

            ## Decision and Next Steps
            - [ ] Hiring decision, interview progression, or follow-up items
            """
        ),
        MeetingTemplateDefinition(
            id: "stand-up",
            title: "Stand-Up",
            category: "Team",
            icon: "figure.stand",
            kind: .builtin,
            promptBody: """
            Use this structure exactly:

            ## Yesterday
            - Work completed or progress since the last update

            ## Today
            - Planned work or priorities for today

            ## Blockers
            - Risks, delays, or dependencies

            ## Coordination Notes
            - Decisions, asks, or cross-team alignment points
            """
        ),
        MeetingTemplateDefinition(
            id: "weekly-team-meeting",
            title: "Weekly Team Meeting",
            category: "Team",
            icon: "calendar",
            kind: .builtin,
            promptBody: """
            Use this structure exactly:

            ## Weekly Overview
            A concise summary of the most important updates from the meeting.

            ## Progress Updates
            - Key workstreams and status changes

            ## Decisions
            - Decisions made or confirmed

            ## Risks and Open Questions
            - Issues that need attention or follow-up

            ## Action Items
            - [ ] Tasks, owners, and timing if mentioned
            """
        ),
    ]

    static let customIconOptions: [CustomIconOption] = [
        CustomIconOption(symbolName: "square.and.pencil", label: "Notes"),
        CustomIconOption(symbolName: "person.2.fill", label: "1 to 1"),
        CustomIconOption(symbolName: "person.crop.circle.badge.questionmark", label: "Discovery"),
        CustomIconOption(symbolName: "briefcase.fill", label: "Hiring"),
        CustomIconOption(symbolName: "calendar", label: "Weekly"),
        CustomIconOption(symbolName: "figure.stand", label: "Stand-Up"),
        CustomIconOption(symbolName: "person.fill.questionmark", label: "Interview"),
        CustomIconOption(symbolName: "person.fill.checkmark", label: "Review"),
        CustomIconOption(symbolName: "building.2.fill", label: "Business"),
        CustomIconOption(symbolName: "chart.line.uptrend.xyaxis", label: "Strategy"),
        CustomIconOption(symbolName: "dollarsign.circle", label: "Sales"),
        CustomIconOption(symbolName: "megaphone.fill", label: "Marketing"),
        CustomIconOption(symbolName: "hammer.fill", label: "Execution"),
        CustomIconOption(symbolName: "shippingbox.fill", label: "Ops"),
        CustomIconOption(symbolName: "doc.text.fill", label: "Docs"),
        CustomIconOption(symbolName: "checklist", label: "Checklist"),
        CustomIconOption(symbolName: "lightbulb.fill", label: "Ideas"),
        CustomIconOption(symbolName: "waveform.path.ecg", label: "Health"),
        CustomIconOption(symbolName: "graduationcap.fill", label: "Learning"),
        CustomIconOption(symbolName: "globe", label: "Global"),
        CustomIconOption(symbolName: "phone.fill", label: "Calls"),
        CustomIconOption(symbolName: "message.fill", label: "Conversation"),
        CustomIconOption(symbolName: "person.3.fill", label: "Team"),
        CustomIconOption(symbolName: "target", label: "Goals"),
        CustomIconOption(symbolName: "flag.fill", label: "Milestones"),
        CustomIconOption(symbolName: "sparkles", label: "Enhanced"),
        CustomIconOption(symbolName: "wand.and.stars", label: "Creative"),
        CustomIconOption(symbolName: "paperplane.fill", label: "Launch"),
        CustomIconOption(symbolName: "gearshape.fill", label: "Systems"),
        CustomIconOption(symbolName: "folder.fill", label: "Projects"),
        CustomIconOption(symbolName: "clock.fill", label: "Timeline"),
        CustomIconOption(symbolName: "bolt.fill", label: "Sprint"),
    ]

    static func normalizedCustomIcon(named icon: String?) -> String {
        let trimmed = icon?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return customIconFallback }
        // Older configs stored rocket.fill for launch-style templates; remap it for compatibility.
        if trimmed == "rocket.fill" {
            return "paperplane.fill"
        }
        return customIconOptions.contains(where: { $0.symbolName == trimmed }) ? trimmed : customIconFallback
    }

    static func customDefinition(from customTemplate: CustomMeetingTemplate) -> MeetingTemplateDefinition {
        MeetingTemplateDefinition(
            id: customTemplate.id,
            title: customTemplate.name,
            category: "Custom",
            icon: normalizedCustomIcon(named: customTemplate.icon),
            kind: .custom,
            promptBody: customTemplate.prompt,
            outputLanguage: customTemplate.outputLanguage
        )
    }

    static func customDefinitions(from customTemplates: [CustomMeetingTemplate]) -> [MeetingTemplateDefinition] {
        customTemplates.map(customDefinition)
    }

    /// A custom template stored with a built-in id overrides that built-in
    /// (user-edited built-in template). It keeps the built-in's slot in the
    /// list; deleting it restores the stock definition.
    static func isBuiltInID(_ id: String) -> Bool {
        builtIns.contains { $0.id == id }
    }

    static func allDefinitions(customTemplates: [CustomMeetingTemplate]) -> [MeetingTemplateDefinition] {
        let overrides = Dictionary(
            customTemplates.filter { isBuiltInID($0.id) }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let mergedBuiltIns = builtIns.map { builtIn in
            overrides[builtIn.id].map(customDefinition(from:)) ?? builtIn
        }
        let pureCustoms = customTemplates.filter { !isBuiltInID($0.id) }
        return [auto] + mergedBuiltIns + customDefinitions(from: pureCustoms)
    }

    static func resolveDefinition(id: String?, customTemplates: [CustomMeetingTemplate]) -> MeetingTemplateDefinition {
        let normalizedID = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? autoID
        if normalizedID == autoID {
            return auto
        }
        // Customs first so an edited built-in wins over the stock definition.
        if let custom = customTemplates.first(where: { $0.id == normalizedID }) {
            return customDefinition(from: custom)
        }
        if let builtIn = builtIns.first(where: { $0.id == normalizedID }) {
            return builtIn
        }
        return auto
    }

    static func resolveExactDefinition(id: String?, customTemplates: [CustomMeetingTemplate]) -> MeetingTemplateDefinition? {
        let normalizedID = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? autoID
        if normalizedID.isEmpty || normalizedID == autoID {
            return auto
        }
        if let custom = customTemplates.first(where: { $0.id == normalizedID }) {
            return customDefinition(from: custom)
        }
        if let builtIn = builtIns.first(where: { $0.id == normalizedID }) {
            return builtIn
        }
        return nil
    }

    static func resolveSnapshot(id: String?, customTemplates: [CustomMeetingTemplate]) -> MeetingTemplateSnapshot {
        resolveDefinition(id: id, customTemplates: customTemplates).snapshot
    }

    static func resolveExactSnapshot(id: String?, customTemplates: [CustomMeetingTemplate]) -> MeetingTemplateSnapshot? {
        resolveExactDefinition(id: id, customTemplates: customTemplates)?.snapshot
    }

    static func snapshot(for meeting: MeetingRecord, customTemplates: [CustomMeetingTemplate]) -> MeetingTemplateSnapshot {
        let storedID = meeting.selectedTemplateID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storedName = meeting.selectedTemplateName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storedPrompt = meeting.selectedTemplatePrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Prefer the live template definition so edits to a template (prompt,
        // name, output language) take effect everywhere — matching the template
        // tabs and the regenerate chip. Fall back to the stored snapshot only
        // when the template no longer exists (e.g. a deleted custom template).
        if let live = resolveExactSnapshot(id: storedID.isEmpty ? nil : storedID, customTemplates: customTemplates) {
            return live
        }
        if !storedID.isEmpty, !storedName.isEmpty, !storedPrompt.isEmpty {
            return MeetingTemplateSnapshot(
                id: storedID,
                name: storedName,
                kind: meeting.selectedTemplateKind ?? .auto,
                prompt: storedPrompt,
                // The output language is a generation-time preference, not part
                // of the stored snapshot: resolve it from the current config.
                outputLanguage: customTemplates.first(where: { $0.id == storedID })?.outputLanguage
            )
        }
        return resolveSnapshot(id: storedID.isEmpty ? nil : storedID, customTemplates: customTemplates)
    }
}
