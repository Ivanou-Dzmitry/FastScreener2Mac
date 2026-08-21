import AppKit

// Mirrors the original's formFSHelp: a Settings-style window that just
// shows the shipped help text, read-only. Opened from the hamburger menu
// or F1, matching the original's mitHelp_Click / global F1 hook.
final class HelpWindow: NSWindow {
    convenience init() {
        self.init(contentRect: CGRect(x: 0, y: 0, width: 420, height: 560), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        title = "Help"
        isReleasedWhenClosed = false
        // Same reasoning as SettingsWindow: the main capture window is
        // .floating, so a plain-level window would render stuck behind it.
        level = .modalPanel
        minSize = CGSize(width: 320, height: 300)

        let scrollView = NSTextView.scrollableTextView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        guard let textView = scrollView.documentView as? NSTextView else { fatalError() }
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 12)
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.string = Self.loadHelpText()

        let closeButton = ActionButton(title: "Close") { [weak self] in self?.close() }
        let footerStack = NSStackView(views: [closeButton])
        footerStack.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 16, right: 20)
        footerStack.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(scrollView)
        root.addSubview(divider)
        root.addSubview(footerStack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: divider.topAnchor),

            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: footerStack.topAnchor),

            footerStack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footerStack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        contentView = root
    }

    private static func loadHelpText() -> String {
        guard let url = Bundle.module.url(forResource: "fs2_help", withExtension: "txt", subdirectory: "Resources"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Help text resource 'fs2_help.txt' was not found."
        }
        return text
    }
}
