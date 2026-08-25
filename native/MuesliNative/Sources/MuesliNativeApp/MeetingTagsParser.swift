import Foundation

/// Extracts the `## Tags` / `## Теги` section that the Auto template's prompt
/// asks the model to append, and strips it out of the rendered markdown so it
/// isn't shown twice (once as capsules, once as text at the bottom).
enum MeetingTagsParser {
    static let maxTagCount = 6
    static let maxTagLength = 24

    private static let sectionHeaderNames: Set<String> = ["tags", "теги"]

    struct Result {
        let tags: [String]
        /// The input markdown with the tags section removed. Equal to the
        /// input when no tags section was found.
        let strippedMarkdown: String
    }

    static func parse(_ markdown: String) -> Result {
        let lines = markdown.components(separatedBy: "\n")

        guard let headingIndex = lines.firstIndex(where: isTagsHeading) else {
            return Result(tags: [], strippedMarkdown: markdown)
        }

        var endIndex = lines.count
        for index in (headingIndex + 1)..<lines.count {
            if isHeadingLine(lines[index]) {
                endIndex = index
                break
            }
        }

        let bodyLines = lines[(headingIndex + 1)..<endIndex]
        let tags = parseTags(from: bodyLines.joined(separator: "\n"))

        var remainingLines = Array(lines[..<headingIndex]) + Array(lines[endIndex...])
        // Trim the blank line(s) left behind where the section used to be.
        while remainingLines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            remainingLines.removeLast()
        }
        let strippedMarkdown = remainingLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Result(tags: tags, strippedMarkdown: strippedMarkdown)
    }

    private static func isHeadingLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
    }

    private static func isTagsHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return false }
        let title = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        return sectionHeaderNames.contains(title.lowercased())
    }

    private static func parseTags(from body: String) -> [String] {
        let rawTokens = body
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))

        var seenLowercased = Set<String>()
        var tags: [String] = []

        for rawToken in rawTokens {
            guard tags.count < maxTagCount else { break }

            var token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
            // Strip a leading bullet ("- tag") and any leading hashtags ("#tag").
            if token.hasPrefix("- ") {
                token = String(token.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
            while token.hasPrefix("#") {
                token = String(token.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            // Drop a bare "Tags:" / "Теги:" label if the model echoed it inline.
            for label in sectionHeaderNames {
                if token.lowercased().hasPrefix(label + ":") {
                    token = String(token.dropFirst(label.count + 1)).trimmingCharacters(in: .whitespaces)
                }
            }

            // Drop pure-punctuation noise (e.g. a bare "-" left after bullet
            // stripping) — a tag must contain at least one letter or digit.
            guard token.rangeOfCharacter(from: .alphanumerics) != nil else { continue }
            if token.count > maxTagLength {
                token = String(token.prefix(maxTagLength)).trimmingCharacters(in: .whitespaces)
            }
            guard !token.isEmpty else { continue }

            let dedupeKey = token.lowercased()
            guard !seenLowercased.contains(dedupeKey) else { continue }
            seenLowercased.insert(dedupeKey)
            tags.append(token)
        }

        return tags
    }
}
