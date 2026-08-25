import SwiftUI
import MuesliCore

/// One selectable row in a `ModelPicker`.
struct ModelPickerItem: Identifiable, Equatable {
    let id: String
    let title: String
}

/// Replaces the old `settingsMenu`/`FixedWidthPopUp` pickers everywhere the
/// app lets the user choose a model: shows the models connected for one role
/// plus a "Manage Models…" exit hatch into Settings → Models. When nothing
/// is connected the pill reads "Model not selected" in the accent color and
/// the only menu item routes to Models — never a silent no-op or a network
/// error from picking a phantom selection.
struct ModelPicker: View {
    let items: [ModelPickerItem]
    let selectedID: String?
    let onSelect: (String) -> Void
    let onManage: () -> Void

    private var selectedTitle: String? {
        items.first(where: { $0.id == selectedID })?.title
    }

    var body: some View {
        Menu {
            ForEach(items) { item in
                Button {
                    onSelect(item.id)
                } label: {
                    if item.id == selectedID {
                        Label(item.title, systemImage: "checkmark")
                    } else {
                        Text(item.title)
                    }
                }
            }
            if !items.isEmpty {
                Divider()
            }
            Button(tr("Manage Models…", "Управление моделями…"), action: onManage)
        } label: {
            HStack(spacing: 6) {
                Text(selectedTitle ?? tr("Model not selected", "Модель не выбрана"))
                    .font(.system(size: 13))
                    .foregroundStyle(selectedTitle == nil ? MuesliTheme.accent : MuesliTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 160, maxWidth: .infinity, minHeight: 26, maxHeight: 26)
            .background(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall).fill(MuesliTheme.backgroundBase))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }
}
