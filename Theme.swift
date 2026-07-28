// Shared look & feel for the settings window: colours, text helpers, and the
// handful of composite views (cards, toggle rows, status rows) the panes are built from.
import Cocoa

enum Theme {

    static func dyn(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    // The pill's cyan -> violet -> pink sweep, reused as the app's accent.
    static let cyan   = NSColor(srgbRed: 0.13, green: 0.83, blue: 0.93, alpha: 1)
    static let violet = NSColor(srgbRed: 0.55, green: 0.36, blue: 0.96, alpha: 1)
    static let pink   = NSColor(srgbRed: 0.96, green: 0.45, blue: 0.71, alpha: 1)
    static let teal   = NSColor(srgbRed: 0.13, green: 0.82, blue: 0.69, alpha: 1)

    static let cardFill   = dyn(NSColor.white.withAlphaComponent(0.80), NSColor.white.withAlphaComponent(0.050))
    static let cardStroke = dyn(NSColor.black.withAlphaComponent(0.085), NSColor.white.withAlphaComponent(0.085))
    static let wellFill   = dyn(NSColor.black.withAlphaComponent(0.035), NSColor.black.withAlphaComponent(0.22))
    static let hairline   = dyn(NSColor.black.withAlphaComponent(0.075), NSColor.white.withAlphaComponent(0.075))
    static let navPick    = dyn(violet.withAlphaComponent(0.15), violet.withAlphaComponent(0.28))
    static let navHover   = dyn(NSColor.black.withAlphaComponent(0.045), NSColor.white.withAlphaComponent(0.065))

    /// Bar `i` of `n` along the cyan->violet->pink sweep.
    static func sweep(_ i: Int, of n: Int, alpha: CGFloat = 1) -> NSColor {
        let t = n > 1 ? CGFloat(i) / CGFloat(n - 1) : 0
        return NSColor(calibratedHue: 0.52 + t * 0.38, saturation: 0.82, brightness: 0.98, alpha: alpha)
    }

    // MARK: - Text

    /// Wrapping paragraph label. Claims no intrinsic width, so a long sentence
    /// wraps inside its container instead of stretching the window.
    static func label(_ s: String, _ size: CGFloat = 12,
                      _ weight: NSFont.Weight = .regular,
                      _ color: NSColor = .labelColor) -> NSTextField {
        let f = WrapLabel(labelWithString: s)
        f.font = .systemFont(ofSize: size, weight: weight)
        f.textColor = color
        f.lineBreakMode = .byWordWrapping
        f.maximumNumberOfLines = 0
        f.usesSingleLineMode = false
        f.cell?.wraps = true
        f.cell?.isScrollable = false
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        f.setContentCompressionResistancePriority(.init(rawValue: 200), for: .horizontal)
        return f
    }

    /// Single-line label that keeps its natural width (titles, nav rows, table cells).
    static func line(_ s: String, _ size: CGFloat = 12,
                     _ weight: NSFont.Weight = .regular,
                     _ color: NSColor = .labelColor) -> NSTextField {
        let f = NSTextField(labelWithString: s)
        f.font = .systemFont(ofSize: size, weight: weight)
        f.textColor = color
        f.lineBreakMode = .byTruncatingTail
        f.maximumNumberOfLines = 1
        return f
    }

    static func dim(_ s: String, _ size: CGFloat = 11.5) -> NSTextField {
        label(s, size, .regular, .secondaryLabelColor)
    }

    static func dimLine(_ s: String, _ size: CGFloat = 11.5) -> NSTextField {
        line(s, size, .regular, .secondaryLabelColor)
    }

    static func mono(_ s: String, _ size: CGFloat = 11) -> NSTextField {
        let f = label(s, size)
        f.font = .monospacedSystemFont(ofSize: size, weight: .regular)
        return f
    }

    static func symbol(_ name: String, _ size: CGFloat = 13,
                       _ weight: NSFont.Weight = .semibold) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
    }

