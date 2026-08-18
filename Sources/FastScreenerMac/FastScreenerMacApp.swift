import AppKit

// Explicit @main entry point instead of a bare main.swift: a top-level
// `let delegate = AppDelegate()` in main.swift is a global variable, and
// Swift 6's strict concurrency checker doesn't treat top-level code as
// implicitly MainActor-isolated just because AppDelegate is — it flagged
// it as "not concurrency-safe" (this showed up building via Xcode even
// though plain `swift build` let it slide). Wrapping everything in an
// explicitly @MainActor static func sidesteps the ambiguity entirely.
@main
struct FastScreenerMacApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
