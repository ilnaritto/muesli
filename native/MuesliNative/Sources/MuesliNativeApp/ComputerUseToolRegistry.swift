import Foundation

struct ComputerUseToolDefinition: Codable, Equatable {
    let name: ComputerUseToolName
    let description: String
    let schema: ComputerUseToolSchema
    let executionContract: ComputerUseToolExecutionContract
    let riskPolicy: String
    let mutating: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case schema
        case executionContract = "execution_contract"
        case riskPolicy = "risk_policy"
        case mutating
    }
}

enum ComputerUseToolExecutionContract: String, Codable, Equatable {
    case safeReadOnly = "safe_read_only"
    case backgroundCapable = "background_capable"
    case appScopedBackgroundCapable = "app_scoped_background_capable"
    case scopedWindowAction = "scoped_window_action"
    case ambientCurrentFocus = "ambient_current_focus"
    case foregroundRequired = "foreground_required"
    case visualFeedbackOnly = "visual_feedback_only"
    case finalization = "finalization"

    var description: String {
        switch self {
        case .safeReadOnly:
            return "Read-only; does not intentionally change app focus or UI state."
        case .backgroundCapable:
            return "Can operate against a target app/window without intentionally bringing it forward when permissions and app support allow it."
        case .appScopedBackgroundCapable:
            return "Targets an app/browser through app-scoped APIs and does not depend on the latest visual window match."
        case .scopedWindowAction:
            return "Mutates a target from the latest process/window/element/screenshot state; requires a matched target window when the latest state reports target_mismatch. In Work quietly mode, prefer process_id/window_id targets so input can be routed to the target without foregrounding it."
        case .ambientCurrentFocus:
            return "Acts on the current keyboard/accessibility focus; use only after intentionally establishing focus."
        case .foregroundRequired:
            return "Uses foreground/global pointer or focus behavior and may affect the user's active app or cursor."
        case .visualFeedbackOnly:
            return "Only moves Muesli's visible pointer/cursor feedback; does not complete an app action."
        case .finalization:
            return "Ends the planner loop; only use when latest evidence supports the final state."
        }
    }

    var requiresMatchedVisualTarget: Bool {
        switch self {
        case .scopedWindowAction, .ambientCurrentFocus, .foregroundRequired, .finalization:
            return true
        case .safeReadOnly, .backgroundCapable, .appScopedBackgroundCapable, .visualFeedbackOnly:
            return false
        }
    }
}

struct ComputerUseToolSchema: Codable, Equatable {
    let type: String
    let properties: [String: ComputerUseToolSchemaProperty]
    let required: [String]
    let additionalProperties: Bool

    init(
        properties: [String: ComputerUseToolSchemaProperty],
        required: [String]
    ) {
        type = "object"
        self.properties = properties
        self.required = required
        additionalProperties = false
    }
}

struct ComputerUseToolSchemaProperty: Codable, Equatable {
    let type: String
    let description: String
    let enumValues: [String]?
    let items: ComputerUseToolSchemaArrayItems?

    enum CodingKeys: String, CodingKey {
        case type
        case description
        case enumValues = "enum"
        case items
    }

    init(
        type: String,
        description: String,
        enumValues: [String]? = nil,
        items: ComputerUseToolSchemaArrayItems? = nil
    ) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
        self.items = items
    }
}

struct ComputerUseToolSchemaArrayItems: Codable, Equatable {
    let type: String
    let enumValues: [String]?

    enum CodingKeys: String, CodingKey {
        case type
        case enumValues = "enum"
    }
}

enum ComputerUseToolRegistry {
    static let catalogVersion = "muesli-cua-tools-v9"