    /// The waveform app mark, drawn in the accent sweep.
    static func mark(_ side: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let heights: [CGFloat] = [0.30, 0.52, 0.76, 1.0, 0.76, 0.52, 0.30]
            let n = heights.count
            let barW = rect.width / CGFloat(n * 2 - 1)
            for (i, h) in heights.enumerated() {
                let bh = rect.height * 0.72 * h
                let bar = NSRect(x: CGFloat(i) * barW * 2, y: (rect.height - bh) / 2,
                                 width: barW, height: bh)
                sweep(i, of: n).setFill()
                NSBezierPath(roundedRect: bar, xRadius: barW / 2, yRadius: barW / 2).fill()
            }
            return true
        }
    }

    // MARK: - Buttons

    static func accentButton(_ title: String, target: AnyObject?, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: target, action: action)
        b.bezelStyle = .rounded
        b.bezelColor = violet
        b.contentTintColor = .white
        b.font = .systemFont(ofSize: 12, weight: .medium)
        return b
    }

    static func plainButton(_ title: String, target: AnyObject?, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: target, action: action)
        b.bezelStyle = .rounded
        b.font = .systemFont(ofSize: 12)
        return b
    }

    static func field(_ placeholder: String) -> NSTextField {
        let f = NSTextField()
        f.placeholderString = placeholder
        f.font = .systemFont(ofSize: 12.5)
        f.bezelStyle = .roundedBezel
        return f
    }

    // MARK: - Layout helpers

    static func hstack(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.spacing = spacing
        s.alignment = .centerY
        return s
    }

    static func vstack(_ views: [NSView], spacing: CGFloat = 6) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .vertical
        s.spacing = spacing
        s.alignment = .leading
        return s
    }

    static func spacer() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.init(1), for: .horizontal)
        return v
    }

    static func divider() -> NSView {
        let v = ColorView(color: hairline)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }
}

// MARK: - Small building blocks

/// A label that reports its wrapped height for whatever width it ends up with.
final class WrapLabel: NSTextField {
    override func layout() {
        if abs(preferredMaxLayoutWidth - bounds.width) > 0.5 {
            preferredMaxLayoutWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
        super.layout()
    }
}

/// A flat rectangle of one (appearance-aware) colour.
final class ColorView: NSView {
    private let color: NSColor
    private let radius: CGFloat
    init(color: NSColor, radius: CGFloat = 0) {
        self.color = color
        self.radius = radius
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = radius
    }
    required init?(coder: NSCoder) { fatalError() }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = color.cgColor }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

/// Rounded translucent panel with an optional title/subtitle header.
final class Card: NSView {
    private let stack = NSStackView()

    init(_ title: String? = nil, _ subtitle: String? = nil) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 15),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -15),
        ])

        if let title = title {
            var head: [NSView] = [Theme.line(title, 12.5, .semibold)]
            if let subtitle = subtitle { head.append(Theme.dim(subtitle, 11)) }
            let h = Theme.vstack(head, spacing: 3)
            add(h)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = Theme.cardFill.cgColor
        layer?.borderColor = Theme.cardStroke.cgColor
    }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    /// Adds a row stretched to the card's width.
    func add(_ view: NSView) {
        stack.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    func addDivider() { add(Theme.divider()) }
}

/// Title + explanation on the left, an NSSwitch on the right.
final class ToggleRow: NSView {
    private let sw = NSSwitch()
    private let onChange: (Bool) -> Void

    init(_ title: String, _ detail: String, isOn: Bool, onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)

        let titleLabel = Theme.line(title, 12.5, .medium)
        let detailLabel = Theme.dim(detail, 11)
        sw.state = isOn ? .on : .off
        sw.target = self
        sw.action = #selector(flip)

        // Explicit constraints, not a stack with a spacer: a spacer would win the
        // width fight against a wrapping label and squeeze the text into a column.
        for v in [titleLabel, detailLabel, sw] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: sw.leadingAnchor, constant: -12),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: sw.leadingAnchor, constant: -12),
            detailLabel.bottomAnchor.constraint(equalTo: bottomAnchor),

            sw.trailingAnchor.constraint(equalTo: trailingAnchor),
            sw.centerYAnchor.constraint(equalTo: centerYAnchor),
            sw.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    var isOn: Bool {
        get { sw.state == .on }
        set { sw.state = newValue ? .on : .off }
    }

    @objc private func flip() { onChange(sw.state == .on) }
}

