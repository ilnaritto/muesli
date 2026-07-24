import Foundation
import LLM

/// A downloadable local LLM used for fully on-device meeting summarization.
///
/// Reuses the bundled llama.cpp runtime (LLM.swift) — the same engine that
/// powers the dictation post-processor — so summaries run entirely on the
/// user's Mac with no cloud calls and no API tokens.
struct LocalSummaryModelOption: Identifiable, Equatable {
    let id: String
    let label: String
    let sizeLabel: String
    let description: String
    let downloadURL: URL
    let filename: String

    var cacheDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/muesli/models/summary-\(id)", isDirectory: true)
    }

    var modelURL: URL {
        cacheDirectory.appendingPathComponent(filename)
    }

    var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: modelURL.path)
    }

    /// T-lite-it-1.0 — a Russian-tuned Qwen2.5-7B from T-Bank, quantized to
    /// Q4_K_M GGUF (~4.7 GB). Strong Russian meeting summaries, fits 16 GB Macs
    /// because summarization runs after recording stops.
    static let tLite = LocalSummaryModelOption(
        id: "t-lite-it-1.0-q4km",
        label: "T-lite 7B",
        sizeLabel: "~4.7 GB",
        description: "Локальная суммаризация встреч на русском — без интернета и токенов. Дообученная Qwen2.5-7B (Т-Банк), работает на вашем Mac через llama.cpp.",
        downloadURL: URL(string: "https://huggingface.co/mradermacher/T-lite-it-1.0-GGUF/resolve/main/T-lite-it-1.0.Q4_K_M.gguf")!,
        filename: "T-lite-it-1.0.Q4_K_M.gguf"
    )

    static let all: [LocalSummaryModelOption] = [.tLite]
    static let defaultOption: LocalSummaryModelOption = .tLite

    static func resolve(id: String) -> LocalSummaryModelOption {
        all.first { $0.id == id } ?? defaultOption
    }

    static var isAnyDownloaded: Bool {
        all.contains(where: \.isDownloaded)
    }
}

/// Trims model chat/control artifacts while preserving the Markdown structure
/// of a generated summary (unlike the dictation cleaner, which flattens it).
enum LocalSummaryOutputCleaner {
    static func clean(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: #"<think>[\s\S]*?</think>"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"<\|im_(?:start|end)\|>"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)\[end of text\]"#,
            with: "",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Loads the local GGUF summary model on demand, generates one summary, then
/// releases the model so a 7B model does not stay resident in RAM between
/// meetings (important on 16 GB Macs). Serialized as an actor because the
/// underlying llama.cpp context is not reentrant-safe.
@available(macOS 15, *)
actor LocalSummaryEngine {
    /// Input + output token budget. Qwen2.5-7B supports far more, but 8k keeps
    /// the KV cache modest so summarization stays comfortable on 16 GB.
    static let contextTokens: Int32 = 8192

    private let modelURL: URL

    init(modelURL: URL) {
        self.modelURL = modelURL
    }

    func summarize(systemPrompt: String, userPrompt: String) async throws -> String {
        try Task.checkCancellation()
        guard let bot = LLM(
            from: modelURL,
            seed: 42,
            topK: 40,
            topP: 0.95,
            temp: 0.3,
            repeatPenalty: 1.1,
            repetitionLookback: 64,
            historyLimit: 0,
            maxTokenCount: Self.contextTokens
        ) else {
            throw NSError(domain: "LocalSummaryEngine", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to load local summary model at \(modelURL.path)",
            ])
        }
        // `bot` is released when this method returns, freeing the llama context.
        bot.useResolvedTemplate(systemPrompt: systemPrompt)
        try Task.checkCancellation()
        await bot.respond(to: userPrompt, thinking: .none)
        return LocalSummaryOutputCleaner.clean(bot.output)
    }
}
