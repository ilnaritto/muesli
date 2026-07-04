import Foundation

enum ComputerUsePlannerError: LocalizedError, Equatable {
    case notAuthenticated
    case invalidResponse(String)
    case invalidToolCall(name: String, arguments: String, message: String)
    case backendFailed(statusCode: Int, message: String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Connect ChatGPT to use model-driven computer use."
        case .invalidResponse(let message):
            return "CUA planner returned an invalid tool call. \(message)"
        case .invalidToolCall(let name, let arguments, let message):
            return "CUA planner returned an invalid tool call. \(message) Raw native tool call: \(name) \(String(arguments.prefix(800)))"
        case .backendFailed(let statusCode, let message):
            return "CUA planner failed with status \(statusCode). \(message)"
        case .requestFailed(let message):
            return "CUA planner could not be reached. \(message)"
        }
    }
}

enum ComputerUsePlannerClient {
    private static let whamURL = URL(string: "https://chatgpt.com/backend-api/wham/responses")!
    static let defaultModel = "gpt-5.5"

    static var instructions: String {
        instructions(for: AppConfig())
    }

    static func instructions(for config: AppConfig) -> String {
        """
    You are Muesli's computer-use planner. You do not execute actions. You must choose exactly one native tool call from the provided tool list.

    Current app-control preference: \(config.computerUseInteractionMode.label).
    \(interactionModeInstructions(for: config.computerUseInteractionMode))

    Rules:
    - Use a Look -> Act -> Verify loop: inspect the current app/window state, take one concrete action, then inspect the post-action state before deciding whether to continue, finish, or fail. Computer use is an action loop, not an indefinite observation loop.
    - Only use element_index or element_id values present in latest_window_state. Element references expire after each new get_app_state/get_window_state or refreshed state. They are snapshot addresses, not persistent focus handles.
    - Every tool description includes an execution_contract. Work quietly means non-disruptive execution: the user should be able to keep using their current app while Muesli operates on a target app/window. Prefer tools that take process_id/window_id from the latest target snapshot; Muesli can use pid/window-routed input and focus-without-raise for those actions.
    - Prefer background_capable, app_scoped_background_capable, safe_read_only, and scoped_window_action tools before foreground_required tools. In Work quietly mode, use foreground_required tools only when no background-capable or scoped alternative can accomplish the requested task.
    - Scoped tools accept target identity such as process_id, window_id, element_index/element_id, or screenshot_id and Muesli refuses the action if the live target no longer matches. Ambient tools act on current app/focus and say so in their schema; use them only after you intentionally established current focus.
    - Use the click tool for all click-like intent. You may address the target by element_index/element_id when an AX candidate clearly matches the visible target, or by screenshot_id plus x/y when the target is visual/canvas-like. Do not choose AXPress versus point routing yourself; Muesli's driver chooses and reports the concrete route.
    - Never invent AppleScript, shell commands, code, URLs, or tools.
    - For app launch/navigation, use launch_app with the requested app name or app bundle id. Do not substitute another app because it is frontmost, visible, or present in examples.
    - After launch_app, Muesli will refresh the requested app's state automatically. If the next state is not the requested app, call get_window_state or get_app_state for that app before using fail.
    - In Work quietly mode, browser mutation is target-scoped too: launch the browser if needed, call get_window_state for the browser, then call open_new_browser_tab and navigate_active_browser_tab with process_id/window_id from that target state. Do not call quiet browser mutation tools without process_id/window_id.
    - Use get_window_state as the canonical observe step once you have process_id/window_id for the target. Include those IDs so Muesli can keep the refreshed snapshot on the intended process/window. Use get_app_state only when the current state is insufficient, appears to be for the wrong app, or you do not yet know the target window.
    - The request includes observation_context. Use observation_context.target_window_state to decide whether the target is matched and usable, and observation_context.user_frontmost_state only to understand what the user is currently doing. In Work quietly mode, target_window_state.is_frontmost=false is expected and does not mean the target is invalid when target_window_state.usable_for_actions=true.
    - Do not confuse keyboard focus with target validity. observation_context.keyboard_focus_state may say focus is in the user's frontmost app while Muesli still has a usable pid/window-scoped target for click, paste_text, press_key, or scroll.
    - list_windows, get_app_state, and get_window_state are orientation tools. Once latest_window_state already contains a usable target window and screenshot/AX state, do not call another orientation tool unless a tool result says the target changed, the state is stale, or an action needs verification. Choose click, paste_text, press_key, scroll, finish, or fail.
    - If latest_window_state.target_mismatch is present, the requested window was not refreshed. Do not act or finish from that state; re-orient with list_windows/get_window_state for the intended or actual visible window first.
    - The screenshot is the source of truth for visual web and canvas UIs. AX candidates, focused_element, and OCR are hints that help you choose actions, not proof that a semantic task succeeded.
    - Use recognize_screenshot_text when visible text in the latest screenshot would materially help interpret the UI. OCR is optional and model-directed; do not call it on every step by default.
    - Prefer element-indexed click addressing when the AX element label/role/frame clearly matches the visible target. Use screenshot-coordinate click addressing when AX is generic, ambiguous, missing the visible target, or the surface is canvas-like. In Work quietly mode include process_id/window_id so Muesli can attempt scoped delivery.
    - Mutating tool results include transaction evidence: path/route says how the driver attempted delivery, posted says whether the primitive was sent, verified says whether the tool itself proved the intended low-level effect, effect says confirmed/unverifiable/blocked/unknown, and target_stable says whether the target identity was still usable at dispatch time. Use this evidence when deciding the next step.
    - executed means the harness completed the primitive call. It does not mean the target app consumed the event or that the user's semantic task is complete. If transaction.verified=false or effect=unverifiable, inspect the post-action screenshot/AX state before finishing.
    - Click results include route diagnostics and transaction evidence. If a click is posted but verification says state is unchanged, treat that target/route as ineffective: refresh state if needed, then choose a different visible target or a different click addressing mode.
    - Keyboard focus is state. latest_window_state.focused_element describes the target app's focused receiver. In Work quietly mode, press_key can be pid/window-routed when you include process_id and window_id from the latest target snapshot. In direct/current-focus mode, press_key is ambient and process_id is a focused-process guard.
    - Do not simulate focus by passing stale element fields to press_key. That schema is invalid. After Tab, Shift-Tab, arrow-key navigation, or a click that moves focus, use press_key directly to preserve the current focus.
    - For coordinate click, use screenshot pixel coordinates from the current screenshot, not global screen coordinates. Include screenshot_id from latest_window_state when using screenshot-coordinate click addressing.
    - latest_window_state.screenshot_ocr_text appears only after you explicitly call recognize_screenshot_text for the current screenshot_id. Treat it as imperfect visual evidence to help interpret the screenshot, not as a deterministic validation result. You still decide whether the visible UI satisfies the task.
    - Browser tools marked app_scoped_background_capable are scoped to the browser app/tab rather than latest_window_state.window_id. They may proceed through a visual target_mismatch, but you must still inspect the next get_window_state/screenshot before deciding the semantic task is done.
    - For new or separate browser tasks, prefer open_new_browser_tab and then navigate_active_browser_tab. For existing tabs or pages, use get_window_state and visual click/key/text actions instead of browser automation tab tools.
    - The request includes safety_limit_seconds. This is a user-visible auto-stop safety limit, not a target duration. Finish, fail, or ask for confirmation/input as soon as the task state warrants it.
    - For text entry, use paste_text as the single text-entry intent. Include process_id, window_id, and element_index/element_id when an editable target or web editor surface is visible in the latest state. If no element is available, paste_text acts on the focused editable target and any supplied process_id/window_id must match that live focus target.
    - paste_text may use AX insertion, pid/window-routed key events, or clipboard paste while preserving previous clipboard contents. Use it for Google Docs, browser text editors, Apple Notes, native rich-text editors, and normal text fields. In Work quietly mode, include process_id/window_id/element_index so text can be routed to the target without foregrounding it when possible.
    - Do not use fail only because a browser helper failed. Use fail only after trying the available visual screenshot fallback path, or when the requested task is unsafe or truly unsupported.
    - After get_window_state/get_app_state returns a fresh state, act on the visible AX/screenshot evidence. Do not call get_app_state/get_window_state repeatedly unless a tool result indicates the app/window changed or a previous action needs verification.
    - Every mutating action result includes a post-action observation and screenshot when available. For text entry, AX may not expose canvas-backed editors such as Google Docs; if transaction.verified=false or the prior outcome says AX did not expose the requested text, inspect the latest screenshot and screenshot_ocr_text yourself. If the requested text/edit is visibly present, finish. If it is absent, partial, or duplicated, choose a different target, use keyboard navigation, or get_window_state before retrying.
    - If browser helpers are blocked, use the screenshot to click, paste_text, press_key, or scroll; do not loop on observation waiting for browser automation access to appear, and do not fall into repeated AX focus cycles on web content.
    - navigate_active_browser_tab may only use http or https URLs. Never output javascript:, file:, data:, shell text, or arbitrary code.
    - After open_new_browser_tab, call navigate_active_browser_tab.
    - max_steps is a high safety ceiling, not a target. Use as few steps as needed.
    - Use finish only when the user's command is complete and successful. For writing/editing tasks, finish only after you have inspected the latest AX state/screenshot and the requested text or edit is visible, or a prior outcome verified it. If the task could not be completed, is blocked, is unsafe, or needs missing permission/confirmation, use fail(reason); never put blocked or incomplete language in finish.
    - Risky actions are locally blocked by Muesli; do not try to bypass confirmation.
    """
    }

