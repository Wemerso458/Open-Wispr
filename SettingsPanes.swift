// The Dictionary pane (word replacements, manual + auto-learned) and the
// Activity pane (recent dictations + the log).
import Cocoa

// MARK: - Shared bits

/// Rounded, clipped container for a table or text view.
final class Panel: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = Theme.cardFill.cgColor
        layer?.borderColor = Theme.cardStroke.cgColor
    }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

/// Table that reports Delete/Backspace so rows can be removed from the keyboard.
final class KeyTableView: NSTableView {
    var onDeleteKey: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        let del = event.charactersIgnoringModifiers?.unicodeScalars.first
        if del == UnicodeScalar(NSDeleteCharacter)! || del == UnicodeScalar(NSBackspaceCharacter)! {
            onDeleteKey?()
            return
        }
        super.keyDown(with: event)
    }
}

/// Text field that remembers which rule and column it edits.
final class RuleField: NSTextField {
    var ruleID = ""
    var isFromColumn = true
}

/// Checkbox that remembers its rule.
final class RuleCheck: NSButton {
    var ruleID = ""
}

// MARK: - Dictionary

final class DictionaryPane: PaneView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {

    private let fromField = Theme.field("Heard as…  e.g. Rekki")
    private let toField = Theme.field("Replace with…  e.g. ReqKey")
    private let search = NSSearchField()
    private let filter = NSSegmentedControl(labels: ["All", "Typed", "Learned"],
                                            trackingMode: .selectOne, target: nil, action: nil)
    private let table = KeyTableView()
    private let countLabel = Theme.dimLine("", 11)
    private let emptyLabel = Theme.dim("", 12)
    private var shown: [ReplacementRule] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        reload()
        NotificationCenter.default.addObserver(self, selector: #selector(reload),
                                               name: .owRulesChanged, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    private func build() {
        let header = makePaneHeader("Dictionary",
                                    "Words to swap after every transcription — names, product names, anything the model keeps mishearing.")

        // --- add bar
        let addCard = Card()
        let arrow = NSImageView(image: Theme.symbol("arrow.right", 11, .medium) ?? NSImage())
        arrow.contentTintColor = .tertiaryLabelColor
        arrow.translatesAutoresizingMaskIntoConstraints = false
        arrow.widthAnchor.constraint(equalToConstant: 16).isActive = true
        fromField.target = self
        fromField.action = #selector(addRule)
        toField.target = self
        toField.action = #selector(addRule)
        let addButton = Theme.accentButton("Add", target: self, action: #selector(addRule))
        let bar = Theme.hstack([fromField, arrow, toField, addButton], spacing: 8)
        fromField.setContentHuggingPriority(.init(1), for: .horizontal)
        toField.setContentHuggingPriority(.init(1), for: .horizontal)
        fromField.translatesAutoresizingMaskIntoConstraints = false
        toField.translatesAutoresizingMaskIntoConstraints = false
        toField.widthAnchor.constraint(equalTo: fromField.widthAnchor).isActive = true
        addCard.add(bar)
        addCard.add(Theme.dim("Matched as whole words, ignoring case — “rekki” and “Rekki” both become “ReqKey”. Phrases work too.", 11))

        // --- toolbar
        search.placeholderString = "Filter"
        search.font = .systemFont(ofSize: 12)
        search.target = self
        search.action = #selector(reload)
        search.translatesAutoresizingMaskIntoConstraints = false
        search.widthAnchor.constraint(equalToConstant: 190).isActive = true
        filter.selectedSegment = 0
        filter.target = self
        filter.action = #selector(reload)
        filter.segmentStyle = .rounded
        let forget = Theme.plainButton("Forget learned…", target: self, action: #selector(forgetLearned))
        let toolbar = Theme.hstack([filter, search, Theme.spacer(), countLabel, forget], spacing: 10)

        // --- table
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 30
        table.gridStyleMask = []
        table.style = .fullWidth
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = .clear
        table.headerView = NSTableHeaderView()
        table.allowsMultipleSelection = true
        table.onDeleteKey = { [weak self] in self?.deleteSelected() }
        // Default is 17pt per gap, which pushes the last column outside the clip view.
        table.intercellSpacing = NSSize(width: 8, height: 0)

        // Only the two text columns may absorb extra width; capping the rest keeps
        // the delete button from being pushed off the right edge.
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        func column(_ id: String, _ title: String, _ width: CGFloat,
                    min: CGFloat? = nil, max: CGFloat? = nil) -> NSTableColumn {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title
            c.width = width
            c.minWidth = min ?? width
            c.maxWidth = max ?? width
            return c
        }
        table.addTableColumn(column("from", "Heard", 190, min: 120, max: 460))
        table.addTableColumn(column("to", "Replace with", 190, min: 120, max: 460))
        table.addTableColumn(column("source", "Source", 66))
        table.addTableColumn(column("case", "Aa", 34))
        table.addTableColumn(column("hits", "Uses", 46))
        table.addTableColumn(column("del", "", 28))

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let panel = Panel()
        scroll.fill(panel)
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: panel.centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: panel.widthAnchor, constant: -60),
        ])

        // --- layout
        for v in [header, addCard, toolbar, panel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PANE_INSET),
                v.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PANE_INSET),
            ])
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 46),
            addCard.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            toolbar.topAnchor.constraint(equalTo: addCard.bottomAnchor, constant: 16),
            panel.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 12),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),
        ])
    }

    override func paneAppeared() { reload() }

    // MARK: Data

    @objc private func reload() {
        let all = ReplacementStore.shared.rules.sorted { $0.created > $1.created }
        let mode = filter.selectedSegment
        let needle = search.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        shown = all.filter { rule in
            if mode == 1 && rule.learned { return false }
            if mode == 2 && !rule.learned { return false }
            if !needle.isEmpty {
                return rule.from.lowercased().contains(needle) || rule.to.lowercased().contains(needle)
            }
            return true
        }
        table.reloadData()

        let learned = all.filter { $0.learned }.count
        countLabel.stringValue = all.isEmpty
            ? ""
            : "\(all.count) total · \(learned) learned"
        emptyLabel.isHidden = !shown.isEmpty
        emptyLabel.stringValue = all.isEmpty
            ? "No replacements yet.\nAdd one above — or just fix a word right after a paste and it lands here on its own."
            : "Nothing matches this filter."
        emptyLabel.alignment = .center
        SettingsUI.shared.refreshChip()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < shown.count, let id = tableColumn?.identifier.rawValue else { return nil }
        let rule = shown[row]

        switch id {
        case "from", "to":
            let field = RuleField()
            field.stringValue = id == "from" ? rule.from : rule.to
            field.ruleID = rule.id
            field.isFromColumn = (id == "from")
            field.isBordered = false
            field.drawsBackground = false
            field.isEditable = true
            field.delegate = self
            field.font = id == "to"
                ? .systemFont(ofSize: 12.5, weight: .medium)
                : .systemFont(ofSize: 12.5)
            field.textColor = id == "to" ? .labelColor : .secondaryLabelColor
            field.lineBreakMode = .byTruncatingTail
            let cell = NSTableCellView()
            cell.addSubview(field)
            cell.textField = field
            field.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell

        case "source":
            let text = Theme.dimLine(rule.learned ? "Learned" : "Typed", 10.5)
            text.textColor = rule.learned ? Theme.violet : .tertiaryLabelColor
            text.font = .systemFont(ofSize: 10.5, weight: .semibold)
            return wrap(text, leading: 2)

        case "case":
            let check = RuleCheck(checkboxWithTitle: "", target: self, action: #selector(toggleCase(_:)))
            check.ruleID = rule.id
            check.state = rule.caseSensitive ? .on : .off
            check.toolTip = "Match capitalisation exactly"
            return wrap(check, leading: 6)

        case "hits":
            let text = Theme.dimLine(rule.hits == 0 ? "–" : "\(rule.hits)", 11.5)
            text.alignment = .right
            return wrap(text, leading: 0, trailing: 8)

        case "del":
            let b = NSButton()
            b.image = Theme.symbol("xmark", 9.5, .semibold)
            b.isBordered = false
            b.bezelStyle = .inline
            b.contentTintColor = .tertiaryLabelColor
            b.identifier = NSUserInterfaceItemIdentifier(rule.id)
            b.target = self
            b.action = #selector(deleteRow(_:))
            b.toolTip = "Remove this replacement"
            return wrap(b, leading: 4)

        default:
            return nil
        }
    }

    private func wrap(_ view: NSView, leading: CGFloat, trailing: CGFloat = -2) -> NSTableCellView {
        let cell = NSTableCellView()
        view.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: leading),
            view.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: trailing),
            view.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    // MARK: Actions

    @objc private func addRule() {
        let from = fromField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = toField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty else {
            NSSound.beep()
            return
        }
        ReplacementStore.shared.upsert(from: from, to: to)
        Config.shared.log("Replacement added: \(from) -> \(to)")
        fromField.stringValue = ""
        toField.stringValue = ""
        window?.makeFirstResponder(fromField)
        reload()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? RuleField else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { reload(); return }
        if field.isFromColumn {
            ReplacementStore.shared.update(id: field.ruleID, from: value)
        } else {
            ReplacementStore.shared.update(id: field.ruleID, to: value)
        }
    }

    @objc private func toggleCase(_ sender: RuleCheck) {
        ReplacementStore.shared.setCaseSensitive(id: sender.ruleID, sender.state == .on)
    }

    @objc private func deleteRow(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        ReplacementStore.shared.remove(id: id)
        reload()
    }

    private func deleteSelected() {
        let ids = table.selectedRowIndexes.compactMap { $0 < shown.count ? shown[$0].id : nil }
        guard !ids.isEmpty else { return }
        ids.forEach { ReplacementStore.shared.remove(id: $0) }
        reload()
    }

    @objc private func forgetLearned() {
        let learned = ReplacementStore.shared.rules.filter { $0.learned }
        guard !learned.isEmpty else {
            NSSound.beep()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Forget \(learned.count) learned replacement\(learned.count == 1 ? "" : "s")?"
        alert.informativeText = "Replacements you typed yourself are kept."
        alert.addButton(withTitle: "Forget")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            ReplacementStore.shared.removeAllLearned()
            reload()
        }
    }
}

