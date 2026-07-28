// Auto-learn: after a paste, watch the field we pasted into and notice when you
// fix a single word by hand ("Janish" -> "Janice"). That pair becomes a
// replacement rule, so the next dictation gets it right on its own.
//
// Deliberately conservative. It only ever learns from a *substitution* inside the
// text we just pasted: same number of words, exactly one of them different, the
// new word spelled similarly to the old one, and the text has sat still for a
// beat so we don't learn a half-typed word. Anything else is ignored.
//
// Reads the focused field through the Accessibility API (a grant the app already
// needs in order to paste). Nothing is stored but the word pair, nothing leaves
// the Mac. Fields that don't expose their text (terminals, some Electron apps)
// simply can't be watched — we log it and move on.
import Cocoa
import ApplicationServices

final class CorrectionWatcher {

    /// (spokenWord, correctedWord)
    var onLearn: ((String, String) -> Void)?

    private var timer: Timer?
    private var element: AXUIElement?
    private var baseline: [Character] = []
    private var regionStart = 0          // where our pasted text sits in the field
    private var regionLen = 0
    private var pastedLower = ""
    private var deadline = Date.distantPast
    private var learns = 0
    private var misses = 0
    private var attempt = 0
    private var pendingPasted = ""
    private var retryWork: DispatchWorkItem?

    // Debounce state: an edit must look the same across polls before we judge it.
    private var pendingKey = ""
    private var pendingSince = Date.distantPast

    /// Maps a word we already learned *to* back to the word originally spoken, so a
    /// second pass ("Janish"->"Jan" then "Jan"->"Janice") collapses into one rule.
    private var chain: [String: String] = [:]

    private let pollInterval: TimeInterval = 0.4
    private let stableDelay: TimeInterval = 1.1
    private let watchWindow: TimeInterval = 90
    private let maxLearns = 4
    // Chrome took ~5s to publish its tree after being asked, so keep trying for ~9s.
    private let maxAttempts = 13
    private let retryDelay: TimeInterval = 0.7
    private let maxMisses = 4

    // MARK: - Lifecycle

    func stop() {
        timer?.invalidate()
        timer = nil
        retryWork?.cancel()
        retryWork = nil
        element = nil
        baseline = []
        chain = [:]
        pendingKey = ""
        misses = 0
    }

    func begin(pasted: String) {
        stop()
        guard pasted.count >= 2, pasted.count < 20_000 else { return }
        guard AXIsProcessTrusted() else {
            Config.shared.log("Auto-learn: no Accessibility permission — skipped")
            return
        }
        pendingPasted = pasted
        attempt = 0
        attach()
    }

    /// Finding the field can take a couple of tries: the paste may still be landing,
    /// and Chromium/Electron apps only publish their accessibility tree once asked.
    private func attach() {
        attempt += 1
        let pasted = pendingPasted

        if let hit = Self.locate(pasted: Array(pasted)) {
            element = hit.element
            baseline = hit.text
            regionStart = hit.start
            regionLen = pasted.count
            pastedLower = pasted.lowercased()
            learns = 0
            misses = 0
            pendingKey = ""
            deadline = Date().addingTimeInterval(watchWindow)
            timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
                self?.tick()
            }
            Config.shared.log("Auto-learn: watching \(Self.describe(hit.element)) — \(hit.text.count) chars")
            return
        }

        guard attempt < maxAttempts else {
            let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "the frontmost app"
            Config.shared.log("Auto-learn: couldn't read the text of the field in \(app) "
                              + "— it may not publish its content over Accessibility. Skipped.")
            return
        }

