import AppKit
import MuesliCore

@main
@MainActor
enum MuesliMain {
    static func main() {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        application.delegate = appDelegate
        // A regular activation policy keeps a Dock icon (and Cmd+Tab entry)
        // at all times. Muesli used to run as a pure background/menu-bar
        // accessory (.accessory) with a Dock icon only while a window was
        // open — closing the last window made the app vanish from the Dock
        // entirely, leaving the small menu-bar glyph as the only way back
        // in. That's not how most people expect to relaunch a Mac app, and
        // real users reported being unable to find Muesli again after
        // closing it. A persistent Dock icon fixes that the same way any
        // ordinary app works, at the cost of Muesli no longer feeling like
        // a pure background utility.
        application.setActivationPolicy(.regular)
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}
