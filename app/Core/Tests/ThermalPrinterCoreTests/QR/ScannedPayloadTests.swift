import Foundation
import Testing
@testable import ThermalPrinterCore

@Test(arguments: [
    "taskforge:///task/a", "obsidian://open?vault=v&file=f", "x-apple-reminderkit://REMCDReminder/1",
    "https://github.com/a/b/issues/1", "HTTP://example.com",
])
func linksThisAppPutsInQRsAreOpened(text: String) {
    #expect(ScannedPayload.classify(text) == .open(URL(string: text)!))
}

@Test(arguments: ["file:///etc/passwd", "javascript:alert(1)", "tel:0120", "会議メモの原文です", "", "https://"])
func anythingElseIsShownNotOpened(text: String) {
    #expect(ScannedPayload.classify(text) == .show(text))
}

@Test(arguments: [
    "obsidian://new?vault=v&file=f&content=x&overwrite=true", "obsidian://advanced-uri?vault=v&commandid=x",
    "taskforge:///add?title=x", "taskforge://task/a", "taskforge:///",
])
func linksOfThisAppsSchemesThatDoNotOpenAnExistingNoteOrTaskAreShownNotOpened(text: String) {
    #expect(ScannedPayload.classify(text) == .show(text))
}
