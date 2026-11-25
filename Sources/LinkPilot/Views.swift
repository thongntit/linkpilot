import AppKit
import SwiftUI

struct LinkPicker: View {
    @ObservedObject var model: LinkCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let link = model.pickerLink {
                Text(link.host)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(link.url.absoluteString)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(link.url.absoluteString)
                    .accessibilityLabel(link.url.absoluteString)
                if let message = model.pickerMessage {
                    Text(message).font(.callout).foregroundStyle(.orange)
                }
                if model.browsers.isEmpty {
                    ContentUnavailableView("No browsers available", systemImage: "globe",
                                           description: Text("Copy the link or refresh the browser list."))
                    Button("Refresh") { model.refresh() }
                } else {
                    destinationList
                    Toggle("Remember for this hostname", isOn: $model.rememberChoice)
                        .disabled(model.storageLocked || model.openingFromPicker)
                }
                Spacer(minLength: 0)
                HStack {
                    Button("Copy Link") { model.copyPickerLink() }
                    Spacer()
                    if model.openingFromPicker {
                        ProgressView().controlSize(.small)
                    }
                    Button("Cancel") { model.finishPicker() }
                    Button("Open") { model.openSelected() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.selection == nil)
                }
                .disabled(model.openingFromPicker)
            }
        }
        .padding(20)
        .frame(width: 470, height: 440, alignment: .topLeading)
    }

    private var destinationList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.browsers) { browser in
                        let selected = model.selection == browser.id
                        Button {
                            model.selection = browser.id
                        } label: {
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: browser.appURL.path))
                                    .resizable()
                                    .frame(width: 28, height: 28)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(browser.title).fontWeight(.medium)
                                    if let subtitle = browser.subtitle {
                                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if selected {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(8)
                            .background(selected ? Color.accentColor.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .id(browser.id)
                    }
                }
            }
            .onChange(of: model.selection, initial: true) { _, destination in
                if let destination { proxy.scrollTo(destination) }
            }
        }
        .disabled(model.openingFromPicker)
    }
}

