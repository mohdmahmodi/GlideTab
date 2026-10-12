import AppKit
import Security

/// Updates from GitHub Releases, checked at most daily. A download is installed only if it satisfies this
/// app's designated requirement, meaning it was signed by the same developer.
final class Updater {
    static let shared = Updater()

    private let repository = Bundle.main.object(forInfoDictionaryKey: "GlideTabUpdateRepository") as? String
    private var timer: Timer?
    private var isChecking = false

    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    func start() {
        timer?.invalidate()
        guard Prefs.autoUpdate else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { self.check(userInitiated: false) }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { _ in self.check(userInitiated: false) }
        timer?.tolerance = 60 * 60
    }

    func check(userInitiated: Bool) {
        guard !isChecking else { return }
        guard let repository else {
            if userInitiated { alert(String(localized: "Updates aren't configured for this build.")) }
            return
        }
        isChecking = true
        Task {
            let latest = await Self.latestRelease(of: repository)
            await MainActor.run {
                self.isChecking = false
                guard let release = latest else {
                    if userInitiated { self.alert(String(localized: "Couldn't reach GitHub. Check your internet connection and try again.")) }
                    return
                }
                let version = release.tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                guard Self.isNewer(version, than: self.currentVersion),
                      let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") && Self.isTrustedHost($0.url) })
                else {
                    if userInitiated { self.alert(String(localized: "GlideTab is up to date.")) }
                    return
                }
                self.offer(version: version, notes: release.body ?? "", download: asset.url)
            }
        }
    }

    /// Asks the GitHub API first. Its unauthenticated limit is 60 requests an hour per network, so when that
    /// fails, the release page's redirect gives the latest tag, and the download URL follows from it.
    private static func latestRelease(of repository: String) async -> Release? {
        if let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") {
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let release = try? JSONDecoder().decode(Release.self, from: data) {
                return release
            }
        }
        guard let page = URL(string: "https://github.com/\(repository)/releases/latest") else { return nil }
        var request = URLRequest(url: page, timeoutInterval: 20)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let final = response.url, isTrustedHost(final),
              final.pathComponents.dropLast().last == "tag",
              let download = URL(string: "https://github.com/\(repository)/releases/download/\(final.lastPathComponent)/GlideTab.zip")
        else { return nil }
        return Release(tag: final.lastPathComponent, body: nil, assets: [.init(name: download.lastPathComponent, url: download)])
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let url: URL
            enum CodingKeys: String, CodingKey { case name, url = "browser_download_url" }
        }
        let tag: String
        let body: String?
        let assets: [Asset]
        enum CodingKeys: String, CodingKey { case tag = "tag_name", body, assets }
    }

    /// Release downloads come from GitHub (and its asset CDN), over HTTPS.
    private static func isTrustedHost(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".github.com") || host.hasSuffix(".githubusercontent.com")
    }

    /// Numeric dotted-version comparison: "1.10" > "1.9", "2.0" == "2".
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private func offer(version: String, notes: String, download: URL) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "GlideTab \(version) is available")
        alert.informativeText = notes.isEmpty ? String(localized: "You have \(currentVersion).") : String(notes.prefix(600))
        alert.addButton(withTitle: String(localized: "Install and Relaunch"))
        alert.addButton(withTitle: String(localized: "Later"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        install(from: download, version: version)
    }

    private func install(from url: URL, version: String) {
        URLSession.shared.downloadTask(with: url) { file, _, _ in
            let result = file.flatMap { try? self.prepare(zip: $0, expectedVersion: version) }
            DispatchQueue.main.async {
                guard let newApp = result else { return self.alert(String(localized: "The update couldn't be installed.")) }
                self.replaceAndRelaunch(with: newApp)
            }
        }.resume()
    }

    /// Unzips and verifies the download. Returns the new app bundle.
    private func prepare(zip: URL, expectedVersion: String) throws -> URL {
        // Refuse implausibly large downloads.
        let size = (try? zip.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size < 100_000_000 else { throw CocoaError(.fileReadTooLarge) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("GlideTab-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, folder.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0,
              let app = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }),
              let bundle = Bundle(url: app), bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              // It must really be the version the release claims, and newer than this build: no downgrades.
              (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) == expectedVersion,
              Self.buildNumber(bundle) > Self.buildNumber(.main),
              Self.isSignedLikeMe(app)
        else {
            try? FileManager.default.removeItem(at: folder)
            throw CocoaError(.fileReadCorruptFile)
        }
        return app
    }

    private static func buildNumber(_ bundle: Bundle) -> Int {
        Int(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    private static func isSignedLikeMe(_ app: URL) -> Bool {
        var me: SecCode?
        var myStatic: SecStaticCode?
        var requirement: SecRequirement?
        var candidate: SecStaticCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &myStatic) == errSecSuccess, let myStatic,
              SecCodeCopyDesignatedRequirement(myStatic, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(app as CFURL, [], &candidate) == errSecSuccess, let candidate
        else { return false }
        let enforceRevocationChecks: UInt32 = 1 << 30 // kSecCSEnforceRevocationChecks, not exported to Swift
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode
            | enforceRevocationChecks)
        guard SecStaticCodeCheckValidity(candidate, flags, requirement) == errSecSuccess else { return false }
        // If this copy was notarized by Apple, its replacement must be too.
        var notarized: SecRequirement?
        guard SecRequirementCreateWithString("notarized" as CFString, [], &notarized) == errSecSuccess, let notarized else { return true }
        if SecStaticCodeCheckValidity(myStatic, [], notarized) == errSecSuccess {
            return SecStaticCodeCheckValidity(candidate, [], notarized) == errSecSuccess
        }
        return true
    }

    private func replaceAndRelaunch(with newApp: URL) {
        let current = Bundle.main.bundleURL
        do {
            _ = try FileManager.default.replaceItemAt(current, withItemAt: newApp)
        } catch {
            return alert(String(localized: "The update couldn't be installed."))
        }
        AppDelegate.relaunch()
    }

    private func alert(_ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
