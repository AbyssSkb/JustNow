import Foundation
import XCTest
import JustNowCore
@testable import JustNow

final class TopicSummaryTests: XCTestCase {
    func testAggregationCountsEventsAndDistinctRecordedIntervals() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = JournalEntry(start: start, end: start.addingTimeInterval(1_800), status: .recorded, events: [
            JournalEvent(topic: "Vellum", content: "调整段落"),
            JournalEvent(topic: "Vellum", content: "修改标题"),
            JournalEvent(content: "散步")
        ])
        let second = JournalEntry(start: start.addingTimeInterval(1_800), end: start.addingTimeInterval(3_600), status: .recorded, events: [
            JournalEvent(topic: "vellum", content: "整理笔记")
        ])
        let pending = JournalEntry(start: start.addingTimeInterval(3_600), end: start.addingTimeInterval(5_400), events: [
            JournalEvent(topic: "Vellum", content: "尚未提交")
        ])
        let legacy = JournalEntry(start: start.addingTimeInterval(5_400), end: start.addingTimeInterval(7_200),
                                  text: "Vellum 旧记录", status: .recorded)

        let summaries = TopicSummary.aggregate([legacy, second, pending, first])
        XCTAssertEqual(summaries.count, 2)
        let vellum = try XCTUnwrap(summaries.first { $0.id == "vellum" })
        XCTAssertEqual(vellum.eventCount, 3)
        XCTAssertEqual(vellum.entryIDs, [first.id, second.id])
        let other = try XCTUnwrap(summaries.first { $0.id.isEmpty })
        XCTAssertNil(other.name)
        XCTAssertEqual(other.eventCount, 1)
        XCTAssertEqual(other.entryIDs, [first.id])
        XCTAssertEqual(summaries.first?.id, "vellum")
    }
}