    static let definitions: [ComputerUseToolDefinition] = [
        definition(.listApps, "List running desktop apps with names, bundle IDs, process IDs, and active state.", required: [], properties: [:], risk: "safe read-only"),
        definition(.launchApp, "Launch a macOS app by app_name or app_bundle_id. In Work quietly mode, launch without intentional foreground activation when macOS and the target app allow it; in Bring apps forward mode, activation is allowed.", required: [], properties: [
            "app_name": .string("Human app name, for example Google Chrome."),
            "app_bundle_id": .string("Bundle identifier, for example com.google.Chrome."),
        ], risk: "quiet mode attempts background launch; direct mode allows foreground activation"),
        definition(.listWindows, "List visible windows, optionally scoped by app_bundle_id. Orientation only: after a target window screenshot/state is available, choose a concrete action, finish, or fail instead of repeating window listing.", required: [], properties: [
            "app_bundle_id": .string("Optional bundle identifier to scope windows."),
        ], risk: "safe read-only"),
        definition(.getAppState, "Capture fresh app/window state: state_id, process_id, window_id, screenshot metadata/image for the planner, AX candidates as optional hints, focused element, selected text, cursor, and app hints. Prefer get_window_state once a target process_id/window_id is known; call recognize_screenshot_text only when OCR would help. Use this for Look/Verify, not as a waiting loop; after a fresh usable state, act, finish, or fail unless the target changed.", required: [], properties: [
            "app_bundle_id": .string("Optional app bundle to activate before capture."),
            "window_id": .integer("Optional window id hint."),
        ], risk: "safe read-only"),
        definition(.getWindowState, "Capture or refresh a specific target window. Prefer this when you already know process_id/window_id from latest_window_state or list_windows; Muesli uses these IDs to keep the refreshed snapshot on the requested process/window when possible. Use this for Look/Verify, not as a waiting loop; after a fresh usable state, act, finish, or fail unless the target changed.", required: [], properties: [
            "app_bundle_id": .string("Optional app bundle to activate before capture."),
            "process_id": .integer("Optional process id from latest_window_state or list_windows."),
            "window_id": .integer("Optional window id hint."),
        ], risk: "safe read-only"),
        definition(.recognizeScreenshotText, "Run OCR on the latest screenshot when visible text would help interpret the screen. This is optional and model-directed; use it when the screenshot alone is visually ambiguous or text is too small to inspect.", required: ["screenshot_id"], properties: [
            "screenshot_id": .string("Current screenshot id from latest_window_state."),
            "label": .string("Optional reason or visible region label for trace."),
        ], risk: "safe read-only; may be slow on large screenshots"),
        definition(.click, "Click a target from the latest screenshot/window state. Provide either an element_index/element_id when a visible AX candidate clearly matches the target, or screenshot_id plus x/y when the visible target is canvas-like, generic, or not exposed through AX. Do not choose AXPress versus point routes yourself: Muesli's driver selects and reports the concrete route, prefers scoped pid/window delivery in Work quietly mode, and fails instead of silently changing to disruptive foreground control when quiet delivery is not possible.", required: [], properties: [
            "process_id": .integer("Recommended in Work quietly mode; process id from the latest state."),
            "window_id": .integer("Recommended in Work quietly mode; window id from the latest state."),
            "element_index": .integer("Temporary element index from the latest state."),
            "element_id": .string("Temporary element id from the latest state, for example e12."),
            "screenshot_id": .string("Current screenshot id."),
            "x": .number("Screenshot pixel x coordinate."),
            "y": .number("Screenshot pixel y coordinate."),
            "clicks": .integer("1 for single click, 2 for double click."),
            "button": .string("left or right."),
            "label": .string("Human target label for trace and safety."),
        ], risk: "confirmation for risky labels or unknown coordinate targets"),
        definition(.pasteText, "Enter literal text into a target. Provide process_id/window_id and optional editable element_index/element_id from the latest state when available; otherwise this is a focused-text action. Do not choose lower-level text delivery routes yourself: Muesli's driver chooses the safest available text route, restores the user's clipboard when clipboard fallback is needed, and returns transaction evidence. If transaction.verified=false, the text was posted but not proven consumed; inspect the post-action AX state/screenshot before finishing or retrying.", required: ["text"], properties: [
            "app_name": .string("Optional target app name, for example Notes."),
            "app_bundle_id": .string("Optional target app bundle identifier, for example com.apple.Notes."),
            "process_id": .integer("Optional process id from latest_window_state or list_windows."),
            "window_id": .integer("Optional window id from latest_window_state or list_windows."),
            "element_index": .integer("Optional temporary editable element index from the latest state."),
            "element_id": .string("Optional temporary editable element id from the latest state."),
            "text": .string("Text to enter."),
            "label": .string("Human target label for trace."),
        ], risk: "safe primitive; can temporarily use clipboard and restores clipboard; quiet mode posts text to target pid/window without foregrounding the target when possible"),
        definition(.pressKey, "Press one key with optional modifiers. Use this for keyboard navigation and shortcuts after the target state is clear. In Work quietly mode, include process_id and window_id from the latest target snapshot so Muesli can post a pid/window-routed key without changing the user's frontmost app. It never accepts element_index or element_id; use paste_text for targeted text insertion. The result transaction reports whether key events were posted; verify the UI effect from the post-action state.", required: ["key"], properties: [
            "app_name": .string("Optional target app name."),
            "app_bundle_id": .string("Optional target app bundle identifier."),
            "process_id": .integer("Optional process id from latest_window_state or list_windows."),
            "window_id": .integer("Recommended in Work quietly mode for focus-without-raise before dispatch."),
            "key": .string("Key name, for example enter, tab, l, escape."),
            "modifiers": .array("Optional modifiers.", item: .string("Modifier", enumValues: ComputerUseKeyModifier.allCases.map(\.rawValue))),
        ], risk: "confirmation for Cmd-Q and Cmd-W"),
        definition(.scroll, "Scroll the current view or a scrollable AX element from the latest state. In Work quietly mode include process_id and window_id; when no scrollable AX element is supplied, Muesli routes PageUp/PageDown/arrow keys to the target pid/window instead of using global scroll. The result transaction reports the scroll path and posted state; verify movement from the post-action state.", required: ["direction"], properties: [
            "process_id": .integer("Recommended in Work quietly mode; process id from the latest target state."),
            "window_id": .integer("Recommended in Work quietly mode; window id from the latest target state."),
            "element_index": .integer("Optional temporary scrollable element index from the latest state."),
            "element_id": .string("Optional temporary scrollable element id from the latest state."),
            "direction": .string("Scroll direction.", enumValues: ["up", "down", "left", "right"]),
            "pages": .number("Approximate page count, default 1."),
        ], risk: "safe primitive"),
        definition(.openNewBrowserTab, "Open a new tab in a supported browser and make it active. Prefer this for new or separate web tasks. In Work quietly mode, include process_id and window_id from the latest browser window state; Muesli routes Cmd-T to that target window instead of mutating the user's frontmost app. The result transaction confirms command delivery only; inspect the next browser state before navigating or finishing.", required: ["app_bundle_id"], properties: [
            "app_bundle_id": .string("Browser bundle identifier, currently com.google.Chrome."),
            "process_id": .integer("Required in Work quietly mode; browser process id from latest_window_state or list_windows."),
            "window_id": .integer("Recommended in Work quietly mode; browser window id from latest_window_state or list_windows."),
        ], risk: "browser app-scoped automation; may visibly change target browser"),
        definition(.navigateActiveBrowserTab, "Navigate the active browser tab to a safe http/https URL without tab indexes. Prefer this immediately after open_new_browser_tab. In Work quietly mode, include process_id and window_id from the same target browser window so Muesli routes Cmd-L, URL paste, and Enter to that window. The result transaction confirms command delivery only; inspect the next browser screenshot/state to verify URL/page readiness.", required: ["app_bundle_id", "url"], properties: [
            "app_bundle_id": .string("Browser bundle identifier, currently com.google.Chrome."),
            "process_id": .integer("Required in Work quietly mode; browser process id from latest_window_state or list_windows."),
            "window_id": .integer("Recommended in Work quietly mode; browser window id from latest_window_state or list_windows."),
            "url": .string("http or https URL only."),
        ], risk: "rejects javascript:, file:, data:, shell-like strings, and unsafe URLs"),
        definition(.finish, "Finish when the user task is complete. For writing/editing tasks, use only after you inspect latest AX state/screenshot and confirm the requested text or edit is visible, or a prior outcome verified it. Use reason for the final answer.", required: [], properties: [
            "reason": .string("Final user-facing result."),
        ], risk: "safe finalization"),
        definition(.fail, "Fail explicitly when blocked, unsupported, unsafe, or incomplete. Use reason to explain.", required: ["reason"], properties: [
            "reason": .string("Failure reason."),
        ], risk: "safe finalization"),
    ]

