import AppKit

/// One auto-clear rule: clips copied from `app` are deleted after `minutes`.
/// `app` is a bundle ID, or an ID from `BrowserExtensions.known` (browser-extension:bitwarden).
struct AutoClearRule: Codable, Identifiable, Equatable {
    var app: String
    var name: String
    var minutes: Int
    var id: String { app }
}

/// Auto-clear: clips copied from chosen apps are deleted from the history after a set time, and
/// taken off the clipboard too when they're still on it. A rule for a password manager also lets
/// its copies into the history, for that long. Pinned clips are never deleted.
///
/// The rules live in ~/.config/copykeep/auto-clear.json so they're easy to edit by hand or by an
/// agent; Settings reads and writes the same file, and edits are picked up within 10 seconds:
///
///     {"rules": [{"app": "browser-extension:bitwarden", "name": "Bitwarden (browser extension)", "minutes": 15}]}
final class AutoClear: ObservableObject {
    static let shared = AutoClear()
    static let fileURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/copykeep/auto-clear.json")
    static let choices = [1, 5, 15, 30, 60, 240, 1440]

    @Published private(set) var rules: [AutoClearRule] = []
    /// Set when the file can't be read; the rules read before stay in use.
    @Published private(set) var error: String?
    private var loadedDate: Date?

    private init() { reload() }

    var apps: Set<String> { Set(rules.map(\.app)) }

    func rule(for app: String?) -> AutoClearRule? {
        guard let app else { return nil }
        return rules.first { $0.app == app }
    }

    func set(_ rule: AutoClearRule) {
        if let i = rules.firstIndex(where: { $0.app == rule.app }) { rules[i] = rule } else { rules.append(rule) }
        save()
    }

    func remove(_ app: String) {
        rules.removeAll { $0.app == app }
        save()
    }

    /// Reads the file again when it changed since the last read.
    func reloadIfChanged() {
        if Self.modified() != loadedDate { reload() }
    }

    /// Deletes the clips past their time, and empties the clipboard when it still holds one of
    /// them. Returns the deleted clips.
    @discardableResult
    func expire(_ history: History, now: Date = Date()) -> [Clip] {
        reloadIfChanged()
        let expired = history.clips.filter { clip in
            guard !clip.pinned, let rule = rule(for: clip.sourceBundleID) else { return false }
            return now.timeIntervalSince(clip.copiedAt) >= Double(rule.minutes) * 60
        }
        guard !expired.isEmpty else { return [] }
        let pb = NSPasteboard.general
        if let current = pb.string(forType: .string),
           expired.contains(where: { ($0.kind == .text || $0.kind == .link) && $0.text == current }) {
            pb.clearContents()
        }
        expired.forEach { history.delete($0.id) }
        return expired
    }

    /// "1 min", "15 min", "1 hour", "4 hours", "1 day".
    static func label(_ minutes: Int) -> String {
        if minutes % 1440 == 0 { return minutes == 1440 ? "1 day" : "\(minutes / 1440) days" }
        if minutes % 60 == 0 { return minutes == 60 ? "1 hour" : "\(minutes / 60) hours" }
        return "\(minutes) min"
    }

    private struct File: Codable { var rules: [AutoClearRule] }

    private func reload() {
        loadedDate = Self.modified()
        guard let data = try? Data(contentsOf: Self.fileURL) else {
            rules = []
            error = nil
            return
        }
        do {
            rules = try JSONDecoder().decode(File.self, from: data).rules.filter { $0.minutes > 0 }
            error = nil
        } catch {
            self.error = "\(Self.fileURL.lastPathComponent) can't be read, so the rules from before stay in use: \(error.localizedDescription)"
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(File(rules: rules)) else { return }
        try? FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL, options: .atomic)
        loadedDate = Self.modified()
        error = nil
    }

    private static func modified() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }
}

/// A copy made in a browser extension comes from the browser app. To tell one apart, Copykeep
/// asks the browser through Accessibility which page has the focus: an extension's page has an
/// address like chrome-extension://<id>/…. Only asked when an auto-clear rule needs it.
struct KnownExtension {
    let app: String
    let name: String
    /// Its ID in the Chrome Web Store and Edge Add-ons, the same in every install.
    let chromeIDs: Set<String>
    /// Its web app, where copies count as the extension's too.
    let hosts: Set<String>
    /// Firefox and Safari give extensions a random ID per install; the page or window title
    /// names it instead.
    let title: String
}

enum BrowserExtensions {
    static let known = [
        KnownExtension(app: "browser-extension:bitwarden", name: "Bitwarden (browser extension)",
                       chromeIDs: ["nngceckbapebfimnlniiiahkandclblb", "jbkfoedolllekgbhcbcoahefnbanhhlh"],
                       hosts: ["vault.bitwarden.com", "vault.bitwarden.eu"], title: "Bitwarden"),
    ]

    private static let browsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "org.chromium.Chromium",
        "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera", "app.zen-browser.zen", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
        "com.apple.Safari",
    ]

    /// The extension the copy was made in, when `app` is a browser and one of `wanted` has the focus.
    static func source(in app: NSRunningApplication, wanted: Set<String>) -> KnownExtension? {
        let candidates = known.filter { wanted.contains($0.app) }
        guard !candidates.isEmpty, let id = app.bundleIdentifier, browsers.contains(id), Paster.trusted else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.5) // a busy browser mustn't hold up the clipboard check
        // Chromium browsers only build the accessibility tree of web pages for apps that ask.
        AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        var urls: [URL] = []
        var titles: [String] = []
        if let window = element(root, kAXFocusedWindowAttribute), let title: String = value(window, kAXTitleAttribute) {
            titles.append(title)
        }
        // From the focused element up to its window, collecting the pages' addresses and titles.
        var node = element(root, kAXFocusedUIElementAttribute)
        for _ in 0..<60 {
            guard let n = node else { break }
            if let url: URL = value(n, "AXURL") { urls.append(url) }
            if let role: String = value(n, kAXRoleAttribute), role == "AXWebArea", let title: String = value(n, kAXTitleAttribute) {
                titles.append(title)
            }
            node = element(n, kAXParentAttribute)
        }

        return candidates.first { ext in
            urls.contains { url in
                let scheme = url.scheme?.lowercased() ?? ""
                let host = url.host?.lowercased() ?? ""
                if scheme == "chrome-extension" { return ext.chromeIDs.contains(host) }
                if scheme.hasSuffix("-extension") { // moz-extension, safari-web-extension
                    return titles.contains { $0.localizedCaseInsensitiveContains(ext.title) }
                }
                return ext.hosts.contains(host)
            }
        }
    }

    private static func value<T>(_ el: AXUIElement, _ attribute: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attribute as CFString, &v) == .success else { return nil }
        return v as? T
    }

    private static func element(_ el: AXUIElement, _ attribute: String) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attribute as CFString, &v) == .success, let v,
              CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }
}
