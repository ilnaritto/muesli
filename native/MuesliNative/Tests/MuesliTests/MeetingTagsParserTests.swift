import Testing
import Foundation
@testable import MuesliNativeApp

@Suite("MeetingTagsParser")
struct MeetingTagsParserTests {

    @Test("parses an English Tags heading and strips the section")
    func parsesEnglishHeading() {
        let markdown = """
        ## Meeting Summary
        We discussed the Q3 roadmap.

        ## Tags
        product roadmap, q3 planning, budget
        """

        let result = MeetingTagsParser.parse(markdown)

        #expect(result.tags == ["product roadmap", "q3 planning", "budget"])
        #expect(!result.strippedMarkdown.contains("## Tags"))
        #expect(!result.strippedMarkdown.contains("product roadmap"))
        #expect(result.strippedMarkdown.contains("## Meeting Summary"))
    }

    @Test("parses a Russian Теги heading case-insensitively")
    func parsesRussianHeadingCaseInsensitive() {
        let markdown = """
        ## Сводка встречи
        Обсудили дорожную карту.

        ### теги
        дорожная карта, бюджет, клиент x
        """

        let result = MeetingTagsParser.parse(markdown)

        #expect(result.tags == ["дорожная карта", "бюджет", "клиент x"])
        #expect(!result.strippedMarkdown.lowercased().contains("теги"))
    }

    @Test("strips leading hashtags and bullets from noisy tag input")
    func stripsHashtagsAndBullets() {
        let markdown = """
        ## Tags
        - #product
        - #roadmap, ## budget
        """

        let result = MeetingTagsParser.parse(markdown)

        #expect(result.tags == ["product", "roadmap", "budget"])
    }

    @Test("caps at 6 tags, ignoring anything past the sixth")
    func capsTagCount() {
        let markdown = """
        ## Tags
        one, two, three, four, five, six, seven, eight
        """

        let result = MeetingTagsParser.parse(markdown)

        #expect(result.tags == ["one", "two", "three", "four", "five", "six"])
    }

    @Test("truncates a tag longer than 24 characters")
    func truncatesLongTag() {
        let longTag = String(repeating: "x", count: 40)
        let markdown = """
        ## Tags
        \(longTag), short tag
        """

        let result = MeetingTagsParser.parse(markdown)

        #expect(result.tags.count == 2)
        #expect(result.tags[0].count == MeetingTagsParser.maxTagLength)
        #expect(result.tags[1] == "short tag")
    }

    @Test("deduplicates tags case-insensitively, keeping first occurrence")
    func deduplicatesCaseInsensitively() {
        let markdown = """
        ## Tags
        Budget, budget, BUDGET, roadmap
        """

        let result = MeetingTagsParser.parse(markdown)

        #expect(result.tags == ["Budget", "roadmap"])
    }

    @Test("empty Tags section yields no tags and strips cleanly")
    func emptySectionYieldsNoTags() {
        let markdown = """
        ## Meeting Summary
        Nothing much happened.

        ## Tags

        """

        let result = MeetingTagsParser.parse(markdown)

        #expect(result.tags.isEmpty)
        #expect(result.strippedMarkdown == "## Meeting Summary\nNothing much happened.")
    }

    @Test("no Tags section at all leaves markdown untouched")
    func noSectionLeavesMarkdownUntouched() {
        let markdown = """
        ## Meeting Summary
        Just a summary, no tags requested.
        """

        let result = MeetingTagsParser.parse(markdown)

        #expect(result.tags.isEmpty)
        #expect(result.strippedMarkdown == markdown)
    }

    @Test("garbage-only tokens are dropped without crashing")
    func garbageTokensAreDropped() {
        let markdown = """
        ## Tags
        , , #, -, ,,,
        """

        let result = MeetingTagsParser.parse(markdown)

        #expect(result.tags.isEmpty)
    }
}
