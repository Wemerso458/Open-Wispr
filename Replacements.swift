// The replacement dictionary: "heard this -> type that".
// Rules come from two places — typed by hand in the settings window, or learned
// automatically when you fix a word right after a paste (see CorrectionWatcher).
import Foundation

struct ReplacementRule: Codable, Equatable {
    var id: String
    var from: String
    var to: String
    var learned: Bool
    /// Case-only fixes ("janice" -> "Janice") must not match the already-correct form,
    /// so they are stored as exact-case rules.
    var caseSensitive: Bool
    var hits: Int
    var created: Date

    init(from: String, to: String, learned: Bool = false, caseSensitive: Bool = false) {
        self.id = UUID().uuidString
        self.from = from
        self.to = to
        self.learned = learned
        self.caseSensitive = caseSensitive
        self.hits = 0
        self.created = Date()
    }

    // Hand-written so an older/partial file still loads instead of throwing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        from = (try? c.decode(String.self, forKey: .from)) ?? ""
        to = (try? c.decode(String.self, forKey: .to)) ?? ""
        learned = (try? c.decode(Bool.self, forKey: .learned)) ?? false
        caseSensitive = (try? c.decode(Bool.self, forKey: .caseSensitive)) ?? false
        hits = (try? c.decode(Int.self, forKey: .hits)) ?? 0
        created = (try? c.decode(Date.self, forKey: .created)) ?? Date()
    }
}

private struct RulesFile: Codable {
    var version: Int
    var rules: [ReplacementRule]
}

final class ReplacementStore {
    static let shared = ReplacementStore()

    private(set) var rules: [ReplacementRule] = []

    private init() { load() }

    // MARK: - Persistence

    func load() {
        guard let data = try? Data(contentsOf: Config.shared.rulesURL) else { return }
        if let file = try? JSONDecoder().decode(RulesFile.self, from: data) {
            rules = file.rules
        } else if let bare = try? JSONDecoder().decode([ReplacementRule].self, from: data) {
            rules = bare
        }
        lastLoadedModified = fileModified()
    }

    private var lastLoadedModified: Date?

    private func fileModified() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: Config.shared.rulesURL.path)[.modificationDate]) as? Date
    }

    /// Saving writes the whole array, so a copy that went stale — a second instance,
    /// or the file edited by hand — would silently wipe newer rules. Re-read first.
    private func syncFromDisk() {
        guard let onDisk = fileModified() else { return }
        if lastLoadedModified == nil || onDisk > lastLoadedModified! { load() }
    }

    func save(notify: Bool = true) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(RulesFile(version: 1, rules: rules)) {
            try? data.write(to: Config.shared.rulesURL, options: .atomic)
            lastLoadedModified = fileModified()
        }
        if notify { NotificationCenter.default.post(name: .owRulesChanged, object: nil) }
    }

    // MARK: - Editing

    /// Adds a rule, or retargets the existing rule with the same `from`.
    /// Returns true when something actually changed.
    @discardableResult
    func upsert(from: String, to: String, learned: Bool = false, caseSensitive: Bool = false) -> Bool {
        syncFromDisk()
        let f = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty, !t.isEmpty, f != t else { return false }

        if let i = rules.firstIndex(where: { matchesKey($0, f, caseSensitive: caseSensitive) }) {
            if rules[i].to == t && rules[i].caseSensitive == caseSensitive { return false }
            rules[i].to = t
            rules[i].caseSensitive = caseSensitive
            if learned { rules[i].learned = true }
            save()
            return true
        }
        rules.insert(ReplacementRule(from: f, to: t, learned: learned, caseSensitive: caseSensitive), at: 0)
        save()
        return true
    }

    private func matchesKey(_ rule: ReplacementRule, _ from: String, caseSensitive: Bool) -> Bool {
        // A case-only rule ("janice" -> "Janice") coexists with a spelling rule for the
        // same word only if their spellings differ; otherwise treat them as one entry.
        if rule.caseSensitive || caseSensitive { return rule.from == from }
        return rule.from.caseInsensitiveCompare(from) == .orderedSame
    }

    func update(id: String, from: String? = nil, to: String? = nil) {
        syncFromDisk()
        guard let i = rules.firstIndex(where: { $0.id == id }) else { return }
        if let f = from?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty { rules[i].from = f }
        if let t = to?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { rules[i].to = t }
        save()
    }

    func setCaseSensitive(id: String, _ on: Bool) {
        syncFromDisk()
        guard let i = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[i].caseSensitive = on
        save()
    }

    func remove(id: String) {
        syncFromDisk()
        rules.removeAll { $0.id == id }
        save()
    }

    func removeAllLearned() {
        syncFromDisk()
        rules.removeAll { $0.learned }
        save()
    }

    func rule(withFrom from: String) -> ReplacementRule? {
        rules.first { $0.from.caseInsensitiveCompare(from) == .orderedSame }
    }

    // MARK: - Applying

    /// Whole-word substitution over the transcript. Longest `from` first so a rule for
    /// "req key" wins over one for "key".
    func apply(to text: String) -> String {
        syncFromDisk()
        guard !rules.isEmpty, !text.isEmpty else { return text }
        var out = text
        var hitAny = false

        for (index, rule) in rules.enumerated().sorted(by: { $0.element.from.count > $1.element.from.count }) {
            guard !rule.from.isEmpty, !rule.to.isEmpty else { continue }
            // Lookarounds instead of \b so multi-word and punctuated phrases work too.
            let pattern = "(?<![\\p{L}\\p{N}_])"
                + NSRegularExpression.escapedPattern(for: rule.from)
                + "(?![\\p{L}\\p{N}_])"
            var opts: NSRegularExpression.Options = []
            if !rule.caseSensitive { opts.insert(.caseInsensitive) }
            guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { continue }

            let matches = re.matches(in: out, options: [], range: NSRange(out.startIndex..., in: out))
            guard !matches.isEmpty else { continue }

            let buffer = NSMutableString(string: out)
            for m in matches.reversed() {
                var replacement = rule.to
                // "rekki" at the start of a sentence should still come out capitalised.
                if !rule.caseSensitive {
                    let matched = buffer.substring(with: m.range)
                    if let mf = matched.first, mf.isUppercase,
                       let rf = replacement.first, rf.isLowercase {
                        replacement = replacement.prefix(1).uppercased() + replacement.dropFirst()
                    }
                }
                buffer.replaceCharacters(in: m.range, with: replacement)
            }
            out = buffer as String
            rules[index].hits += matches.count
            hitAny = true
        }

        // Hit counters only — don't nudge the UI mid-edit.
        if hitAny { save(notify: false) }
        return out
    }
}
