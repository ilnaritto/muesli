import AppKit
import MuesliCore

@MainActor
private enum MuesliAppDelegateHolder {
    static let shared = AppDelegate()
}

@main
@MainActor
enum MuesliMain {
    static func main() {
        let application = NSApplication.shared
        let appDelegate = MuesliAppDelegateHolder.shared
        application.delegate = appDelegate
        application.setActivationPolicy(.accessory)
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}
