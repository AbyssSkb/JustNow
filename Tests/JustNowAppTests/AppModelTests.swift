import Foundation
import XCTest
@testable import JustNow

final class AppModelTests: XCTestCase {
    @MainActor
    private func makeModel() -> AppModel {
        let model = AppModel(isDemo: true, showOnboarding: true)
        for entry in model.entries { model.deleteEntry(entry.id) }
        return model
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2024, month: 2, day: day, hour: hour, minute: minute))!
    }

    func testTodayRollsOverAndPromptSaveUpdatesCountsWithoutNavigation() async throws {
        try await MainActor.run {
            let model = makeModel()
            defer { try? FileManager.default.removeItem(at: model.dataDirectory) }
            model.now = at(6, 23, 55)
            model.selectedDay = model.now
            XCTAssertTrue(model.saveEditedEntry(id: nil, start: at(6, 22, 0), end: at(6, 22, 30), text: "Earlier"))
            XCTAssertTrue(model.saveEditedEntry(id: nil, start: at(6, 23, 50), end: at(7, 0, 20), text: "Draft"))
            let id = try XCTUnwrap(model.entries.last?.id)
            model.setDraft(id: id, text: "Unfinished note")
            model.dismissPrompt()
            XCTAssertEqual(model.completedCount, 1)
            XCTAssertEqual(model.pendingCount, 1)
            XCTAssertEqual(model.recordedDuration, 1_800)

            model.now = at(7, 0, 25)
            XCTAssertEqual(model.displayDay, model.now)
            XCTAssertEqual(model.selectedDay, at(6, 23, 55))
            XCTAssertEqual(model.selectedDayEntries.map(\.id), [id])
            XCTAssertEqual(model.completedCount, 0)
            XCTAssertEqual(model.pendingCount, 1)
            XCTAssertEqual(model.todayPendingCount, 1)
            XCTAssertEqual(model.recordedDuration, 0)

            model.openPendingEntry(id)
            XCTAssertEqual(model.promptEntryID, id)
            XCTAssertTrue(model.savePrompt(id: id, text: "Finished across midnight"))
            XCTAssertEqual(model.selectedSection, .today)
            XCTAssertEqual(model.selectedDayEntries.first?.text, "Finished across midnight")
            XCTAssertEqual(model.completedCount, 1)
            XCTAssertEqual(model.pendingCount, 0)
            XCTAssertEqual(model.todayPendingCount, 0)
            XCTAssertEqual(model.recordedDuration, 1_200)
            XCTAssertNil(model.promptEntryID)
        }
    }

    func testHistoryKeepsItsSelectedDateAndSearchWhenTodayChanges() async throws {
        try await MainActor.run {
            let model = makeModel()
            defer { try? FileManager.default.removeItem(at: model.dataDirectory) }
            XCTAssertTrue(model.saveEditedEntry(id: nil, start: at(6, 9, 0), end: at(6, 9, 30), text: "Read a paper"))
            XCTAssertTrue(model.saveEditedEntry(id: nil, start: at(6, 10, 0), end: at(6, 10, 15), text: "Write notes"))
            XCTAssertTrue(model.saveEditedEntry(id: nil, start: at(7, 0, 0), end: at(7, 0, 20), text: "Read more"))
            let firstDayIDs = Array(model.entries.prefix(2)).map(\.id)
            model.selectedSection = .history
            model.selectedDay = at(6, 12, 0)
            model.searchText = "read"
            model.now = at(7, 0, 25)
            XCTAssertEqual(model.displayDay, model.selectedDay)
            XCTAssertEqual(model.selectedDayEntries.map(\.id), [firstDayIDs[0]])
            XCTAssertEqual(model.completedCount, 1)
            XCTAssertEqual(model.recordedDuration, 1_800)

            model.now = at(8, 0, 25)
            XCTAssertEqual(model.selectedDay, at(6, 12, 0))
            XCTAssertEqual(model.searchText, "read")
            XCTAssertEqual(model.selectedDayEntries.map(\.id), [firstDayIDs[0]])
            model.searchText = ""
            XCTAssertEqual(model.selectedDayEntries.map(\.id), firstDayIDs)
            XCTAssertEqual(model.completedCount, 2)
            XCTAssertEqual(model.recordedDuration, 2_700)
            XCTAssertTrue(model.saveEditedEntry(id: nil, start: at(8, 0, 0), end: at(8, 0, 20), text: "Today's draft"))
            let id = try XCTUnwrap(model.entries.last?.id)
            model.setDraft(id: id, text: "Unfinished")
            model.dismissPrompt()
            model.searchText = "no match"
            XCTAssertTrue(model.selectedDayEntries.isEmpty)
            XCTAssertEqual(model.pendingCount, 0)
            XCTAssertEqual(model.todayPendingCount, 1)
        }
    }

    func testSameDaySaveEditDraftAndDeleteAppearImmediately() async throws {
        try await MainActor.run {
            let model = makeModel()
            defer { try? FileManager.default.removeItem(at: model.dataDirectory) }
            model.now = at(7, 12, 0)
            model.selectedDay = model.now
            XCTAssertTrue(model.saveEditedEntry(id: nil, start: at(7, 9, 0), end: at(7, 9, 30), text: "First"))
            XCTAssertTrue(model.saveEditedEntry(id: nil, start: at(7, 10, 0), end: at(7, 10, 30), text: "Second"))
            let id = try XCTUnwrap(model.entries.last?.id)
            XCTAssertEqual(model.selectedDayEntries.map(\.text), ["Second", "First"])

            XCTAssertFalse(model.saveEditedEntry(id: id, start: at(7, 10, 0), end: at(7, 9, 45), text: "Edited"))
            XCTAssertNotNil(model.errorMessage)
            XCTAssertTrue(model.saveEditedEntry(id: id, start: at(7, 10, 0), end: at(7, 10, 45), text: "Edited"))
            XCTAssertNil(model.errorMessage)
            XCTAssertEqual(model.selectedDayEntries.first?.text, "Edited")
            XCTAssertEqual(model.recordedDuration, 4_500)
            model.setDraft(id: id, text: "Still editing")
            model.dismissPrompt()
            XCTAssertEqual(model.selectedDayEntries.first?.text, "Still editing")
            XCTAssertEqual(model.pendingCount, 1)
            XCTAssertEqual(model.completedCount, 1)
            XCTAssertEqual(model.recordedDuration, 1_800)
            XCTAssertFalse(model.savePrompt(id: id, text: " \n"))
            XCTAssertNotNil(model.errorMessage)
            XCTAssertTrue(model.savePrompt(id: id, text: "Done"))
            XCTAssertNil(model.errorMessage)
            XCTAssertEqual(model.selectedDayEntries.first?.text, "Done")
            XCTAssertEqual(model.pendingCount, 0)
            XCTAssertEqual(model.completedCount, 2)
            XCTAssertEqual(model.recordedDuration, 4_500)

            model.deleteEntry(id)
            XCTAssertEqual(model.selectedDayEntries.map(\.text), ["First"])
            XCTAssertEqual(model.completedCount, 1)
            XCTAssertEqual(model.recordedDuration, 1_800)
            XCTAssertEqual(model.selectedSection, .today)
        }
    }
}
