import AppKit

// A borderless popup panel listing filename-history matches under the
// filename field. The original's txtbName AutoComplete drops its list
// down the instant you type — no separate button involved — but
// NSComboBox's built-in popup only opens via its arrow button or the
// down-arrow key, so this is a small hand-rolled equivalent instead of
// relying on that.
@MainActor
final class FilenameSuggestionPanel: NSObject {
    var onSelect: ((String) -> Void)?

    private var panel: NSPanel?
    private var tableView: NSTableView!
    private var items: [String] = []
    private let rowHeight: CGFloat = 26
    private let maxVisibleRows = 6

    func show(matches: [String], below field: NSView, in parentWindow: NSWindow, openUpward: Bool) {
        items = matches
        if panel == nil { setupPanel() }
        tableView.reloadData()

        let fieldFrameInWindow = field.convert(field.bounds, to: nil)
        let fieldFrameOnScreen = parentWindow.convertToScreen(fieldFrameInWindow)
        let visibleRows = min(items.count, maxVisibleRows)
        let height = CGFloat(visibleRows) * rowHeight
        let y = openUpward ? fieldFrameOnScreen.maxY : fieldFrameOnScreen.minY - height
        let frame = CGRect(x: fieldFrameOnScreen.minX, y: y, width: fieldFrameOnScreen.width, height: height)

        // NSTableView doesn't auto-size its own frame to numberOfRows *
        // rowHeight — without this the document view stayed at its
        // initial .zero frame, so the scroll view's content height never
        // matched the real row count and the last row was clipped unless
        // you scrolled to reveal it.
        tableView.frame = CGRect(x: 0, y: 0, width: frame.width, height: CGFloat(items.count) * rowHeight)
        tableView.tableColumns.first?.width = frame.width

        panel?.setFrame(frame, display: true)
        if let panel, panel.parent == nil {
            parentWindow.addChildWindow(panel, ordered: .above)
        }
        panel?.orderFront(nil)
    }

    func hide() {
        guard let panel, panel.parent != nil || panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func setupPanel() {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = true
        p.backgroundColor = NSColor(calibratedWhite: 0.15, alpha: 1)
        p.hasShadow = true
        p.level = .popUpMenu
        p.isReleasedWhenClosed = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let table = NSTableView()
        table.headerView = nil
        table.rowHeight = rowHeight
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        table.target = self
        table.action = #selector(rowClicked)
        table.dataSource = self
        table.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.width = 240
        table.addTableColumn(column)

        scrollView.documentView = table
        p.contentView = scrollView

        tableView = table
        panel = p
    }

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        onSelect?(items[row])
    }
}

extension FilenameSuggestionPanel: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField) ?? {
            let field = NSTextField(labelWithString: "")
            field.identifier = identifier
            field.font = .systemFont(ofSize: 11)
            field.textColor = .white
            field.drawsBackground = false
            field.isBordered = false
            field.isEditable = false
            return field
        }()
        cell.stringValue = items[row]
        return cell
    }
}