/// Status dot + label + optional action button — used for the permission rows.
final class StatusRow: NSView {
    private let dot = ColorView(color: .systemGray, radius: 4)
    private let titleField: NSTextField
    private let detailField: NSTextField
    private let button: NSButton?
    private let action: () -> Void

    init(_ title: String, _ detail: String, buttonTitle: String?, action: @escaping () -> Void) {
        self.action = action
        titleField = Theme.line(title, 12.5, .medium)
        detailField = Theme.dim(detail, 11)
        button = buttonTitle.map { NSButton(title: $0, target: nil, action: nil) }
        super.init(frame: .zero)

        for v in [dot, titleField, detailField] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        // Same reason as ToggleRow: pin the text to the button instead of using a spacer.
        let rightEdge: NSLayoutXAxisAnchor
        if let b = button {
            b.bezelStyle = .rounded
            b.font = .systemFont(ofSize: 11.5)
            b.target = self
            b.action = #selector(tap)
            // Keep its natural width — otherwise it stretches into the label's space.
            b.setContentHuggingPriority(.required, for: .horizontal)
            b.translatesAutoresizingMaskIntoConstraints = false
            addSubview(b)
            NSLayoutConstraint.activate([
                b.trailingAnchor.constraint(equalTo: trailingAnchor),
                b.centerYAnchor.constraint(equalTo: centerYAnchor),
                b.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            ])
            rightEdge = b.leadingAnchor
        } else {
            rightEdge = trailingAnchor
        }

        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleField.topAnchor.constraint(equalTo: topAnchor),
            titleField.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 10),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: rightEdge, constant: -12),

            detailField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 2),
            detailField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            detailField.trailingAnchor.constraint(equalTo: rightEdge, constant: -12),
            detailField.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func tap() { action() }

    func set(ok: Bool?, detail: String) {
        detailField.stringValue = detail
        let color: NSColor = ok == nil ? .systemGray : (ok! ? Theme.teal : .systemOrange)
        dot.layer?.backgroundColor = color.cgColor
        button?.isHidden = (ok == true)
    }
}

/// Base class so the shell can tell a pane when it comes on screen.
class PaneView: NSView {
    func paneAppeared() {}
    func paneDisappeared() {}
}

extension NSView {
    /// Pins this view to fill `parent`, with optional padding.
    func fill(_ parent: NSView, inset: CGFloat = 0) {
        translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset),
            leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
        ])
    }
}

/// Top-down coordinates, so a scroll view opens at the top of its content
/// instead of at the bottom (AppKit's default for an unflipped document view).
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Horizontal breathing room between the sidebar and a pane's content.
let PANE_INSET: CGFloat = 32

/// A vertically scrolling column of cards.
func makeCardScroll(_ cards: [NSView], topInset: CGFloat = 0) -> NSScrollView {
    let stack = NSStackView(views: cards)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 14
    stack.translatesAutoresizingMaskIntoConstraints = false

    // The side inset belongs on the stack: pinning the document view to the clip
    // view's edges would override NSScrollView.contentInsets, leaving the cards
    // flush against the sidebar.
    let doc = FlippedView()
    doc.translatesAutoresizingMaskIntoConstraints = false
    doc.addSubview(stack)
    NSLayoutConstraint.activate([
        stack.topAnchor.constraint(equalTo: doc.topAnchor, constant: topInset),
        stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: PANE_INSET),
        stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -PANE_INSET),
        stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -18),
    ])
    for c in cards {
        c.translatesAutoresizingMaskIntoConstraints = false
        c.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    let scroll = NSScrollView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.documentView = doc
    NSLayoutConstraint.activate([
        doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
        doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
    ])
    return scroll
}

/// Big pane title + one-line explanation.
func makePaneHeader(_ title: String, _ subtitle: String) -> NSView {
    let t = Theme.line(title, 21, .semibold)
    let s = Theme.dim(subtitle, 12)
    let v = Theme.vstack([t, s], spacing: 3)
    return v
}
