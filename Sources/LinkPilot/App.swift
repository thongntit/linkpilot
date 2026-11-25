import AppKit
import OSLog
import SwiftUI

@main
enum LinkPilot {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = LinkCoordinator()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var pickerWindow: NSPanel?
    private var keyboardMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.showPicker = { [weak self] in self?.showPicker() }
        model.hidePicker = { [weak self] in self?.pickerWindow?.orderOut(nil) }
        makeMenu()
        model.start()
        registerPickerKeyboard()
        if !UserDefaults.standard.bool(forKey: "hasOpenedSettings") && !model.hasIncomingLinks {
            showSettings()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        model.receive(urls)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshHandlers()
    }

    private func makeMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "LinkPilot")
        item.button?.toolTip = "LinkPilot"
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit LinkPilot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func showSettings() {
        UserDefaults.standard.set(true, forKey: "hasOpenedSettings")
        model.refresh()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 470),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "LinkPilot Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func showPicker() {
        if pickerWindow == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 470, height: 440),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "Open Link"
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: LinkPicker(model: model))
            pickerWindow = panel
        }
        if pickerWindow?.isVisible == false { pickerWindow?.center() }
        NSApp.activate()
        pickerWindow?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender == pickerWindow {
            model.finishPicker()
            return false
        }
        return true
    }

    private func registerPickerKeyboard() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.pickerWindow, panel === event.window,
                  panel.isKeyWindow, self.model.pickerLink != nil,
                  !self.model.openingFromPicker else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "c" {
                self.model.copyPickerLink()
                return nil
            }
            guard modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return event }
            switch event.keyCode {
            case 126: self.model.moveSelection(by: -1)
            case 125: self.model.moveSelection(by: 1)
            case 36, 76: self.model.openSelected()
            case 53: self.model.finishPicker()
            default: return event
            }
            return nil
        }
    }
}

@MainActor
final class LinkCoordinator: ObservableObject {
    @Published private(set) var preferences = Preferences()
    @Published private(set) var browsers: [Browser] = []
    @Published private(set) var chromeProfilesUnavailable = false
    @Published private(set) var pickerLink: WebLink?
    @Published var selection: Destination?
    @Published var rememberChoice = false
    @Published private(set) var pickerMessage: String?
    @Published private(set) var openingFromPicker = false
    @Published private(set) var settingsMessage: String?
    @Published private(set) var storageLocked = false
    @Published private(set) var handlerStatus = ""
    @Published private(set) var isDefaultBrowser = false
    @Published private(set) var requestingDefaultBrowser = false

    var showPicker: (() -> Void)?
    var hidePicker: (() -> Void)?

