import Foundation

/// One quick-prompt chip in the Insights composer: `label` is the short text
/// shown on the chip, `prompt` is the full question sent to the model and
/// shown in the chat as the user's message. Kept apart on purpose — chip
/// labels wide enough to read as a sentence make the whole row wrap into a
/// mess (task 1.2).
struct InsightsHint: Identifiable, Sendable {
    let id: String
    let label: String
    let icon: String
    let prompt: String
}

enum InsightsHints {
    /// Computed, not a cached `static let` — `tr()` must re-evaluate on
    /// every access so the labels follow the runtime language switch.
    static var all: [InsightsHint] {
        [
            InsightsHint(
                id: "commitments",
                label: tr("My tasks", "Мои задачи"),
                icon: "checklist",
                prompt: tr(
                    "What did I commit to doing? Gather my tasks and promises from these meetings, with the owner and deadline if it was mentioned.",
                    "Что я пообещал сделать? Собери мои задачи и обещания с этих встреч, с owner-ом и сроком, если он назывался."
                )
            ),
            InsightsHint(
                id: "open",
                label: tr("Open", "Нерешённое"),
                icon: "questionmark.circle",
                prompt: tr(
                    "What's still open and unresolved? Open questions and topics left hanging.",
                    "Что осталось нерешённым и не закрытым? Открытые вопросы и подвешенные темы."
                )
            ),
            InsightsHint(
                id: "decisions",
                label: tr("Decisions", "Решения"),
                icon: "checkmark.seal",
                prompt: tr(
                    "What specific decisions were made? Only what was actually decided.",
                    "Какие конкретные решения были приняты? Только то, что действительно решили."
                )
            ),
            InsightsHint(
                id: "waiting",
                label: tr("Waiting", "Кто ждёт"),
                icon: "person.crop.circle.badge.clock",
                prompt: tr(
                    "Who's waiting on a reply or action from me, and about what?",
                    "Кто ждёт ответа или действия от меня и по какому вопросу?"
                )
            ),
            InsightsHint(
                id: "recurring",
                label: tr("Recurring", "Повторы"),
                icon: "arrow.triangle.2.circlepath",
                prompt: tr(
                    "What topics keep recurring meeting after meeting and are still not closed?",
                    "Какие темы повторяются из встречи в встречу и до сих пор не закрыты?"
                )
            ),
            InsightsHint(
                id: "risks",
                label: tr("Risks", "Риски"),
                icon: "exclamationmark.triangle",
                prompt: tr(
                    "What risks, slipping deadlines, or warning signs came up?",
                    "Какие риски, срывы сроков и тревожные сигналы прозвучали?"
                )
            ),
        ]
    }
}
