import Testing
@testable import MuesliNativeApp

@Suite("DictionarySuggestionPromptController")
struct DictionarySuggestionPromptControllerTests {
    @Test("Auto-dismiss decision is made when timer fires")
    @MainActor
    func autoDismissDecisionIsMadeWhenTimerFires() {
        #expect(DictionarySuggestionPromptController.shouldAutoDismissFromTimer(isPausedWhenTimerFires: false))
        #expect(!DictionarySuggestionPromptController.shouldAutoDismissFromTimer(isPausedWhenTimerFires: true))
    }
}