    private let logger = Logger(subsystem: "io.hiraism.LinkPilot", category: "Routing")
    private let registry = BrowserRegistry()
    private let launcher = BrowserLauncher()
    private let store: SettingsStore
    private static let defaultStore = SettingsStore(file: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: Bundle.main.bundleIdentifier ?? "io.hiraism.LinkPilot", directoryHint: .isDirectory)
        .appending(path: "settings.json"))
    init(store: SettingsStore? = nil) {
        self.store = store ?? Self.defaultStore
    }

    private var chromeAccess: URL?
    private static let chromeBookmarkKey = "chromeProfileFolderBookmark"
    private var ready = false
    private var routing = false
    private var incoming: [WebLink] = []
    private var waiting: [(link: WebLink, message: String?)] = []
    var hasIncomingLinks: Bool { !incoming.isEmpty || routing || pickerLink != nil }

    func start() {
        reloadSettings()
        if let bookmark = UserDefaults.standard.data(forKey: Self.chromeBookmarkKey) {
            var stale = false
            let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                               relativeTo: nil, bookmarkDataIsStale: &stale)
            if let url, isChromeRoot(url) { chromeAccess = url }
        }
        refresh()
        ready = true
        processIncoming()
    }

    func reloadSettings() {
        do {
            preferences = try store.load()
            storageLocked = false
            settingsMessage = nil
        } catch {
            if !ready || !storageLocked { preferences = Preferences() }
            storageLocked = true
            settingsMessage = "Settings couldn’t be read. The file was preserved. Repair it and reload settings."
        }
    }

    @discardableResult
    func save(_ next: Preferences) -> Bool {
        guard !storageLocked else { return false }
        do {
            // Recheck an on-disk file that may have been changed outside the app.
            let current = try store.load()
            guard current == preferences else {
                preferences = current
                settingsMessage = "Settings changed on disk. Review the reloaded settings and retry."
                return false
            }
        } catch {
            storageLocked = true
            preferences = Preferences()
            settingsMessage = "The settings file changed and couldn’t be read. It was preserved."
            return false
        }
        do {
            try store.save(next)
            preferences = next
            settingsMessage = nil
            return true
        } catch {
            settingsMessage = "Couldn’t save settings."
            return false
        }
    }

    func refresh() {
        updateBrowsers()
        if pickerLink != nil && !browsers.contains(where: { $0.id == selection }) {
            selection = browsers.first?.id
        }
        refreshHandlers()
    }

    private func updateBrowsers() {
        let inventory = registry.scan(chromeAccess: chromeAccess)
        browsers = inventory.browsers
        chromeProfilesUnavailable = inventory.chromeProfilesUnavailable
    }

    func chooseChromeProfileFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Chrome Profile Folder"
        panel.message = "Select the Chrome folder to show your browser profiles in LinkPilot."
        panel.prompt = "Choose Chrome Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = registry.chromeRoot
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard isChromeRoot(url) else {
            settingsMessage = "Choose the Chrome folder in Library/Application Support/Google."
            return
        }
        chromeAccess = url
        if let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: Self.chromeBookmarkKey)
        }
        refresh()
        settingsMessage = chromeProfilesUnavailable ? "macOS did not provide access to the Chrome profile list." : nil
    }

    private func isChromeRoot(_ url: URL) -> Bool {
        url.isFileURL && url.resolvingSymlinksInPath().standardizedFileURL.path ==
            registry.chromeRoot.resolvingSymlinksInPath().standardizedFileURL.path
    }

    func refreshHandlers() {
        let schemes = ["http", "https"]
        isDefaultBrowser = schemes.allSatisfy(isDefaultHandler)
        handlerStatus = schemes.map { scheme in
            "\(scheme.uppercased()) · \(isDefaultHandler(scheme) ? "LinkPilot" : "Other browser")"
        }.joined(separator: "     ")
    }

    private func isDefaultHandler(_ scheme: String) -> Bool {
        guard let identifier = Bundle.main.bundleIdentifier,
              let url = URL(string: "\(scheme)://example.com"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: url) else { return false }
        return Bundle(url: handler)?.bundleIdentifier == identifier
    }

    func requestDefaultBrowser() {
        guard !requestingDefaultBrowser else { return }
        requestingDefaultBrowser = true
        Task {
            defer {
                refreshHandlers()
                requestingDefaultBrowser = false
            }
            do {
                for scheme in ["https", "http"] where !isDefaultHandler(scheme) {
                    try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL,
                                                                       toOpenURLsWithScheme: scheme)
                    // Stop if macOS declined the request without returning an error.
                    if !isDefaultHandler(scheme) { break }
                }
            } catch {
                settingsMessage = "The default browser wasn’t changed. You can select LinkPilot in System Settings."
            }
        }
    }

    func openDefaultBrowserSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!
        NSWorkspace.shared.open(url)
    }

    func receive(_ urls: [URL]) {
        let accepted = urls.compactMap(WebLink.init)
        logger.notice("URL event received: \(accepted.count, privacy: .public) accepted, \(urls.count - accepted.count, privacy: .public) rejected")
        incoming.append(contentsOf: accepted)
        processIncoming()
    }

    private func processIncoming() {
        guard ready, !routing, !incoming.isEmpty else { return }
        routing = true
        Task {
            while !incoming.isEmpty {
                let link = incoming.removeFirst()
                guard let destination = preferences.destination(for: link.host) else {
                    logger.notice("Routing to picker")
                    enqueuePicker(link)
                    continue
                }
                do {
                    try await open(link, at: destination)
                    logger.notice("Automatic launch request sent")
                } catch let error as OpenFailure {
                    logger.error("Automatic launch failed: \(error == .unavailable ? 1 : 2, privacy: .public)")
                    enqueuePicker(link, message: error.message)
                } catch {
                    enqueuePicker(link, message: OpenFailure.failed.message)
                }
            }
            routing = false
        }
    }

    private func open(_ link: WebLink, at destination: Destination) async throws {
        updateBrowsers()
        guard let browser = browsers.first(where: { $0.id == destination }) else { throw OpenFailure.unavailable }
        try await launcher.open(link, in: browser, chromeRoot: registry.chromeRoot)
    }

    private func enqueuePicker(_ link: WebLink, message: String? = nil) {
        waiting.append((link, message))
        presentNextPicker()
    }

    private func presentNextPicker() {
        guard pickerLink == nil, !waiting.isEmpty else { return }
        let next = waiting.removeFirst()
        refresh()
        selection = browsers.first?.id
        rememberChoice = false
        pickerMessage = next.message
        pickerLink = next.link
        showPicker?()
    }

    func finishPicker() {
        guard !openingFromPicker else { return }
        pickerLink = nil
        if waiting.isEmpty { hidePicker?() }
        presentNextPicker()
    }

    func copyPickerLink() {
        guard let link = pickerLink, !openingFromPicker else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.url.absoluteString, forType: .string)
        finishPicker()
    }

    func moveSelection(by offset: Int) {
        guard !browsers.isEmpty else { return }
        let index = browsers.firstIndex { $0.id == selection } ?? (offset > 0 ? -1 : browsers.count)
        selection = browsers[min(max(index + offset, 0), browsers.count - 1)].id
    }

    func openSelected() {
        guard let link = pickerLink, let destination = selection, !openingFromPicker else { return }
        let remember = rememberChoice
        openingFromPicker = true
        pickerMessage = nil
        Task {
            do {
                try await open(link, at: destination)
            } catch {
                openingFromPicker = false
                pickerMessage = (error as? OpenFailure ?? .failed).message
                refresh()
                return
            }
            openingFromPicker = false
            if remember {
                var next = preferences
                next.remember(link.host, destination: destination)
                guard save(next) else {
                    let alert = NSAlert()
                    alert.messageText = "Link sent. Rule not saved."
                    alert.informativeText = settingsMessage ?? "Check settings and try again."
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                    finishPicker()
                    return
                }
            }
            finishPicker()
        }
    }
}
