import AppKit
import Foundation

struct Browser: Identifiable {
    let id: Destination
    let appURL: URL
    let title: String
    let subtitle: String?
}

struct BrowserInventory {
    var browsers: [Browser] = []
    var chromeProfilesUnavailable = false
}

struct BrowserRegistry {
    static let chrome = "com.google.Chrome"
    static let supported = [(chrome, "Google Chrome"), ("com.apple.Safari", "Safari"), ("org.mozilla.firefox", "Firefox")]
    let chromeRoot = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/Google/Chrome", directoryHint: .isDirectory)

    func scan(chromeAccess: URL? = nil) -> BrowserInventory {
        var inventory = BrowserInventory()
        for (bundleID, label) in Self.supported {
            guard bundleID != Bundle.main.bundleIdentifier,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
                  let executable = Bundle(url: url)?.executableURL,
                  FileManager.default.isExecutableFile(atPath: executable.path) else { continue }
            if bundleID == Self.chrome {
                let profiles = chromeProfiles(at: url, label: label, root: chromeAccess ?? chromeRoot)
                inventory.chromeProfilesUnavailable = profiles == nil
                let discovered = profiles ?? []
                inventory.browsers += discovered
                if !discovered.contains(where: { $0.id.profileDirectory == "Default" }) {
                    let destination = Destination(bundleID: bundleID, profileDirectory: "Default")
                    inventory.browsers.append(Browser(id: destination, appURL: url, title: "Default", subtitle: label))
                }
            } else {
                inventory.browsers.append(Browser(id: Destination(bundleID: bundleID), appURL: url,
                                                  title: label, subtitle: nil))
            }
        }
        return inventory
    }

    private func chromeProfiles(at appURL: URL, label: String, root: URL) -> [Browser]? {
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        struct LocalState: Decodable {
            struct Profile: Decodable {
                struct Entry: Decodable { var name: String? }
                let info_cache: [String: Entry]
            }
            let profile: Profile
        }
        guard let data = try? Data(contentsOf: root.appending(path: "Local State")),
              let state = try? JSONDecoder().decode(LocalState.self, from: data) else { return nil }

        let profiles = state.profile.info_cache.filter { directory, _ in
            guard !directory.isEmpty, directory != ".", directory != "..",
                  !directory.contains("/"), !directory.contains("\\") else { return false }
            let url = root.appending(path: directory, directoryHint: .isDirectory)
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) &&
                isDirectory.boolValue && url.resolvingSymlinksInPath().deletingLastPathComponent()
                .standardizedFileURL.path == root.resolvingSymlinksInPath().standardizedFileURL.path
        }

        return profiles.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { directory in
            let name = profiles[directory]?.name ?? directory
            let description = name == directory ? label : "\(label) · \(directory)"
            return Browser(id: Destination(bundleID: Self.chrome, profileDirectory: directory),
                           appURL: appURL, title: name, subtitle: description)
        }
    }
}

enum OpenFailure: Error {
    case unavailable, failed

    var message: String {
        switch self {
        case .unavailable: "This browser or profile is unavailable."
        case .failed: "The browser could not open the link."
        }
    }
}

@MainActor
struct BrowserLauncher {
    func open(_ link: WebLink, in browser: Browser, chromeRoot: URL) async throws {
        if let profile = browser.id.profileDirectory {
            guard let executable = Bundle(url: browser.appURL)?.executableURL else { throw OpenFailure.unavailable }
            try await Task.detached(priority: .userInitiated) {
                try await Self.launchChrome(executable, root: chromeRoot, profile: profile, url: link.url)
            }.value
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        do {
            _ = try await NSWorkspace.shared.open([link.url], withApplicationAt: browser.appURL, configuration: config)
        } catch {
            throw OpenFailure.failed
        }
    }

    nonisolated private static func launchChrome(_ executable: URL, root: URL, profile: String, url: URL) async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--user-data-dir=\(root.path)", "--profile-directory=\(profile)", url.absoluteString]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw OpenFailure.failed
        }

        // A cold launch can stay alive for the whole browsing session.
        for _ in 0..<12 {
            if !process.isRunning {
                guard process.terminationStatus == 0 else { throw OpenFailure.failed }
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
