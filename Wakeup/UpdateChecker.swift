import Foundation
import AppKit
import Combine

/// Checks GitHub Releases for a newer version of the app and, when found, points the
/// user at the release page to download the new DMG. Intentionally lightweight: no
/// external dependency, no in-app auto-install — it compares versions and opens the
/// browser. Suitable for an open-source app distributed via GitHub Releases.
@MainActor
final class UpdateChecker: ObservableObject {

    /// GitHub repository in "owner/repo" form.
    private let repo = "kartikk-k/wakeup-mac"

    /// How often the automatic (silent) check runs.
    private let autoCheckInterval: TimeInterval = 60 * 60 * 24 // 1 day

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            UserDefaults.standard.set(automaticallyChecksForUpdates, forKey: "automaticallyChecksForUpdates")
        }
    }

    private static let lastCheckKey = "lastUpdateCheckDate"

    init() {
        UserDefaults.standard.register(defaults: ["automaticallyChecksForUpdates": true])
        self.automaticallyChecksForUpdates = UserDefaults.standard.bool(forKey: "automaticallyChecksForUpdates")
    }

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    // MARK: - Public API

    /// Called on launch. Runs a silent check at most once per `autoCheckInterval`, and
    /// only surfaces UI if a newer version is actually available.
    func checkOnLaunchIfNeeded() {
        guard automaticallyChecksForUpdates else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        if let last, Date().timeIntervalSince(last) < autoCheckInterval { return }
        Task { await check(userInitiated: false) }
    }

    /// Called from the "Check for Updates…" menu item. Always shows a result dialog.
    func checkForUpdates() {
        Task { await check(userInitiated: true) }
    }

    /// Open the download page for an available update.
    func openReleasePage(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    // MARK: - Core

    private func check(userInitiated: Bool) async {
        state = .checking
        do {
            let release = try await fetchLatestRelease()
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)

            let latest = release.normalizedVersion
            if latest.isNewer(than: currentVersion) {
                let url = URL(string: release.html_url) ?? releasesURL
                state = .available(version: latest.raw, url: url)
                presentUpdateAvailable(version: latest.raw, url: url)
            } else {
                state = .upToDate
                if userInitiated { presentUpToDate() }
            }
        } catch {
            state = .failed(error.localizedDescription)
            if userInitiated { presentFailure(error) }
        }
    }

    private var releasesURL: URL {
        URL(string: "https://github.com/\(repo)/releases/latest")!
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Wakeup", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.network
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 404 {
                throw UpdateError.noReleases
            }
            throw UpdateError.http(http.statusCode)
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    // MARK: - Dialogs

    private func presentUpdateAvailable(version: String, url: URL) {
        let alert = NSAlert()
        alert.messageText = "A new version of Wakeup is available"
        alert.informativeText = "Wakeup \(version) is available — you have \(currentVersion)."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openReleasePage(url)
        }
    }

    private func presentUpToDate() {
        let alert = NSAlert()
        alert.messageText = "You’re up to date"
        alert.informativeText = "Wakeup \(currentVersion) is the latest version."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func presentFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t check for updates"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

// MARK: - GitHub model

private struct GitHubRelease: Decodable {
    let tag_name: String
    let name: String?
    let html_url: String
    let prerelease: Bool

    /// The version parsed from the tag (preferred) or release name.
    var normalizedVersion: SemanticVersion {
        SemanticVersion(tag_name)
    }
}

// MARK: - Version comparison

/// Minimal semantic-version comparison tolerant of a leading "v" and extra components.
struct SemanticVersion {
    let raw: String
    let components: [Int]

    init(_ string: String) {
        self.raw = string.trimmingCharacters(in: .whitespaces)
        let cleaned = raw
            .lowercased()
            .replacingOccurrences(of: "v", with: "", options: .anchored)
        // Keep only the numeric dotted part, drop any pre-release/build suffix.
        let numericPart = cleaned.prefix { $0.isNumber || $0 == "." }
        self.components = numericPart
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }

    func isNewer(than otherString: String) -> Bool {
        let other = SemanticVersion(otherString)
        let count = Swift.max(components.count, other.components.count)
        for i in 0..<count {
            let a = i < components.count ? components[i] : 0
            let b = i < other.components.count ? other.components[i] : 0
            if a != b { return a > b }
        }
        return false
    }
}

enum UpdateError: LocalizedError {
    case network
    case http(Int)
    case noReleases

    var errorDescription: String? {
        switch self {
        case .network:
            return "Could not reach the update server."
        case .http(let code):
            return "The update server returned an error (HTTP \(code))."
        case .noReleases:
            return "No releases have been published yet."
        }
    }
}
