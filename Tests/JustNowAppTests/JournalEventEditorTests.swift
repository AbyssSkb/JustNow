import XCTest
import JustNowCore
@testable import JustNow

final class JournalEventEditorTests: XCTestCase {
    func testReminderGrowsWithEventsAndStopsAtItsMaximum() {
        let first = PromptView.height(hasPrevious: true, hasClues: true)
        XCTAssertEqual(PromptView.height(editorHeight: 142, hasPrevious: true, hasClues: true), first + 52)
        XCTAssertEqual(PromptView.height(editorHeight: 1_000, hasPrevious: true, hasClues: true), 560)
        XCTAssertEqual(PromptView.height(hasPrevious: true, hasClues: true, hasError: true), first + 44)
    }

    func testRowsPreserveTopicsAndOmittedTopicsThroughRawRoundTrip() {
        let blank = JournalEventInputRow.rows(for: "")
        XCTAssertEqual(blank.count, 1)
        XCTAssertEqual(JournalEventInputRow.inputText(for: blank), "")

        let original = [JournalEventInputRow(topic: "Vellum", content: "review draft"),
                        JournalEventInputRow(content: "Read paper methods"),
                        JournalEventInputRow(topic: "开题报告"),
                        JournalEventInputRow(topic: "Other", content: "Other details")]
        let encoded = JournalEventInputRow.inputText(for: original)
        XCTAssertEqual(JournalEvents.parse(encoded), [JournalEvent(topic: "Vellum", content: "review draft"),
                                                     JournalEvent(content: "Read paper methods"),
                                                     JournalEvent(topic: "开题报告", content: ""),
                                                     JournalEvent(content: "Other details")])
        XCTAssertEqual(JournalEventInputRow.inputText(for: JournalEventInputRow.rows(for: encoded)), encoded)
    }
}
