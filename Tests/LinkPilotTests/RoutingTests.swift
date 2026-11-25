import Foundation
import XCTest
@testable import LinkPilot

final class RoutingTests: XCTestCase {
    private let personal = Destination(bundleID: "com.google.Chrome", profileDirectory: "Default")
    private let work = Destination(bundleID: "com.google.Chrome", profileDirectory: "Profile 1")

    func testWebLinkNormalizesOnlyTheHost() throws {
        let input = try XCTUnwrap(URL(string: "https://BÜCHER.example.:8443/p%2Fread?next=%2fhome#Section"))
        let link = try XCTUnwrap(WebLink(input))
        XCTAssertEqual(link.host, "xn--bcher-kva.example")
        XCTAssertEqual(link.url.absoluteString, input.absoluteString)
        XCTAssertEqual(WebLink.normalize("bücher.example"), link.host)
        XCTAssertEqual(WebLink(URL(string: "http://[::1]:8000")!)?.host, "::1")
        XCTAssertNil(WebLink(URL(string: "file:///tmp/test")!))
        XCTAssertNil(WebLink(URL(string: "https:///path")!))
        XCTAssertNil(WebLink.normalize("example..com"))
    }

    func testRoutesRespectOrderingAndSubdomainBoundary() throws {
        let domain = DomainMatch(type: .domainAndSubdomains, host: "EXAMPLE.com.")
        let exact = DomainMatch(type: .exact, host: "docs.example.com")
        var preferences = Preferences(fallback: .init(type: .open, destination: personal), rules: [
            Rule(enabled: false, match: exact, destination: personal),
            Rule(match: domain, destination: work),
            Rule(match: exact, destination: personal),
        ])
        XCTAssertEqual(preferences.destination(for: "example.com"), work)
        XCTAssertEqual(preferences.destination(for: "docs.example.com"), work)
        XCTAssertEqual(preferences.destination(for: "falseexample.com"), personal)
        XCTAssertEqual(preferences.destination(for: "example.com.other"), personal)
        XCTAssertNil(DomainMatch(type: .domainAndSubdomains, host: "127.0.0.1").normalized)
        preferences.remember("docs.example.com", destination: personal)
        XCTAssertEqual(preferences.rules.count, 3)
        XCTAssertEqual(preferences.destination(for: "docs.example.com"), personal)
        XCTAssertEqual(preferences.destination(for: "other.example.com"), work)
    }

    @MainActor
    func testPickerQueuesEarlyLinksAndUnavailableDestination() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(file: directory.appending(path: "settings.json"))
        let unavailable = Destination(bundleID: "com.google.Chrome", profileDirectory: UUID().uuidString)
        let preferences = Preferences(fallback: .init(type: .open, destination: unavailable))
        try store.save(preferences)
        let coordinator = LinkCoordinator(store: store)
        let shown = expectation(description: "Presented the first queued link")
        coordinator.showPicker = { shown.fulfill() }
        coordinator.receive([
            URL(string: "file:///tmp/discard")!,
            URL(string: "https://example.com/first")!,
            URL(string: "http://example.com/second")!,
        ])
        XCTAssertNil(coordinator.pickerLink)
        coordinator.start()
        await fulfillment(of: [shown], timeout: 2)
        XCTAssertEqual(coordinator.pickerLink?.url.path, "/first")
        XCTAssertNotNil(coordinator.pickerMessage)
        coordinator.showPicker = nil
        coordinator.finishPicker()
        XCTAssertEqual(coordinator.pickerLink?.url.path, "/second")
        XCTAssertNotNil(coordinator.pickerMessage)
        coordinator.finishPicker()
        XCTAssertNil(coordinator.pickerLink)
    }

    func testSettingsRoundTripAndRejectInvalidVersions() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(file: directory.appending(path: "settings.json"))
        XCTAssertEqual(try store.load(), Preferences())
        var preferences = Preferences()
        preferences.remember("example.com", destination: personal)
        try store.save(preferences)
        XCTAssertEqual(try store.load(), preferences)

        preferences.version = 2
        let futureData = try JSONEncoder().encode(preferences)
        try futureData.write(to: store.file)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(preferences))
        XCTAssertEqual(try Data(contentsOf: store.file), futureData)
    }
}
