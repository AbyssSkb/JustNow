import Foundation
import XCTest
@testable import JustNowCore

final class JournalEventTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var end: Date { start.addingTimeInterval(1_800) }

    func testParsingPreservesOtherAndUnfinishedItems() {
        let text = "Vellum 调整段落\r\nJustNow\t修复提醒\n开题报告　写背景\n  Read a paper\n散步\n其他 吃饭\nOTHER Taking a walk\n\t\nJustNow "
        XCTAssertEqual(JournalEvents.parse(text), [
            JournalEvent(topic: "Vellum", content: "调整段落"),
            JournalEvent(topic: "JustNow", content: "修复提醒"),
            JournalEvent(topic: "开题报告", content: "写背景"),
            JournalEvent(content: "Read a paper"),
            JournalEvent(content: "散步"),
            JournalEvent(content: "吃饭"),
            JournalEvent(content: "Taking a walk"),
            JournalEvent(topic: "JustNow", content: "")
        ])
        XCTAssertTrue(JournalEvents.parse(" \t\n\r\n").isEmpty)
    }

    func testInputRoundTripAndLegacyConversionDoNotInventTopics() {
        let events = [JournalEvent(topic: "JustNow", content: "Fix keyboard focus"),
                      JournalEvent(content: "Read a paper"), JournalEvent(content: "散步")]
        XCTAssertEqual(JournalEvents.parse(JournalEvents.inputText(for: events)), events)
        let legacy = "Read a paper\nJustNow 修复提醒\n\n  Already indented"
        XCTAssertEqual(JournalEvents.legacyInputText(legacy), " Read a paper\n JustNow 修复提醒\n\n   Already indented")
        XCTAssertEqual(JournalEvents.legacyInputText(""), "")
        XCTAssertEqual(JournalEvents.parse(JournalEvents.legacyInputText("Read a paper\r\nJustNow Fix reminders\u{2028}Review notes")), [
            JournalEvent(content: "Read a paper"), JournalEvent(content: "JustNow Fix reminders"), JournalEvent(content: "Review notes")
        ])
        XCTAssertEqual(JournalEvents.parse(JournalEvents.legacyInputText(legacy)), [
            JournalEvent(content: "Read a paper"), JournalEvent(content: "JustNow 修复提醒"),
            JournalEvent(content: "Already indented")
        ])
    }

    func testStructuredDraftsRejectIncompleteOrMismatchedSavesAtomically() throws {
        var state = JournalState()
        let entry = JournalEntry(start: start, end: end, createdAt: end,
                                 applicationUsage: ApplicationUsageSummary(start: start, end: end, activity: []))
        state.entries = [entry]
        let partial = "JustNow "
        state.setDraft(id: entry.id, text: partial, events: JournalEvents.parse(partial))
        try state.validate()
        let before = state
        XCTAssertThrowsError(try state.updateEntry(id: entry.id, text: partial, events: JournalEvents.parse(partial))) {
            XCTAssertEqual($0 as? JournalError, .emptyNote)
        }
        XCTAssertEqual(state, before)
        XCTAssertThrowsError(try state.updateEntry(id: entry.id, text: "JustNow 修复提醒", events: [JournalEvent(content: "Different")])) {
            XCTAssertEqual($0 as? JournalError, .invalidEvents)
        }
        XCTAssertEqual(state, before)
        let text = " Read a paper\nJustNow 修复提醒\n"
        try state.updateEntry(id: entry.id, text: text, events: JournalEvents.parse(text))
        XCTAssertEqual(state.entries[0].text, text)
        XCTAssertEqual(state.entries[0].events, JournalEvents.parse(text))
        XCTAssertEqual(state.entries[0].applicationUsage, entry.applicationUsage)
        XCTAssertEqual(state.entries[0].id, entry.id)
        XCTAssertEqual(state.entries[0].createdAt, entry.createdAt)
        try state.validate()
        state.entries[0].events = []
        XCTAssertThrowsError(try state.validate()) { XCTAssertEqual($0 as? JournalError, .invalidEvents) }
    }

    func testLegacyAndStructuredEntriesRoundTripTogether() throws {
        var state = JournalState()
        let legacy = "Read a paper\nJustNow 修复提醒"
        _ = try state.insertEntry(start: start, end: end, text: legacy)
        let text = "JustNow 修复提醒\n Read a paper"
        _ = try state.insertEntry(start: end, end: end.addingTimeInterval(1_800), text: text, events: JournalEvents.parse(text))
        let draft = JournalEditorDraft(entryID: nil, start: start, end: end, text: "Unsubmitted\nlegacy draft")
        state.editorDraft = draft
        state.updateContinuation = AppUpdateContinuation(preparedAt: end, sourceVersion: "0.1.11", targetVersion: "0.1.12", editorDraft: draft)
        let data = try JSONEncoder().encode(state)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try XCTUnwrap(json["entries"] as? [[String: Any]])
        XCTAssertNil(entries[0]["events"])
        XCTAssertNotNil(entries[1]["events"])
        let restored = try JSONDecoder().decode(JournalState.self, from: data)
        XCTAssertEqual(restored, state)
        XCTAssertNil(restored.entries[0].events)
        XCTAssertEqual(restored.entries[0].text, legacy)
        try restored.validate()
        state.editorDraft?.usesStructuredEvents = true
        let structuredDraft = try JSONDecoder().decode(JournalState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(structuredDraft.editorDraft?.usesStructuredEvents, true)
        XCTAssertNil(restored.editorDraft?.usesStructuredEvents)
    }
}
