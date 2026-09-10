import AppKit

enum MenuBarIconRenderer {

    static let options: [(id: String, label: String)] = [
        ("muesli", "Muesli Logo"),
        ("mic.fill", "Microphone"),
        ("waveform", "Waveform"),
        ("bubble.left.fill", "Bubble"),
        ("text.bubble", "Speech Bubble"),
        ("pencil.line", "Pencil"),
        ("brain.head.profile", "Brain"),
        ("sparkles", "Sparkles"),
        ("headphones", "Headphones"),
        ("person.wave.2", "Meeting"),
        ("character.bubble", "Character"),
        ("doc.text", "Document"),
    ]

    /// Returns a menu bar icon for the given choice.
    /// "muesli" loads the bundled M logo; anything else renders an SF Symbol.
    ///
    /// Never returns nil: this is the status bar item's icon, the app's only
    /// affordance back to its UI once the last window is closed (it's an
    /// `LSUIElement` app — no Dock icon). "muesli" isn't a real SF Symbol
    /// name, so if the bundled PNG fails to load, falling through to
    /// `NSImage(systemSymbolName: "muesli", ...)` below would silently
    /// return nil — a blank, invisible status item with no way back in.
    static func make(choice: String = "muesli") -> NSImage? {
        if choice == "muesli" {
            if let url = Bundle.main.url(forResource: "menu_m_template", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                return image
            }
            return fallbackSymbol
        }
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        if let image = NSImage(systemSymbolName: choice, accessibilityDescription: "Muesli")?
            .withSymbolConfiguration(config) {
            image.isTemplate = true
            return image
        }
        return fallbackSymbol
    }

    /// Last-resort icon so the status item is never blank — a guaranteed
    /// real SF Symbol, unlike the callers' own (possibly invalid) choice.
    private static var fallbackSymbol: NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let image = NSImage(systemSymbolName: "waveform.badge.microphone", accessibilityDescription: "Muesli")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }
}
