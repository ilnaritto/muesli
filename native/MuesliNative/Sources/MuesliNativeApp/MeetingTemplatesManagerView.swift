import SwiftUI
import MuesliCore

/// Two-pane template manager: the left column lists "New template", the
/// user's templates and the built-ins (each with an on/off switch); the
/// right pane edits the selection. Presented as a wide sheet from the
/// meeting page, or embedded into Settings → Templates (isEmbedded).
struct MeetingTemplatesManagerView: View {
    let appState: AppState
    let controller: MuesliController
    let onClose: () -> Void
    /// Opens with the "new template" editor selected.
    var startsCreating: Bool = false
    /// Opens with this template (built-in or custom) selected.
    var startsEditingTemplateID: String? = nil
    /// Rendered inside the Settings pane rather than as a sheet:
    /// no fixed size, no own background, no Done button.
    var isEmbedded: Bool = false

    private enum Selection: Hashable {
        case newTemplate
        case template(String)
    }

    @State private var selection: Selection = .newTemplate
    @State private var draftTemplateName = ""
    @State private var draftTemplatePrompt = ""
    @State private var draftTemplateIcon = MeetingTemplates.customIconFallback
    @State private var draftTemplateLanguage: String? = nil
    @State private var showNameValidationError = false
    @State private var showPromptValidationError = false
    @State private var templateToDelete: CustomMeetingTemplate?
    @State private var showIconPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
            header