// MARK: - Activity

final class ActivityPane: PaneView, NSTableViewDataSource, NSTableViewDelegate {

    private let table = NSTableView()
    private let logView = NSTextView()
    private var entries: [HistoryEntry] = []
    private var timer: Timer?
    private let stamp = DateFormatter()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stamp.dateFormat = "MMM d, HH:mm:ss"
        build()
        reload()
        NotificationCenter.default.addObserver(self, selector: #selector(reload),
                                               name: .owHistoryChanged, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    private func build() {
        let header = makePaneHeader("Activity", "Everything you've dictated in this install, and what the app logged while doing it.")

        // --- history table
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 28
        table.gridStyleMask = []
        table.style = .fullWidth
        table.backgroundColor = .clear
        table.usesAlternatingRowBackgroundColors = false
        table.headerView = NSTableHeaderView()
        table.intercellSpacing = NSSize(width: 8, height: 0)
        table.target = self
        table.doubleAction = #selector(copyRow)

        let when = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("when"))
        when.title = "When"; when.width = 118; when.minWidth = 100
        let text = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("text"))
        text.title = "Transcript"; text.width = 400; text.minWidth = 200
        let len = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("len"))
        len.title = "Chars"; len.width = 52
        table.addTableColumn(when)
        table.addTableColumn(text)
        table.addTableColumn(len)

        let tableScroll = NSScrollView()
        tableScroll.documentView = table
        tableScroll.drawsBackground = false
        tableScroll.hasVerticalScroller = true
        tableScroll.autohidesScrollers = true
        let tablePanel = Panel()
        tableScroll.fill(tablePanel)

        let historyHead = Theme.hstack([
            Theme.line("Recent dictations", 12.5, .semibold),
            Theme.dimLine("double-click to copy", 11),
            Theme.spacer(),
            Theme.plainButton("Clear history", target: self, action: #selector(clearHistory)),
        ], spacing: 8)

        // --- log
        logView.isEditable = false
        logView.drawsBackground = false
        logView.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        logView.textColor = .secondaryLabelColor
        logView.textContainerInset = NSSize(width: 8, height: 8)
        let logScroll = NSScrollView()
        logScroll.documentView = logView
        logScroll.drawsBackground = false
        logScroll.hasVerticalScroller = true
        logView.autoresizingMask = [.width]
        logView.minSize = NSSize(width: 0, height: 0)
        logView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        logView.isVerticallyResizable = true
        logView.isHorizontallyResizable = false
        logView.textContainer?.widthTracksTextView = true
        let logPanel = Panel()
        logScroll.fill(logPanel)

        let logHead = Theme.hstack([
            Theme.line("Log", 12.5, .semibold),
            Theme.dimLine("~/.config/openwispr/openwispr.log", 11),
            Theme.spacer(),
            Theme.plainButton("Reveal", target: self, action: #selector(revealLog)),
            Theme.plainButton("Clear", target: self, action: #selector(clearLog)),
        ], spacing: 8)

        for v in [header, historyHead, tablePanel, logHead, logPanel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PANE_INSET),
                v.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PANE_INSET),
            ])
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 46),
            historyHead.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
            tablePanel.topAnchor.constraint(equalTo: historyHead.bottomAnchor, constant: 8),
            logHead.topAnchor.constraint(equalTo: tablePanel.bottomAnchor, constant: 18),
            logPanel.topAnchor.constraint(equalTo: logHead.bottomAnchor, constant: 8),
            logPanel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),
            // history gets the top ~45% of the space, the log the rest
            tablePanel.heightAnchor.constraint(equalTo: logPanel.heightAnchor, multiplier: 0.8),
        ])
    }

    override func paneAppeared() {
        reload()
        refreshLog(scrollToEnd: true)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.refreshLog(scrollToEnd: false)
        }
    }

    override func paneDisappeared() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func reload() {
        entries = HistoryStore.shared.entries
        table.reloadData()
    }

    private func refreshLog(scrollToEnd: Bool) {
        let text = Config.shared.logTail()
        guard text != logView.string else { return }
        let atBottom = scrollToEnd || isLogAtBottom()
        logView.string = text
        if atBottom { logView.scrollToEndOfDocument(nil) }
    }

    private func isLogAtBottom() -> Bool {
        guard let clip = logView.enclosingScrollView?.contentView else { return true }
        let visibleMax = clip.bounds.maxY
        return visibleMax >= logView.bounds.height - 40
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < entries.count, let id = tableColumn?.identifier.rawValue else { return nil }
        let e = entries[row]
        let field: NSTextField
        switch id {
        case "when":
            field = Theme.dimLine(stamp.string(from: e.date), 11)
        case "len":
            field = Theme.dimLine("\(e.text.count)", 11)
            field.alignment = .right
        default:
            field = Theme.line(e.text.replacingOccurrences(of: "\n", with: " "), 12)
        }
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        field.toolTip = e.text
        let cell = NSTableCellView()
        cell.textField = field
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    @objc private func copyRow() {
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        guard row >= 0, row < entries.count else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entries[row].text, forType: .string)
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear dictation history?"
        alert.informativeText = "This only removes the list shown here. Your replacements are kept."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            HistoryStore.shared.clear()
            reload()
        }
    }

    @objc private func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([Config.shared.logURL])
    }

    @objc private func clearLog() {
        Config.shared.clearLog()
        refreshLog(scrollToEnd: true)
    }
}