    static func definition(for tool: ComputerUseToolName) -> ComputerUseToolDefinition? {
        definitions.first { $0.name == tool }
    }

    static func isModelFacing(_ tool: ComputerUseToolName) -> Bool {
        definition(for: tool) != nil
    }

    static func promptDocumentation(allowedTools: Set<ComputerUseToolName>? = nil) -> String {
        selectedDefinitions(allowedTools: allowedTools).map { definition in
            let required = definition.schema.required.isEmpty ? "none" : definition.schema.required.joined(separator: ", ")
            let properties = definition.schema.properties
                .sorted { $0.key < $1.key }
                .map { key, property in
                    var line = "  - \(key): \(property.type). \(property.description)"
                    if let values = property.enumValues {
                        line += " Allowed: \(values.joined(separator: ", "))."
                    }
                    return line
                }
                .joined(separator: "\n")
            let propertyText = properties.isEmpty ? "  - no arguments" : properties
            return """
            Tool: \(definition.name.rawValue)
            Description: \(definition.description)
            Execution contract: \(definition.executionContract.rawValue) - \(definition.executionContract.description)
            Required: \(required)
            Risk policy: \(definition.riskPolicy)
            Schema properties:
            \(propertyText)
            """
        }.joined(separator: "\n\n")
    }