            HStack(alignment: .top, spacing: MuesliTheme.spacing16) {
                sidebar
                    .frame(width: isEmbedded ? 220 : 250)
                editorPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(isEmbedded ? 0 : MuesliTheme.spacing24)
        .frame(minWidth: isEmbedded ? nil : 920, minHeight: isEmbedded ? nil : 580)
        .background(isEmbedded ? Color.clear : MuesliTheme.backgroundDeep)
        .onAppear {
            if let templateID = startsEditingTemplateID {
                selection = .template(templateID)
                appState.meetingTemplatesManagerStartsEditingID = nil
            } else if startsCreating {
                selection = .newTemplate
                appState.meetingTemplatesManagerStartsCreating = false
            }
            loadDraft()
        }
        .onChange(of: selection) { _, _ in
            loadDraft()
        }
        .alert(
            tr("Delete \"\(templateToDelete?.name ?? "")\"?", "Удалить «\(templateToDelete?.name ?? "")»?"),
            isPresented: Binding(
                get: { templateToDelete != nil },
                set: { if !$0 { templateToDelete = nil } }
            )
        ) {
            Button(tr("Cancel", "Отмена"), role: .cancel) {
                templateToDelete = nil
            }
            Button(tr("Delete", "Удалить"), role: .destructive) {
                guard let template = templateToDelete else { return }
                controller.deleteCustomMeetingTemplate(id: template.id)
                if selection == .template(template.id) {
                    selection = .newTemplate
                }
                templateToDelete = nil
            }
        } message: {
            Text(tr("This template will be permanently removed. Existing meetings will keep their saved template snapshot.", "Этот шаблон будет удалён навсегда. Существующие встречи сохранят свой снимок шаблона."))
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        ZStack {
            Text(tr("Meeting Templates", "Шаблоны встреч"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MuesliTheme.textPrimary)

            if !isEmbedded {
                HStack {
                    Spacer()
                    capsuleButton(tr("Done", "Готово"), systemImage: "checkmark") {
                        onClose()
                    }
                    .help(tr("Close template manager", "Закрыть менеджер шаблонов"))
                }
            }
        }
        .frame(height: 40)
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                sidebarRow(
                    icon: "plus",
                    title: tr("New template", "Новый шаблон"),
                    isSelected: selection == .newTemplate,
                    iconTint: MuesliTheme.accent,
                    toggleID: nil
                ) {
                    selection = .newTemplate
                }

                let customs = controller.customOnlyMeetingTemplates()
                if !customs.isEmpty {
                    sidebarSectionHeader(tr("My templates", "Мои шаблоны"))
                    ForEach(customs) { template in
                        sidebarRow(
                            icon: MeetingTemplates.normalizedCustomIcon(named: template.icon),
                            title: template.name,
                            isSelected: selection == .template(template.id),
                            toggleID: template.id
                        ) {
                            selection = .template(template.id)
                        }
                    }
                }

                sidebarSectionHeader(tr("Built-in", "Встроенные"))
                ForEach(controller.builtInMeetingTemplates()) { template in
                    sidebarRow(
                        icon: template.icon,
                        title: template.title,
                        isSelected: selection == .template(template.id),
                        showsEditedMark: isOverridden(template.id),
                        toggleID: template.id
                    ) {
                        selection = .template(template.id)
                    }
                }
            }
            .padding(MuesliTheme.spacing8)
        }
        .background(MuesliTheme.backgroundBase)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private func sidebarSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(MuesliTheme.textTertiary)
            .textCase(.uppercase)
            .padding(.horizontal, MuesliTheme.spacing8)
            .padding(.top, MuesliTheme.spacing12)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func sidebarRow(
        icon: String,
        title: String,
        isSelected: Bool,
        iconTint: Color? = nil,
        showsEditedMark: Bool = false,
        toggleID: String?,
        action: @escaping () -> Void
    ) -> some View {
        let isEnabled = toggleID.map { controller.isMeetingTemplateEnabled(id: $0) } ?? true
        HStack(spacing: MuesliTheme.spacing8) {
            Button(action: action) {
                HStack(spacing: MuesliTheme.spacing8) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? MuesliTheme.accent : (iconTint ?? MuesliTheme.textSecondary))
                        .frame(width: 16)
                    Text(title)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(isSelected ? MuesliTheme.textPrimary : MuesliTheme.textSecondary)
                        .lineLimit(1)
                    if showsEditedMark {
                        Circle()
                            .fill(MuesliTheme.accent)
                            .frame(width: 5, height: 5)
                            .help(tr("Edited", "Изменён"))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let toggleID {
                Toggle("", isOn: Binding(
                    get: { controller.isMeetingTemplateEnabled(id: toggleID) },
                    set: { controller.setMeetingTemplateEnabled(id: toggleID, enabled: $0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help(tr("Show as a tab on the meeting page", "Показывать вкладкой на странице встречи"))
            }
        }
        .padding(.horizontal, MuesliTheme.spacing8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .fill(isSelected ? MuesliTheme.accentSubtle : Color.clear)
        )
        .opacity(isEnabled ? 1 : 0.55)
    }

    // MARK: - Editor pane

    private var isCreating: Bool { selection == .newTemplate }

    private var selectedTemplateID: String? {
        if case let .template(id) = selection { return id }
        return nil
    }

    private func isBuiltIn(_ id: String) -> Bool {
        MeetingTemplates.isBuiltInID(id)
    }

    private func isOverridden(_ id: String) -> Bool {
        isBuiltIn(id) && controller.customMeetingTemplates().contains { $0.id == id }
    }

    @ViewBuilder
    private var editorPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        fieldLabel(tr("Name", "Название"))
                        Spacer()
                        if let id = selectedTemplateID, isBuiltIn(id) {
                            Text(isOverridden(id) ? tr("built-in · edited", "встроенный · изменён") : tr("built-in", "встроенный"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(MuesliTheme.textTertiary)
                        }
                    }
                    HStack(spacing: MuesliTheme.spacing8) {
                        // Icon chip: tap to pick a symbol from a popover.
                        Button {
                            showIconPicker = true
                        } label: {
                            Image(systemName: draftTemplateIcon)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(MuesliTheme.accent)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(MuesliTheme.backgroundBase))
                                .overlay(Circle().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(tr("Template icon", "Значок шаблона"))
                        .popover(isPresented: $showIconPicker, arrowEdge: .bottom) {
                            iconPickerPopover
                        }

                        TextField(tr("Customer follow-up", "Встреча с клиентом"), text: $draftTemplateName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(MuesliTheme.textPrimary)
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .frame(maxWidth: .infinity)
                            .background(Capsule().fill(MuesliTheme.backgroundBase))
                            .overlay(
                                Capsule().strokeBorder(
                                    showNameValidationError ? MuesliTheme.recording.opacity(0.75) : MuesliTheme.surfaceBorder,
                                    lineWidth: 1
                                )
                            )
                            .onChange(of: draftTemplateName) { _, newValue in
                                if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    showNameValidationError = false
                                }
                            }
                    }
                    if showNameValidationError {
                        validationText(tr("Enter a template name.", "Введите название шаблона."))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel(tr("Output language", "Язык выдачи"))
                    languagePicker
                }

                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel(tr("Prompt", "Промпт"))
                    TextEditor(text: $draftTemplatePrompt)
                        .font(.system(size: 12))
                        .foregroundStyle(MuesliTheme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 180)
                        .padding(MuesliTheme.spacing12)
                        .background(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).fill(MuesliTheme.backgroundBase))
                        .overlay(
                            RoundedRectangle(cornerRadius: MuesliTheme.cornerXL)
                                .strokeBorder(
                                    showPromptValidationError ? MuesliTheme.recording.opacity(0.75) : MuesliTheme.surfaceBorder,
                                    lineWidth: 1
                                )
                        )
                        .onChange(of: draftTemplatePrompt) { _, newValue in
                            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                showPromptValidationError = false
                            }
                        }
                    if showPromptValidationError {
                        validationText(tr("Enter the prompt instructions for this template.", "Введите инструкции промпта для этого шаблона."))
                    }
                }

                HStack(spacing: MuesliTheme.spacing8) {
                    if let id = selectedTemplateID {
                        if isBuiltIn(id) {
                            if isOverridden(id) {
                                capsuleButton(tr("Reset to Default", "Сбросить к стандартному"), systemImage: "arrow.uturn.backward") {
                                    controller.resetBuiltInMeetingTemplate(id: id)
                                    loadDraft()
                                }
                            }
                        } else {
                            capsuleButton(tr("Delete", "Удалить"), systemImage: "trash", style: .destructive) {
                                templateToDelete = controller.customMeetingTemplates().first { $0.id == id }
                            }
                        }
                    }
                    Spacer()
                    capsuleButton(
                        isCreating ? tr("Create template", "Создать шаблон") : tr("Save changes", "Сохранить изменения"),
                        systemImage: isCreating ? "plus" : "checkmark",
                        style: .accent
                    ) {
                        saveDraft()
                    }
                }
                .padding(.top, MuesliTheme.spacing4)
            }
            .padding(.vertical, 2)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(MuesliTheme.caption())
            .foregroundStyle(MuesliTheme.textSecondary)
            .padding(.leading, 16)
    }

    private func validationText(_ message: String) -> some View {
        Text(message)
            .font(MuesliTheme.caption())
            .foregroundStyle(MuesliTheme.recording)
            .padding(.leading, 16)
    }

    // MARK: - Capsule buttons (meeting-page chip style)

    private enum CapsuleButtonStyleKind {
        case neutral
        case accent
        case destructive
    }

    private func capsuleButton(
        _ title: String,
        systemImage: String,
        style: CapsuleButtonStyleKind = .neutral,
        action: @escaping () -> Void
    ) -> some View {
        let foreground: Color
        let background: Color
        let border: Color
        switch style {
        case .neutral:
            foreground = MuesliTheme.textSecondary
            background = MuesliTheme.backgroundBase
            border = MuesliTheme.surfaceBorder
        case .accent:
            foreground = .white
            background = MuesliTheme.accent
            border = .clear
        case .destructive:
            foreground = MuesliTheme.recording
            background = MuesliTheme.recording.opacity(0.1)
            border = MuesliTheme.recording.opacity(0.2)
        }
        return Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(Capsule().fill(background))
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Language picker

    @ViewBuilder
    private var languagePicker: some View {
        Menu {
            Button {
                draftTemplateLanguage = nil
            } label: {
                if draftTemplateLanguage == nil {
                    Label(MeetingOutputLanguage.displayName(for: nil), systemImage: "checkmark")
                } else {
                    Text(MeetingOutputLanguage.displayName(for: nil))
                }
            }
            Divider()
            ForEach(MeetingOutputLanguage.options, id: \.code) { option in
                Button {
                    draftTemplateLanguage = option.code
                } label: {
                    if draftTemplateLanguage == option.code {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 12, weight: .medium))
                Text(MeetingOutputLanguage.displayName(for: draftTemplateLanguage))
                    .font(.system(size: 13, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(MuesliTheme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 18)
        .frame(height: 40)
        .background(Capsule().fill(MuesliTheme.backgroundBase))
        .overlay(Capsule().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
        .contentShape(Capsule())
    }

    // MARK: - Icon picker popover

    @ViewBuilder
    private var iconPickerPopover: some View {
        let columns = [
            GridItem(.adaptive(minimum: 36, maximum: 36), spacing: 6)
        ]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(MeetingTemplates.customIconOptions) { icon in
                Button {
                    draftTemplateIcon = icon.symbolName
                    showIconPicker = false
                } label: {
                    Image(systemName: icon.symbolName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(
                            draftTemplateIcon == icon.symbolName
                                ? MuesliTheme.accent
                                : MuesliTheme.textSecondary
                        )
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(
                            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                .fill(
                                    draftTemplateIcon == icon.symbolName
                                        ? MuesliTheme.accent.opacity(0.12)
                                        : MuesliTheme.backgroundRaised
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                .strokeBorder(
                                    draftTemplateIcon == icon.symbolName
                                        ? MuesliTheme.accent.opacity(0.35)
                                        : MuesliTheme.surfaceBorder,
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .help(icon.label)
            }
        }
        .padding(MuesliTheme.spacing12)
        .frame(width: 320)
    }

    // MARK: - Draft handling

    private func loadDraft() {
        clearValidationErrors()
        showIconPicker = false
        switch selection {
        case .newTemplate:
            draftTemplateName = ""
            draftTemplatePrompt = ""
            draftTemplateIcon = MeetingTemplates.customIconFallback
            draftTemplateLanguage = nil
        case .template(let id):
            if let custom = controller.customMeetingTemplates().first(where: { $0.id == id }) {
                draftTemplateName = custom.name
                draftTemplatePrompt = custom.prompt
                draftTemplateIcon = MeetingTemplates.normalizedCustomIcon(named: custom.icon)
                draftTemplateLanguage = custom.outputLanguage
            } else if let builtIn = MeetingTemplates.builtIns.first(where: { $0.id == id }) {
                draftTemplateName = builtIn.title
                draftTemplatePrompt = builtIn.promptBody
                draftTemplateIcon = MeetingTemplates.normalizedCustomIcon(named: builtIn.icon)
                draftTemplateLanguage = nil
            } else {
                selection = .newTemplate
            }
        }
    }

    private func saveDraft() {
        let trimmedName = draftTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = draftTemplatePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        showNameValidationError = trimmedName.isEmpty
        showPromptValidationError = trimmedPrompt.isEmpty
        guard !trimmedName.isEmpty, !trimmedPrompt.isEmpty else { return }

        if let id = selectedTemplateID {
            controller.updateCustomMeetingTemplate(
                id: id,
                name: trimmedName,
                prompt: trimmedPrompt,
                icon: draftTemplateIcon,
                outputLanguage: draftTemplateLanguage
            )
        } else {
            controller.createCustomMeetingTemplate(
                name: trimmedName,
                prompt: trimmedPrompt,
                icon: draftTemplateIcon,
                outputLanguage: draftTemplateLanguage
            )
            // Select the just-created template so further edits update it.
            if let created = controller.customMeetingTemplates().last {
                selection = .template(created.id)
            }
        }
    }

    private func clearValidationErrors() {
        showNameValidationError = false
        showPromptValidationError = false
    }
}
