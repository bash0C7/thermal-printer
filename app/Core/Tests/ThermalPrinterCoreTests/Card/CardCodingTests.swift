import Foundation
import Testing
@testable import ThermalPrinterCore

enum CardFixture {
    static let names = ["github", "slack", "url", "reminder"]

    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "test/fixtures/cards")

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appending(path: "\(name).json"))
    }

    static func card(_ name: String) throws -> Card {
        try JSONDecoder().decode(Card.self, from: data(name))
    }
}

@Suite struct CardCodingTests {
    @Test(arguments: CardFixture.names)
    func cardFixturesRoundTrip(name: String) throws {
        let card = try CardFixture.card(name)
        #expect(try JSONDecoder().decode(Card.self, from: JSONEncoder().encode(card)) == card)
    }

    @Test func githubFixtureCarriesTheDesignDocumentFields() throws {
        let card = try CardFixture.card("github")
        #expect(card.version == 1)
        #expect(card.kind == .github)
        #expect(card.url == "https://github.com/bash0C7/thermal-printer/issues/12")
        #expect(card.header.lines == ["bash0C7/thermal-printer"])
        #expect(card.header.emphasis == "#12")
        #expect(card.header.sublines == ["open ・ 更新 2日前"])
        #expect(card.sections.map(\.label) == [nil, "最新コメント"])
        #expect(card.note == nil)
    }

    @Test func reminderFixtureHasNoURLAndNoEmphasis() throws {
        let card = try CardFixture.card("reminder")
        #expect(card.kind == .reminder)
        #expect(card.url == nil)
        #expect(card.header.emphasis == nil)
    }

    @Test func kindsAreTheFourNamesOfTheSchema() {
        #expect(Card.Kind.allCases.map(\.rawValue) == ["github", "slack", "url", "reminder"])
    }

    @Test func unknownKindIsRejected() {
        let json = Data(#"{"version":1,"kind":"mail","url":null,"header":{"lines":["a"],"emphasis":null,"sublines":[]},"title":"t","sections":[]}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Card.self, from: json)
        }
    }

    @Test func encodedReminderKeepsUrlAndEmphasisAsExplicitNull() throws {
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(CardFixture.card("reminder"))) as? [String: Any]
        )
        #expect(Set(object.keys) == ["version", "kind", "url", "header", "title", "sections"])
        #expect(object["url"] is NSNull)
        let header = try #require(object["header"] as? [String: Any])
        #expect(header["emphasis"] is NSNull)
    }

    @Test func noteIsOnlyEncodedWhenPresent() throws {
        var card = try CardFixture.card("github")
        card.note = "要約モデルが使えないため先頭を切り詰めました"
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as? [String: Any])
        #expect(object["note"] as? String == card.note)
        #expect(try JSONDecoder().decode(Card.self, from: JSONEncoder().encode(card)) == card)
    }
}
