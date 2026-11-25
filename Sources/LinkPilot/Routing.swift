import Foundation

struct Destination: Codable, Hashable {
    let bundleID: String
    var profileDirectory: String?
}

struct WebLink: Identifiable {
    let id = UUID()
    let url: URL
    let host: String

    init?(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.url?.host(percentEncoded: false),
              let normalized = Self.normalize(host) else { return nil }
        self.url = url
        self.host = normalized
    }

    static func normalize(_ input: String) -> String? {
        var host = input.lowercased()
        if host.hasSuffix(".") { host.removeLast() }
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        guard !host.isEmpty, !host.unicodeScalars.contains(where: {
            CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
        }), !host.contains(where: { "/\\?#@%".contains($0) }) else { return nil }

        if host.contains(":") {
            var address = in6_addr()
            return host.withCString { inet_pton(AF_INET6, $0, &address) } == 1 ? host : nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        guard let ascii = components.url?.host(percentEncoded: true)?.lowercased(),
              ascii.utf8.count <= 253,
              ascii.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({
                  let bytes = $0.utf8
                  return (1...63).contains(bytes.count) && bytes.first != 45 && bytes.last != 45 &&
                      bytes.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
              }) else { return nil }
        return ascii
    }

    static func isIPAddress(_ host: String) -> Bool {
        var address = in_addr()
        return host.contains(":") || host.withCString { inet_pton(AF_INET, $0, &address) } == 1
    }
}

struct DomainMatch: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case exact, domainAndSubdomains
        var id: Self { self }
        var title: String { self == .exact ? "Exact hostname" : "Hostname and subdomains" }
    }

    var type: Kind
    var host: String

    var normalized: DomainMatch? {
        guard let host = WebLink.normalize(host.trimmingCharacters(in: .whitespacesAndNewlines)),
              type == .exact || !WebLink.isIPAddress(host) else { return nil }
        return DomainMatch(type: type, host: host)
    }

    func matches(_ candidate: String) -> Bool {
        guard let match = normalized else { return false }
        return candidate == match.host ||
            (match.type == .domainAndSubdomains && candidate.hasSuffix("." + match.host))
    }
}

struct Rule: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var enabled = true
    var match: DomainMatch
    var destination: Destination
}

struct Preferences: Codable, Equatable {
    struct Fallback: Codable, Equatable {
        enum Kind: String, Codable { case ask, open }
        var type: Kind = .ask
        var destination: Destination?
    }

    var version = 1
    var fallback = Fallback()
    var rules: [Rule] = []

    func destination(for host: String) -> Destination? {
        if let rule = rules.first(where: { $0.enabled && $0.match.matches(host) }) {
            return rule.destination
        }
        return fallback.type == .open ? fallback.destination : nil
    }

    mutating func remember(_ host: String, destination: Destination) {
        let match = DomainMatch(type: .exact, host: host)
        var rule = Rule(match: match, destination: destination)
        if let index = rules.firstIndex(where: { $0.match.normalized == match }) {
            rule.id = rules.remove(at: index).id
        }
        rules.insert(rule, at: 0)
    }

    var isValid: Bool {
        version == 1 && (fallback.type != .open || fallback.destination != nil) &&
            Set(rules.map(\.id)).count == rules.count && rules.allSatisfy { $0.match.normalized != nil }
    }
}

struct SettingsStore {
    let file: URL

    func load() throws -> Preferences {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return Preferences()
        }
        let preferences = try JSONDecoder().decode(Preferences.self, from: data)
        guard preferences.isValid else { throw StoreError.invalid }
        return preferences
    }

    func save(_ preferences: Preferences) throws {
        guard preferences.isValid else { throw StoreError.invalid }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preferences)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }

    enum StoreError: Error { case invalid }
}
