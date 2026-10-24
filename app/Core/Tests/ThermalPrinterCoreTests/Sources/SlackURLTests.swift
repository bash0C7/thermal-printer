import Foundation
import Testing
@testable import ThermalPrinterCore

@Test func slackPermalinkGivesWorkspaceChannelAndJSTTime() throws {
    let s = try #require(SlackURL("https://example.slack.com/archives/C0123456789/p1792565843307099"))
    #expect(s.workspace == "example")
    #expect(s.channelID == "C0123456789")
    #expect(s.jstText == "2026/10/21(水) 15:57")
}

@Test func slackTimestampIsSplitAsIntegersNotFloats() throws {
    let s = try #require(SlackURL("https://example.slack.com/archives/C0123456789/p1792565843999999"))
    #expect(s.seconds == 1792565843)
    #expect(s.microseconds == 999999)
}

@Test func slackTimeCrossesIntoTheNextJSTDayAtMidnight() throws {
    let s = try #require(SlackURL("https://example.slack.com/archives/C0123456789/p1792767600000000"))
    #expect(s.jstText == "2026/10/24(土) 00:00")
}

@Test func threadReplyKeepsTheWholeURLForTheQR() throws {
    let u = "https://example.slack.com/archives/C0123456789/p1792565843307099?thread_ts=1792565800.000100&cid=C0123456789"
    let s = try #require(SlackURL(u))
    #expect(s.card().url == u)
}

@Test func slackCardShowsWorkspaceChannelIDAndTimeInTheHeader() throws {
    let card = try #require(SlackURL("https://example.slack.com/archives/C0123456789/p1792565843307099")).card()
    #expect(card.kind == .slack)
    #expect(card.header.lines == ["example"])
    #expect(card.header.emphasis == "#C0123456789")
    #expect(card.header.sublines == ["2026/10/21(水) 15:57"])
    #expect(card.sections.isEmpty)
}

@Test(arguments: [
    "https://example.slack.com/archives/C0123456789",
    "https://example.slack.com/archives/C0123456789/p179256584330709",
    "https://example.slack.com/archives/C0123456789/p17925658433070990",
    "https://example.slack.com/archives/C0123456789/p179256584330709x",
    "https://example.com/archives/C0123456789/p1792565843307099",
    "https://slack.com/archives/C0123456789/p1792565843307099",
    "http://example.slack.com/archives/C0123456789/p1792565843307099",
    "https://example.slack.com/messages/C0123456789/p1792565843307099",
    "not a url",
])
func nonPermalinksAreNotSlackURLs(string: String) {
    #expect(SlackURL(string) == nil)
}

@Test func directMessageAndGroupChannelsAreAccepted() {
    #expect(SlackURL("https://example.slack.com/archives/D0123456789/p1792565843307099")?.channelID == "D0123456789")
    #expect(SlackURL("https://example.slack.com/archives/G0123456789/p1792565843307099")?.channelID == "G0123456789")
}

@Test func slackHandlerOnlyHandlesPermalinks() async throws {
    let handler = SlackURLHandler()
    let permalink = try #require(URL(string: "https://example.slack.com/archives/C0123456789/p1792565843307099"))
    let other = try #require(URL(string: "https://example.com/"))
    #expect(handler.handles(permalink))
    #expect(!handler.handles(other))
    #expect(try await handler.card(for: permalink).kind == .slack)
}