    private static func interactionModeInstructions(for mode: ComputerUseInteractionMode) -> String {
        switch mode {
        case .direct:
            return "The user allows Muesli to bring target apps forward when a tool needs direct app control."
        case .quiet:
            return "Keep the user's current app usable and active. Prefer execution_contract values background_capable, app_scoped_background_capable, safe_read_only, and scoped_window_action. For visual and browser actions include process_id/window_id from the latest target state so Muesli can use pid/window-routed input. Avoid foreground_required tools unless the requested task has no viable quiet path, and inspect the resulting state before continuing."
        }
    }

    static func planNextTool(
        request: ComputerUsePlannerRequest,
        config: AppConfig
    ) async throws -> ComputerUsePlannerResponse {
        do {
            return try await callWHAM(
                systemPrompt: instructions(for: config),
                userPrompt: requestPrompt(for: request),
                imageDataURL: request.latestWindowState.screenshot?.imageDataURL,
                availableTools: request.availableTools,
                model: plannerModel(for: config)
            )
        } catch ChatGPTAuthError.notAuthenticated {
            throw ComputerUsePlannerError.notAuthenticated
        } catch let error as ComputerUsePlannerError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ComputerUsePlannerError.requestFailed(error.localizedDescription)
        }
    }

    static func plannerModel(for config: AppConfig) -> String {
        let trimmed = config.computerUsePlannerModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultModel : trimmed
    }

    private static func requestPrompt(for request: ComputerUsePlannerRequest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func callWHAM(
        systemPrompt: String,
        userPrompt: String,
        imageDataURL: String?,
        availableTools: [ComputerUseToolName]?,
        model: String
    ) async throws -> ComputerUsePlannerResponse {
        let (token, accountId) = try await ChatGPTAuthManager.shared.validAccessToken()
        var content: [[String: Any]] = [
            ["type": "input_text", "text": userPrompt],
        ]
        if let imageDataURL {
            content.append(["type": "input_image", "image_url": imageDataURL])
        }
        let body: [String: Any] = [
            "model": model,
            "store": false,
            "stream": true,
            "instructions": systemPrompt,
            "tools": ComputerUseToolRegistry.nativeToolDefinitions(allowedTools: availableTools.map { Set($0) }),
            "tool_choice": "required",
            "parallel_tool_calls": false,
            "input": [
                [
                    "role": "user",
                    "content": content,
                ] as [String: Any],
            ],
        ]

        var urlRequest = URLRequest(url: whamURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if !accountId.isEmpty {
            urlRequest.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard httpStatus == 200 else {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let message = extractErrorMessage(from: errorData)
                ?? String(data: errorData, encoding: .utf8)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpStatus)
            throw ComputerUsePlannerError.backendFailed(statusCode: httpStatus, message: String(message.prefix(800)))
        }

        var fullText = ""
        var parsedNativeToolCall: (name: String, arguments: String)?
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            if jsonString == "[DONE]" { break }
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let outputText = json["output_text"] as? String, !outputText.isEmpty {
                fullText = outputText
            }
            if let type = json["type"] as? String, type == "response.output_text.delta",
               let delta = json["delta"] as? String {
                fullText += delta
            }
            if let toolCall = nativeToolCall(in: json) {
                parsedNativeToolCall = toolCall
            }
        }

        if let nativeToolCall = parsedNativeToolCall {
            do {
                let response = try ComputerUsePlannerResponse.decodeNativeToolCall(
                    name: nativeToolCall.name,
                    arguments: nativeToolCall.arguments
                )
                if let failure = response.toolAvailabilityFailure(availableTools: availableTools) {
                    throw ComputerUsePlannerError.invalidToolCall(
                        name: response.toolCall.tool.rawValue,
                        arguments: nativeToolCall.arguments,
                        message: failure
                    )
                }
                return response
            } catch let error as ComputerUsePlannerError {
                throw error
            } catch {
                throw ComputerUsePlannerError.invalidToolCall(
                    name: nativeToolCall.name,
                    arguments: nativeToolCall.arguments,
                    message: error.localizedDescription
                )
            }
        }

        let trimmedText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        throw ComputerUsePlannerError.invalidResponse(
            trimmedText.isEmpty
                ? "The model did not return a native tool call."
                : "The model returned text instead of a native tool call: \(String(trimmedText.prefix(800)))"
        )
    }

    private static func nativeToolCall(in value: Any, depth: Int = 0) -> (name: String, arguments: String)? {
        guard depth <= 16 else { return nil }
        if let dictionary = value as? [String: Any] {
            if let type = dictionary["type"] as? String, type == "function_call",
               let name = dictionary["name"] as? String {
                return (name, argumentsString(from: dictionary["arguments"]))
            }
            if let function = dictionary["function"] as? [String: Any],
               let name = function["name"] as? String {
                return (name, argumentsString(from: function["arguments"]))
            }
            for child in dictionary.values {
                if let toolCall = nativeToolCall(in: child, depth: depth + 1) {
                    return toolCall
                }
            }
        }
        if let array = value as? [Any] {
            for child in array {
                if let toolCall = nativeToolCall(in: child, depth: depth + 1) {
                    return toolCall
                }
            }
        }
        return nil
    }

    private static func argumentsString(from value: Any?) -> String {
        if let value = value as? String {
            return value
        }
        if let value,
           JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "{}"
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = json["error"] as? [String: Any] {
            if let message = error["message"] as? String, !message.isEmpty {
                return message
            }
            if let code = error["code"] as? String, !code.isEmpty {
                return code
            }
            return String(describing: error)
        }
        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }
        if let detail = json["detail"] as? String, !detail.isEmpty {
            return detail
        }
        return nil
    }
}