struct SettingsView: View {
    @ObservedObject var model: LinkCoordinator
    @State private var tab = "general"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let message = model.settingsMessage {
                HStack {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Reload Settings") { model.reloadSettings() }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            TabView(selection: $tab) {
                general.tabItem { Label("General", systemImage: "gearshape") }.tag("general")
                RulesView(model: model).tabItem { Label("Rules", systemImage: "list.bullet") }.tag("rules")
            }
        }
        .padding(14)
        .frame(minWidth: 570, minHeight: 370)
    }

    private var general: some View {
        Form {
            Section("Default browser") {
                LabeledContent("System handlers", value: model.handlerStatus)
                Button("Set LinkPilot as Default…") { model.requestDefaultBrowser() }
                    .disabled(model.isDefaultBrowser || model.requestingDefaultBrowser)
                Button("Open Desktop & Dock Settings") { model.openDefaultBrowserSettings() }
            }
            Section("When no rule matches") {
                Picker("Open links with", selection: fallbackDestination) {
                    Text("Ask every time").tag(nil as Destination?)
                    ForEach(model.browsers) { browser in
                        Text(browser.displayName).tag(Optional(browser.id))
                    }
                    if let missing = missingDefault {
                        Text("Unavailable · " + missing.description).tag(Optional(missing))
                    }
                }
                .disabled(model.storageLocked)
                Button("Refresh Browsers") { model.refresh() }
                if model.chromeProfilesUnavailable {
                    Text("LinkPilot couldn’t read Chrome’s profile list. Chrome Default is still available.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Choose Chrome Profile Folder…") { model.chooseChromeProfileFolder() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var missingDefault: Destination? {
        guard let destination = fallbackDestination.wrappedValue,
              !model.browsers.contains(where: { $0.id == destination }) else { return nil }
        return destination
    }

    private var fallbackDestination: Binding<Destination?> {
        Binding {
            let fallback = model.preferences.fallback
            return fallback.type == .open ? fallback.destination : nil
        } set: { selected in
            var next = model.preferences
            next.fallback = .init(type: selected == nil ? .ask : .open, destination: selected)
            model.save(next)
        }
    }
}

private struct RulesView: View {
    @ObservedObject var model: LinkCoordinator
    @State private var selectedID: String?
    @State private var draft: Rule?
    @State private var confirmingRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Table(model.preferences.rules, selection: $selectedID) {
                TableColumn("On") { rule in
                    Toggle("Enabled", isOn: Binding(get: { rule.enabled }, set: { enabled in
                        update(rule.id) { $0.enabled = enabled }
                    }))
                    .labelsHidden()
                    .disabled(model.storageLocked)
                }
                .width(34)
                TableColumn("Hostname") { Text($0.match.host) }
                TableColumn("Match") { Text($0.match.type.title) }
                TableColumn("Open with") { rule in
                    Text(model.browsers.first { $0.id == rule.destination }?.displayName ??
                         "Unavailable · " + rule.destination.description)
                }
            }
            HStack {
                Button("Add Rule…") {
                    if let browser = model.browsers.first {
                        draft = Rule(match: DomainMatch(type: .exact, host: ""), destination: browser.id)
                    }
                }
                .disabled(model.browsers.isEmpty)
                Button("Edit…") { draft = selected }
                    .disabled(selected == nil)
                Button("Remove…") { confirmingRemoval = true }
                    .disabled(selected == nil)
                Spacer()
                Button { move(-1) } label: { Image(systemName: "chevron.up") }
                    .accessibilityLabel("Move rule up")
                    .disabled(index.map { $0 == 0 } ?? true)
                Button { move(1) } label: { Image(systemName: "chevron.down") }
                    .accessibilityLabel("Move rule down")
                    .disabled(index.map { $0 == model.preferences.rules.count - 1 } ?? true)
            }
            .disabled(model.storageLocked)
            Text("Rules run from top to bottom. The first match wins.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(12)
        .sheet(item: $draft) { rule in
            RuleEditor(rule: rule, browsers: model.browsers) { edited in
                var next = model.preferences
                if let existing = next.rules.firstIndex(where: { $0.id == edited.id }) {
                    next.rules[existing] = edited
                } else {
                    next.rules.append(edited)
                }
                if model.save(next) {
                    selectedID = edited.id
                    return true
                }
                return false
            }
        }
        .confirmationDialog("Remove the selected rule?", isPresented: $confirmingRemoval) {
            Button("Remove", role: .destructive) {
                guard let index else { return }
                var next = model.preferences
                next.rules.remove(at: index)
                if model.save(next) { selectedID = nil }
            }
        }
    }

    private var index: Int? { model.preferences.rules.firstIndex { $0.id == selectedID } }

    private var selected: Rule? { index.map { model.preferences.rules[$0] } }

    private func update(_ id: String, _ change: (inout Rule) -> Void) {
        var next = model.preferences
        guard let index = next.rules.firstIndex(where: { $0.id == id }) else { return }
        change(&next.rules[index])
        model.save(next)
    }

    private func move(_ offset: Int) {
        guard let index else { return }
        var next = model.preferences
        let target = index + offset
        guard next.rules.indices.contains(target) else { return }
        next.rules.swapAt(index, target)
        model.save(next)
    }
}

private struct RuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var rule: Rule
    @State private var saveError = false
    let browsers: [Browser]
    let save: (Rule) -> Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            Form {
                TextField("Hostname", text: $rule.match.host, prompt: Text("example.com"))
                Picker("Match", selection: $rule.match.type) {
                    ForEach(DomainMatch.Kind.allCases) { Text($0.title).tag($0) }
                }
                Picker("Open with", selection: $rule.destination) {
                    ForEach(browsers) { browser in
                        Text(browser.displayName).tag(browser.id)
                    }
                    if !browsers.contains(where: { $0.id == rule.destination }) {
                        Text("Unavailable · " + rule.destination.description).tag(rule.destination)
                    }
                }
            }
            if saveError { Text("Couldn’t save this rule.").foregroundStyle(.orange) }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard let match = rule.match.normalized else { return }
                    rule.match = match
                    if save(rule) { dismiss() } else { saveError = true }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(rule.match.normalized == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

private extension Destination {
    var description: String {
        if let profileDirectory {
            return "Google Chrome · " + profileDirectory
        }
        return BrowserRegistry.supported.first { $0.0 == bundleID }?.1 ?? bundleID
    }
}

private extension Browser {
    var displayName: String {
        guard let subtitle else { return title }
        return "\(title) (\(subtitle))"
    }
}
