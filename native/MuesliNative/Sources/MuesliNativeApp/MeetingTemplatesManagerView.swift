import SwiftUI
import MuesliCore

struct MeetingTemplatesManagerView: View {
    let appState: AppState
    let controller: MuesliController
    let onClose: () -> Void
    /// Opens with the "new template" editor already expanded.
    var startsCreating: Bool = false
    /// Rendered inside the Settings pane rather than as a sheet:
    /// no fixed size, no own background, no Done button.
    var isEmbedded: Bool = false

    @State private var isCreatingTemplate = false
    @State private var editingTemplateID: String?
    @State private var draftTemplateName = ""
    @State private var draftTemplatePrompt = ""
    @State private var draftTemplateIcon = MeetingTemplates.customIconFallback
    @State private var showNameValidationError = false
    @State private var showPromptValidationError = false
    @State private var templateToDelete: CustomMeetingTemplate?

    var body: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Manage Templates", "Управление шаблонами"))
                        .font(MuesliTheme.title2())
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(tr("Create reusable prompt-based note formats for meetings.", "Создавайте многоразовые форматы заметок на основе промптов для встреч."))
                        .font(MuesliTheme.callout())
                        .foregroundStyle(MuesliTheme.textSecondary)
                }

                Spacer()

                HStack(spacing: MuesliTheme.spacing8) {
                    if isCreatingTemplate || editingTemplateID != nil {
                        actionButton(tr("Cancel", "Отмена"), systemImage: "xmark") {
                            resetTemplateEditor()
                        }
                    } else {
                        actionButton(tr("New template", "Новый шаблон"), systemImage: "plus") {
                            beginCreatingTemplate()
                        }
                    }

                    if !isEmbedded {
                        actionButton(tr("Done", "Готово"), systemImage: "checkmark") {
                            onClose()
                        }
                        .disabled(isEditingTemplateInProgress)
                        .opacity(isEditingTemplateInProgress ? 0.55 : 1)
                        .help(isEditingTemplateInProgress ? tr("Finish or cancel template editing before closing.", "Завершите или отмените редактирование шаблона перед закрытием.") : tr("Close template manager", "Закрыть менеджер шаблонов"))
                    }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                    if controller.customMeetingTemplates().isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: MuesliTheme.spacing8) {
                            ForEach(controller.customMeetingTemplates()) { template in
                                customTemplateRow(template)
                            }
                        }
                    }

                    if isCreatingTemplate || editingTemplateID != nil {
                        customTemplateEditor
                    }
                }
                .padding(.bottom, MuesliTheme.spacing4)
            }
        }
        .padding(isEmbedded ? 0 : MuesliTheme.spacing24)
        .frame(minWidth: isEmbedded ? nil : 760, minHeight: isEmbedded ? nil : 520)
        .background(isEmbedded ? Color.clear : MuesliTheme.backgroundBase)
        .onAppear {
            if startsCreating {
                beginCreatingTemplate()
                appState.meetingTemplatesManagerStartsCreating = false
            }
        }
        .alert(
            tr("Delete \"\(templateToDelete?.name ?? "")\"?", "Удалить \"\(templateToDelete?.name ?? "")\"?"),
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
                if editingTemplateID == template.id {
                    resetTemplateEditor()
                }
                templateToDelete = nil
            }
        } message: {
            Text(tr("This template will be permanently removed. Existing meetings will keep their saved template snapshot.", "Этот шаблон будет удалён навсегда. Существующие встречи сохранят свой снимок шаблона."))
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Image(systemName: MeetingTemplates.customIconFallback)
                .font(.system(size: 11))
                .foregroundStyle(MuesliTheme.textTertiary)
            Text(tr("No custom templates yet.", "Пока нет пользовательских шаблонов."))
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textTertiary)
        }
        .padding(.horizontal, MuesliTheme.spacing12)
        .padding(.vertical, 10)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func customTemplateRow(_ template: CustomMeetingTemplate) -> some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: template.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(MuesliTheme.accent)
                        Text(template.name)
                            .font(MuesliTheme.captionMedium())
                            .foregroundStyle(MuesliTheme.textPrimary)
                    }
                    Text(template.prompt)
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                HStack(spacing: MuesliTheme.spacing8) {
                    actionButton(tr("Edit", "Изменить"), systemImage: "pencil") {
                        beginEditingTemplate(template)
                    }
                    actionButton(tr("Delete", "Удалить"), systemImage: "trash", role: .destructive) {
                        templateToDelete = template
                    }
                }
            }
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var customTemplateEditor: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            Text(isCreatingTemplate ? tr("New template", "Новый шаблон") : tr("Edit template", "Изменить шаблон"))
                .font(MuesliTheme.captionMedium())
                .foregroundStyle(MuesliTheme.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Name", "Название"))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
                TextField(tr("Customer follow-up", "Встреча с клиентом"), text: $draftTemplateName)
                    .textFieldStyle(.roundedBorder)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                showNameValidationError ? MuesliTheme.recording.opacity(0.75) : .clear,
                                lineWidth: 1
                            )
                    }
                    .onChange(of: draftTemplateName) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            showNameValidationError = false
                        }
                    }
                if showNameValidationError {
                    Text(tr("Enter a template name.", "Введите название шаблона."))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.recording)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Icon", "Значок"))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
                customIconPicker
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Prompt", "Промпт"))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
                TextEditor(text: $draftTemplatePrompt)
                    .font(.system(size: 12))
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .padding(MuesliTheme.spacing8)
                    .background(MuesliTheme.backgroundBase)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
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
                    Text(tr("Enter the prompt instructions for this template.", "Введите инструкции промпта для этого шаблона."))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.recording)
                }
            }

            HStack {
                Spacer()
                actionButton(
                    isCreatingTemplate ? tr("Create template", "Создать шаблон") : tr("Save changes", "Сохранить изменения"),
                    systemImage: isCreatingTemplate ? "plus.circle" : "checkmark.circle"
                ) {
                    saveTemplateEditor()
                }
            }
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.surfacePrimary.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private func beginCreatingTemplate() {
        isCreatingTemplate = true
        editingTemplateID = nil
        draftTemplateName = ""
        draftTemplatePrompt = ""
        draftTemplateIcon = MeetingTemplates.customIconFallback
        clearValidationErrors()
    }

    private func beginEditingTemplate(_ template: CustomMeetingTemplate) {
        isCreatingTemplate = false
        editingTemplateID = template.id
        draftTemplateName = template.name
        draftTemplatePrompt = template.prompt
        draftTemplateIcon = MeetingTemplates.normalizedCustomIcon(named: template.icon)
        clearValidationErrors()
    }

    private func resetTemplateEditor() {
        isCreatingTemplate = false
        editingTemplateID = nil
        draftTemplateName = ""
        draftTemplatePrompt = ""
        draftTemplateIcon = MeetingTemplates.customIconFallback
        clearValidationErrors()
    }

    private func saveTemplateEditor() {
        let trimmedName = draftTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = draftTemplatePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        showNameValidationError = trimmedName.isEmpty
        showPromptValidationError = trimmedPrompt.isEmpty
        guard !trimmedName.isEmpty, !trimmedPrompt.isEmpty else { return }

        if let editingTemplateID {
            controller.updateCustomMeetingTemplate(
                id: editingTemplateID,
                name: trimmedName,
                prompt: trimmedPrompt,
                icon: draftTemplateIcon
            )
        } else {
            controller.createCustomMeetingTemplate(
                name: trimmedName,
                prompt: trimmedPrompt,
                icon: draftTemplateIcon
            )
        }
        resetTemplateEditor()
    }

    private var isEditingTemplateInProgress: Bool {
        isCreatingTemplate || editingTemplateID != nil
    }

    private func clearValidationErrors() {
        showNameValidationError = false
        showPromptValidationError = false
    }

    @ViewBuilder
    private var customIconPicker: some View {
        let columns = [
            GridItem(.adaptive(minimum: 36, maximum: 36), spacing: 6)
        ]

        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack(spacing: MuesliTheme.spacing8) {
                Image(systemName: draftTemplateIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MuesliTheme.accent)
                    .frame(width: 24, height: 24)
                    .background(MuesliTheme.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                Text(selectedIconLabel)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(MeetingTemplates.customIconOptions) { icon in
                    Button {
                        draftTemplateIcon = icon.symbolName
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedIconLabel: String {
        MeetingTemplates.customIconOptions.first(where: { $0.symbolName == draftTemplateIcon })?.label ?? tr("Custom", "Свой")
    }

    @ViewBuilder
    private func actionButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let isDestructive = role == .destructive
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(isDestructive ? MuesliTheme.recording : MuesliTheme.textPrimary)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 7)
            .background(isDestructive ? MuesliTheme.recording.opacity(0.1) : MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(
                        isDestructive ? MuesliTheme.recording.opacity(0.2) : MuesliTheme.surfaceBorder,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