        // Backstop for when recording didn't get there first (e.g. the user switched
        // apps mid-dictation): ask now and keep retrying while the tree is built.
        if attempt == 1 { Self.prepareFrontmostApp() }
        retryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.attach() }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay, execute: work)
    }

    // MARK: - The diff

    enum Outcome: Equatable {
        /// Field is untouched since we last looked.
        case unchanged
        /// Edit landed outside our pasted text; re-anchor by this many characters.
        case outside(shift: Int)
        /// Edit landed inside our pasted text. `key` identifies it for debouncing;
        /// `pair` is the (old, new) word when it looks like a single substitution.
        case inside(key: String, pair: WordPair?)
    }

    struct WordPair: Equatable {
        let from: String
        let to: String
    }

    /// The whole comparison, as a pure function — no AX, no clock, so it can be tested.
    static func classify(baseline a: [Character], current b: [Character],
                         regionStart: Int, regionLen: Int) -> Outcome {
        if a == b { return .unchanged }

        // Narrow the change down to the span between the common prefix and suffix.
        var p = 0
        while p < a.count, p < b.count, a[p] == b[p] { p += 1 }
        var s = 0
        while s < a.count - p, s < b.count - p, a[a.count - 1 - s] == b[b.count - 1 - s] { s += 1 }
        let aEnd = a.count - s
        let bEnd = b.count - s

        // Typing somewhere else in the document.
        let regionEnd = regionStart + regionLen
        if p >= regionEnd { return .outside(shift: 0) }
        if aEnd <= regionStart { return .outside(shift: bEnd - aEnd) }

        // Grow the span out to whole words on both sides. The suffix is shared, so
        // stepping the end forward in `a` steps over the same characters in `b`.
        var lo = p
        while lo > 0, isWordChar(a[lo - 1]) { lo -= 1 }
        var aHi = aEnd, bHi = bEnd
        while aHi < a.count, isWordChar(a[aHi]) { aHi += 1; bHi += 1 }

        let key = "\(p)|\(aEnd)|\(String(b[p..<bEnd]))"
        guard lo <= aHi, aHi <= a.count, lo <= bHi, bHi <= b.count else {
            return .inside(key: key, pair: nil)
        }

        let oldWords = words(in: a[lo..<aHi])
        let newWords = words(in: b[lo..<bHi])
        guard oldWords.count == newWords.count else { return .inside(key: key, pair: nil) }
        let diffs = zip(oldWords, newWords).filter { $0 != $1 }
        guard diffs.count == 1 else { return .inside(key: key, pair: nil) }
        return .inside(key: key, pair: WordPair(from: diffs[0].0, to: diffs[0].1))
    }

    private func tick() {
        if Date() > deadline { stop(); return }
        guard let el = element else { stop(); return }
        guard let current = Self.stringValue(of: el) else {
            // A read can fail briefly (window redrawing, field rebuilt). Only give up
            // once it keeps failing.
            misses += 1
            if misses >= maxMisses { stop() }
            return
        }
        misses = 0

        let a = baseline
        let b = Array(current)

        switch Self.classify(baseline: a, current: b, regionStart: regionStart, regionLen: regionLen) {
        case .unchanged:
            pendingKey = ""

        case .outside(let shift):
            regionStart += shift
            baseline = b
            pendingKey = ""

        case .inside(let key, let pair):
            // Wait for the edit to settle — mid-word keystrokes are not corrections.
            if key != pendingKey {
                pendingKey = key
                pendingSince = Date()
                return
            }
            if Date().timeIntervalSince(pendingSince) < stableDelay { return }

            // Re-anchor before judging, so the next poll compares against what's there now.
            baseline = b
            regionLen = max(0, regionLen + (b.count - a.count))
            pendingKey = ""

            guard let pair = pair else { return }
            guard Self.plausible(from: pair.from, to: pair.to) else {
                Config.shared.log("Auto-learn: ignored “\(pair.from)” → “\(pair.to)” "
                                  + "(doesn't look like a misheard-word fix)")
                return
            }

            // Only learn from a word we actually said (or from one of our earlier guesses).
            let spoken = pair.from.lowercased()
            guard pastedLower.contains(spoken) || chain[spoken] != nil else { return }
            let from = chain[spoken] ?? pair.from
            chain[pair.to.lowercased()] = from

            learns += 1
            onLearn?(from, pair.to)
            if learns >= maxLearns { stop() }
        }
    }

    // MARK: - Judging a candidate

    /// Is this edit shaped like "you fixed a misheard word", rather than a rewrite,
    /// a deletion, or a word being typed?
    static func plausible(from: String, to: String) -> Bool {
        guard from.count >= 2, from.count <= 40, to.count >= 1, to.count <= 40 else { return false }
        guard from != to else { return false }

        let wordish = "^[\\p{L}][\\p{L}'’\\-]*$"
        guard from.range(of: wordish, options: .regularExpression) != nil,
              to.range(of: wordish, options: .regularExpression) != nil else { return false }

        let f = from.lowercased(), t = to.lowercased()
        if f == t { return true }                                  // capitalisation fix
        if f.hasPrefix(t) && t.count < f.count - 2 { return false } // truncation / mid-typing
        let distance = levenshtein(Array(f), Array(t))
        return distance <= max(2, Int(ceil(Double(max(f.count, t.count)) * 0.5)))
    }

    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var row = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            row[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                row[j] = min(prev[j] + 1, row[j - 1] + 1, prev[j - 1] + cost)
            }
            prev = row
        }
        return prev[b.count]
    }

    // MARK: - Text helpers

    static func isWordChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "'" || c == "’" || c == "-"
    }

    static func words(in slice: ArraySlice<Character>) -> [String] {
        var out: [String] = []
        var buf = ""
        for c in slice {
            if isWordChar(c) { buf.append(c) }
            else if !buf.isEmpty { out.append(buf); buf = "" }
        }
        if !buf.isEmpty { out.append(buf) }
        return out
    }

    static func lastIndex(of needle: [Character], in haystack: [Character]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        var i = haystack.count - needle.count
        while i >= 0 {
            var match = true
            for k in 0..<needle.count where haystack[i + k] != needle[k] { match = false; break }
            if match { return i }
            i -= 1
        }
        return nil
    }

    // MARK: - Accessibility plumbing

    struct Located {
        let element: AXUIElement
        let text: [Character]
        let start: Int
    }

    /// Find the element whose text contains what we just pasted. The system-wide
    /// focused-element query fails outright in some apps (notably Chromium/Electron
    /// ones), so fall back to the frontmost app's own focused element and window,
    /// then search downwards for the text.
    /// Web content sits deep (window → … → web area → group → text area), so the
    /// limits are generous. This runs once when attaching; polling afterwards only
    /// touches the single element we found.
    static func locate(pasted: [Character]) -> Located? {
        for root in candidateRoots() {
            var budget = 4000
            if let hit = findText(pasted: pasted, in: root, depth: 0, budget: &budget) { return hit }
        }
        return nil
    }

    static func candidateRoots() -> [AXUIElement] {
        var out: [AXUIElement] = []
        if let el = element(of: AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute) {
            out.append(el)
        }
        if let app = NSWorkspace.shared.frontmostApplication {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            if let el = element(of: appElement, kAXFocusedUIElementAttribute) { out.append(el) }
            if let win = element(of: appElement, kAXFocusedWindowAttribute) { out.append(win) }
        }
        return out
    }

    /// Apps we have already asked to publish their accessibility tree this session.
    private static var enabledPids = Set<pid_t>()

    /// Chromium-based apps (Chrome, Electron apps like Slack or Claude) don't build
    /// an accessibility tree until an assistive client asks for one, so the focused
    /// text field is invisible to us — which is why auto-learn silently did nothing
    /// there. Setting AXEnhancedUserInterface is that ask; it's the same switch
    /// VoiceOver and other assistive tools flip. Measured: Chrome needs ~5s to build
    /// the tree, so we ask when recording starts rather than when the paste lands.
    /// Only done once per app per session, and only when auto-learn is on.
    @discardableResult
    static func requestAccessibilityTree(for app: NSRunningApplication?) -> Bool {
        guard let app = app, !app.isTerminated else { return false }
        let pid = app.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier else { return false }
        let appElement = AXUIElementCreateApplication(pid)

        // Already talking to us? Then nothing to do.
        if element(of: appElement, kAXFocusedUIElementAttribute) != nil { return false }
        guard !enabledPids.contains(pid) else { return false }
        enabledPids.insert(pid)

        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        // Harmless where unsupported; some Electron builds listen for this one instead.
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        Config.shared.log("Auto-learn: asked \(app.localizedName ?? "pid \(pid)") to publish its "
                          + "accessibility tree (needed to see your edits)")
        return true
    }

    /// Called when recording starts, so the app has the whole record+transcribe
    /// window to build its tree before we need to read it.
    static func prepareFrontmostApp() {
        requestAccessibilityTree(for: NSWorkspace.shared.frontmostApplication)
    }

    /// Depth- and node-limited hunt for an element whose value contains `pasted`.
    static func findText(pasted: [Character], in node: AXUIElement,
                         depth: Int, budget: inout Int) -> Located? {
        guard budget > 0 else { return nil }
        budget -= 1
        if let s = stringValue(of: node), s.count < 400_000, s.count >= pasted.count {
            let chars = Array(s)
            if let start = lastIndex(of: pasted, in: chars) {
                return Located(element: node, text: chars, start: start)
            }
        }
        guard depth < 22 else { return nil }
        for child in children(of: node) {
            if let hit = findText(pasted: pasted, in: child, depth: depth + 1, budget: &budget) {
                return hit
            }
        }
        return nil
    }

    static func element(of parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(v, to: AXUIElement.self)
    }

    static func children(of node: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(node, kAXChildrenAttribute as CFString, &value) == .success,
              let array = value as? [AnyObject] else { return [] }
        return array.compactMap {
            CFGetTypeID($0) == AXUIElementGetTypeID() ? unsafeBitCast($0, to: AXUIElement.self) : nil
        }
    }

    static func stringValue(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let s = value as? String else { return nil }
        return s
    }

    static func describe(_ element: AXUIElement) -> String {
        var value: CFTypeRef?
        var role = "?"
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success,
           let r = value as? String { role = r }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let app = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
        return "\(role) in \(app)"
    }
}