    static func nativeToolDefinitions(allowedTools: Set<ComputerUseToolName>? = nil) -> [[String: Any]] {
        selectedDefinitions(allowedTools: allowedTools).map { definition in
            [
                "type": "function",
                "name": definition.name.rawValue,
                "description": "\(definition.description) Execution contract: \(definition.executionContract.rawValue) - \(definition.executionContract.description) Risk policy: \(definition.riskPolicy)",
                "parameters": toolParameters(for: definition),
            ]
        }
    }

    private static func selectedDefinitions(allowedTools: Set<ComputerUseToolName>?) -> [ComputerUseToolDefinition] {
        guard let allowedTools else { return definitions }
        return definitions.filter { allowedTools.contains($0.name) }
    }

    private static func toolParameters(for definition: ComputerUseToolDefinition) -> [String: Any] {
        let properties = definition.schema.properties
            .filter { $0.key != "tool" }
            .reduce(into: [String: Any]()) { partial, entry in
                partial[entry.key] = entry.value.jsonSchema
            }
        return [
            "type": definition.schema.type,
            "properties": properties,
            "required": definition.schema.required.filter { $0 != "tool" },
            "additionalProperties": definition.schema.additionalProperties,
        ]
    }

    private static func definition(
        _ name: ComputerUseToolName,
        _ description: String,
        required: [String],
        properties: [String: ComputerUseToolSchemaProperty],
        risk: String
    ) -> ComputerUseToolDefinition {
        ComputerUseToolDefinition(
            name: name,
            description: description,
            schema: ComputerUseToolSchema(
                properties: ["tool": .string("Tool name.", enumValues: [name.rawValue])].merging(properties) { current, _ in current },
                required: ["tool"] + required
            ),
            executionContract: executionContract(for: name),
            riskPolicy: risk,
            mutating: ComputerUseToolInvocation(tool: name).isMutating
        )
    }

    static func executionContract(for tool: ComputerUseToolName) -> ComputerUseToolExecutionContract {
        switch tool {
        case .listApps, .listWindows, .getAppState, .getWindowState, .recognizeScreenshotText, .listBrowserTabs, .pageGetText, .pageQueryDOM:
            return .safeReadOnly
        case .launchApp:
            return .backgroundCapable
        case .openNewBrowserTab, .navigateURL, .navigateActiveBrowserTab, .activateBrowserTab:
            return .appScopedBackgroundCapable
        case .click, .clickElement, .focusElement, .performSecondaryAction, .setValue, .typeText, .pasteText:
            return .scopedWindowAction
        case .pressKey, .hotkey, .activateFocused:
            return .ambientCurrentFocus
        case .clickPoint, .scroll, .drag:
            return .foregroundRequired
        case .moveCursor:
            return .visualFeedbackOnly
        case .finish, .fail:
            return .finalization
        }
    }
}

private extension ComputerUseToolSchemaProperty {
    static func string(_ description: String, enumValues: [String]? = nil) -> ComputerUseToolSchemaProperty {
        ComputerUseToolSchemaProperty(type: "string", description: description, enumValues: enumValues)
    }

    static func integer(_ description: String) -> ComputerUseToolSchemaProperty {
        ComputerUseToolSchemaProperty(type: "integer", description: description)
    }

    static func number(_ description: String) -> ComputerUseToolSchemaProperty {
        ComputerUseToolSchemaProperty(type: "number", description: description)
    }

    static func array(_ description: String, item: ComputerUseToolSchemaProperty) -> ComputerUseToolSchemaProperty {
        ComputerUseToolSchemaProperty(
            type: "array",
            description: description,
            items: ComputerUseToolSchemaArrayItems(type: item.type, enumValues: item.enumValues)
        )
    }

    var jsonSchema: [String: Any] {
        var schema: [String: Any] = [
            "type": type,
            "description": description,
        ]
        if let enumValues {
            schema["enum"] = enumValues
        }
        if let items {
            var itemSchema: [String: Any] = ["type": items.type]
            if let enumValues = items.enumValues {
                itemSchema["enum"] = enumValues
            }
            schema["items"] = itemSchema
        }
        return schema
    }
}
