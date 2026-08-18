import AppKit

// NSMenuItem needs a target-action pair; this wraps a closure so menu
// construction reads naturally instead of a pile of @objc handlers.
final class ClosureMenuItem: NSMenuItem {
    private var handler: (() -> Void)?

    convenience init(title: String, keyEquivalent: String = "", handler: @escaping () -> Void) {
        self.init(title: title, action: #selector(invoke), keyEquivalent: keyEquivalent)
        self.handler = handler
        self.target = self
    }

    @objc private func invoke() { handler?() }
}
