import AppKit
import Combine
import CoreGraphics
import ServiceManagement
import UniformTypeIdentifiers
import JustNowCore

enum AppSection: String, CaseIterable {
    case today, history, topics, settings
}

struct EntryEditorRequest: Identifiable {
    let id = UUID()
    var entry: JournalEntry?
    var draft: JournalEditorDraft? = nil
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var journal: JournalState
    @Published var now = Date()
    @Published var selectedSection: AppSection = .today {
        didSet {
            if selectedSection == .today { selectedDay = Date(); searchText = "" }
        }
    }
    @Published var selectedDay = Date()
    @Published var searchText = ""
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var hasStorageError = false
    @Published var presentedEditor: EntryEditorRequest?
    @Published var editorDraft: JournalEditorDraft? {
        didSet {
            if editorDraft != oldValue, editorDraft != journal.editorDraft { scheduleDraftSave() }
        }
    }
    @Published var promptEntryID: UUID?
    @Published var showingPauseResolution = false
    @Published private(set) var launchAtLogin = false

    let isDemo: Bool
    let dataDirectory: URL
    var onShowMainWindow: (() -> Void)?
    private let storage: JournalStorage
    private let applicationTracker: ApplicationUsageTracker?
    private let idleSeconds: () -> TimeInterval
    private let resumedUpdate: Bool
    private var storageLoaded = true
    private var timer: Timer?
    private var lastCheckpoint = Date()
    private var promptQueue: [UUID] = []
    private var drafts: [UUID: String] = [:]
    private var draftSave: DispatchWorkItem?
    private var environmentPauses: Set<ApplicationUsageTracker.PauseReason> = []
    private var beganOnLaunch = false
    private var offeredPauseResolution = false
    private var updating = false

    init(isDemo: Bool = false, showOnboarding: Bool = false, dataDirectory: URL? = nil,
         appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0.1.15",
         trackApplicationUsage: Bool = true, applicationTracker: ApplicationUsageTracker? = nil,
         idleSeconds: @escaping () -> TimeInterval = {
             CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
         }) {
        self.isDemo = isDemo
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.dataDirectory = dataDirectory ?? (isDemo
            ? FileManager.default.temporaryDirectory.appendingPathComponent("JustNow-Preview-\(UUID().uuidString)")
            : base.appendingPathComponent("JustNow", isDirectory: true))
        storage = JournalStorage(directory: self.dataDirectory)
        self.applicationTracker = !isDemo && trackApplicationUsage ? (applicationTracker ?? ApplicationUsageTracker()) : nil
        self.idleSeconds = idleSeconds
        var loaded = JournalState()
        var failure: String?
        var continuation: AppUpdateContinuation?
        var due: [UUID] = []
        let launchDate = Date()
        do {
            loaded = isDemo ? Self.demoJournal(showOnboarding: showOnboarding) : try storage.load()
            if !isDemo {
                let previous = loaded
                let wasRecording = loaded.isRecording
                let existing = Set(loaded.entries.map(\.id))
                continuation = loaded.consumeUpdateContinuation(at: launchDate, appVersion: appVersion)
                if continuation == nil { _ = loaded.recoverInterruptedSession() }
                if let draft = continuation?.editorDraft { loaded.editorDraft = draft }
                if let id = loaded.editorDraft?.entryID, !loaded.entries.contains(where: { $0.id == id }) {
                    loaded.editorDraft = nil
                }
                due = loaded.entries.filter { !existing.contains($0.id) }.map(\.id)
                if wasRecording || previous.updateContinuation != nil || previous.editorDraft != loaded.editorDraft {
                    do { try storage.save(loaded) }
                    catch {
                        loaded = previous
                        loaded.updateContinuation = nil
                        _ = loaded.recoverInterruptedSession()
                        continuation = nil
                        due = []
                        throw error
                    }
                }
            }
        } catch {
            storageLoaded = false
            failure = error.localizedDescription
        }
        journal = loaded
        resumedUpdate = continuation != nil
        hasStorageError = !storageLoaded
        if let continuation {
            promptEntryID = continuation.promptEntryID.flatMap { id in
                loaded.entries.contains(where: { $0.id == id && $0.isPending }) ? id : nil
            }
            promptQueue = (continuation.promptQueue ?? []).filter { id in
                id != promptEntryID && loaded.entries.contains(where: { $0.id == id && $0.isPending })
            }
            if promptEntryID == nil { promptEntryID = nextQueuedEntry() }
            showDueEntries(due)
        }
        if let draft = loaded.editorDraft,
           draft.entryID == nil || loaded.entries.contains(where: { $0.id == draft.entryID }) {
            editorDraft = draft
            presentedEditor = EntryEditorRequest(entry: loaded.entries.first { $0.id == draft.entryID }, draft: draft)
        }
        if let failure {
            errorMessage = text("读取日志失败。原文件已保留，请打开数据文件夹或从备份恢复。", "Your journal could not be loaded. The original file is preserved; open its folder or restore the backup.") + "\n" + failure
        }
        if !isDemo { launchAtLogin = SMAppService.mainApp.status == .enabled }
        syncApplicationTracking(at: launchDate)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    var preferences: Preferences { journal.preferences }
    var entries: [JournalEntry] { journal.entries }
    func previousEntry(for entryID: UUID) -> JournalEntry? {
        guard let entry = entries.first(where: { $0.id == entryID }) else { return nil }
        return entries.filter { $0.id != entryID && $0.end <= entry.start }.max { $0.end < $1.end }
    }
    var isRecording: Bool { journal.isRecording && !isPaused }
    var isPaused: Bool { journal.pauseDate != nil }
    var pauseDate: Date? { journal.pauseDate }
    var currentSegmentStart: Date? { journal.session?.segmentStartedAt }
    var nextReminderDate: Date? {
        guard !isPaused, let session = journal.session else { return nil }
        return session.segmentStartedAt.addingTimeInterval(Double(session.intervalMinutes) * 60)
    }
    var remainingSeconds: TimeInterval { max(0, nextReminderDate?.timeIntervalSince(now) ?? 0) }
    var progress: Double {
        guard let session = journal.session else { return 0 }
        return min(1, max(0, (pauseDate ?? now).timeIntervalSince(session.segmentStartedAt) / (Double(session.intervalMinutes) * 60)))
    }
    var pendingEntries: [JournalEntry] { entries.filter(\.isPending).sorted { $0.start < $1.start } }
    var displayDay: Date { selectedSection == .today ? now : selectedDay }
    var selectedDayEntries: [JournalEntry] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: displayDay)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter {
            $0.start < dayEnd && $0.end > dayStart && (query.isEmpty || $0.text.localizedCaseInsensitiveContains(query))
        }.sorted { selectedSection == .today ? $0.start > $1.start : $0.start < $1.start }
    }
    var recordedDuration: TimeInterval {
        let start = Calendar.current.startOfDay(for: displayDay)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return selectedDayEntries.filter { !$0.isPending }.reduce(0) {
            $0 + max(0, min($1.end, end).timeIntervalSince(max($1.start, start)))
        }
    }
    var pendingCount: Int { selectedDayEntries.filter(\.isPending).count }
    var completedCount: Int { selectedDayEntries.filter { !$0.isPending }.count }
    var todayPendingCount: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return entries.filter { $0.isPending && $0.start < end && $0.end > start }.count
    }

    func text(_ chinese: String, _ english: String) -> String {
        preferences.language.usesChinese ? chinese : english
    }

    func startRecording() {
        if isPaused {
            offeredPauseResolution = true
            showingPauseResolution = true
            showMainWindow()
            return
        }
        guard !isRecording else { return }
        now = Date()
        var started = false
        if commit(at: now, { started = $0.start(at: now) }) {
            lastCheckpoint = now
            if !started {
                errorMessage = text("有一条记录延伸到了未来，请先调整它的结束时间。", "A journal entry extends into the future. Adjust its end time before starting.")
            }
        }
    }

    func stopRecording() {
        guard journal.isRecording else { return }
        now = Date()
        var due: [UUID] = []
        if commit(at: now, { due = $0.stop(at: now); applyDrafts(to: &$0) }) {
            showingPauseResolution = false
            showDueEntries(due)
        }
    }

    func updatePreferences(_ preferences: Preferences) {
        _ = commit { $0.preferences = preferences }
    }

    func completeOnboarding() {
        if commit({ $0.preferences.completedOnboarding = true }) { beginOnLaunch() }
    }

    func beginOnLaunch() {
        guard !beganOnLaunch, !isDemo, storageLoaded, preferences.completedOnboarding else { return }
        beganOnLaunch = true
        if isPaused {
            offerPauseResolutionIfActive()
            return
        }
        if !resumedUpdate && preferences.autoStartRecording != false { startRecording() }
    }

    @discardableResult
    func resolvePause(recordGap: Bool) -> Bool {
        guard let boundary = pauseDate, environmentPauses.isEmpty else { return false }
        now = Date()
        guard now >= boundary else { return false }
        var due: [UUID] = []
        guard commit(at: now, { state in
            applyDrafts(to: &state)
            due = state.resume(at: now, recordGap: recordGap)
        }) else { return false }
        showingPauseResolution = false
        offeredPauseResolution = false
        lastCheckpoint = now
        if promptEntryID == nil { promptEntryID = nextQueuedEntry() }
        showDueEntries(due)
        return !isPaused && isRecording
    }

    func setEnvironmentPaused(_ paused: Bool, for reason: ApplicationUsageTracker.PauseReason, at date: Date = Date()) {
        if paused {
            environmentPauses.insert(reason)
            showingPauseResolution = false
            pauseRecording(at: date)
        } else {
            environmentPauses.remove(reason)
        }
    }

    func setDraft(id: UUID, text: String) {
        drafts[id] = text
        scheduleDraftSave()
    }

    private func scheduleDraftSave() {
        draftSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { _ = self?.flushDrafts() }
        }
        draftSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func savePrompt(id: UUID, text: String) -> Bool {
        guard commit({ applyDrafts(to: &$0); try $0.updateEntry(id: id, text: text, events: JournalEvents.parse(text)) }) else { return false }
        drafts.removeValue(forKey: id)
        draftSave?.cancel()
        promptQueue.removeAll()
        promptEntryID = nil
        errorMessage = nil
        return true
    }

    func canDiscardPrompt(_ id: UUID) -> Bool {
        guard let entry = entries.first(where: { $0.id == id }), entry.isPending,
              (drafts[id] ?? entry.text).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return ![editorDraft, journal.editorDraft].compactMap { $0 }.contains {
            $0.entryID == id && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    @discardableResult
    func discardPrompt(id: UUID) -> Bool {
        guard canDiscardPrompt(id) else { return false }
        guard commit({ state in
            applyDrafts(to: &state)
            state.deleteEntry(id: id)
            if state.editorDraft?.entryID == id { state.editorDraft = nil }
        }) else { return false }
        drafts.removeValue(forKey: id)
        promptQueue.removeAll { $0 == id }
        if promptEntryID == id { promptEntryID = nextQueuedEntry() }
        if editorDraft?.entryID == id {
            editorDraft = nil
            presentedEditor = nil
        }
        errorMessage = nil
        return true
    }

    func dismissPrompt() {
        guard flushDrafts() else { return }
        promptQueue.removeAll()
        promptEntryID = nil
    }

    func openPendingEntry(_ id: UUID) {
        guard presentedEditor == nil else { showMainWindow(); return }
        guard entries.contains(where: { $0.id == id && $0.isPending }), flushDrafts() else { return }
        promptQueue.removeAll()
        promptEntryID = id
    }

    func openEditor(_ entry: JournalEntry? = nil) {
        guard presentedEditor == nil else { showMainWindow(); return }
        if promptEntryID != nil {
            dismissPrompt()
            guard promptEntryID == nil else { return }
        }
        guard flushDrafts() else { return }
        let current = entry.flatMap { item in entries.first { $0.id == item.id } }
        let draft = editorDraft?.entryID == current?.id ? editorDraft : nil
        presentedEditor = EntryEditorRequest(entry: current, draft: draft)
    }

    @discardableResult
    func discardEditorDraft() -> Bool {
        guard commit({ state in
            applyDrafts(to: &state)
            state.editorDraft = nil
        }) else { return false }
        editorDraft = nil
        presentedEditor = nil
        return true
    }

    func saveEditedEntry(id: UUID?, start: Date, end: Date, text: String) -> Bool {
        guard end <= Date().addingTimeInterval(1) else {
            errorMessage = self.text("请记录已经过去的时间，结束时间不能晚于现在。", "Journal entries describe time already spent. The end cannot be in the future.")
            return false
        }
        let result = commit { state in
            applyDrafts(to: &state)
            if let id { try state.updateEntry(id: id, text: text, start: start, end: end, events: JournalEvents.parse(text)) }
            else { _ = try state.insertEntry(start: start, end: end, text: text, events: JournalEvents.parse(text)) }
            state.editorDraft = nil
        }
        if result {
            if let id { drafts.removeValue(forKey: id) }
            presentedEditor = nil
            editorDraft = nil
            errorMessage = nil
        }
        return result
    }

    func deleteEntry(_ id: UUID) {
        if commit({ state in
            applyDrafts(to: &state)
            state.deleteEntry(id: id)
            state.editorDraft = nil
        }) {
            drafts.removeValue(forKey: id)
            promptQueue.removeAll { $0 == id }
            if promptEntryID == id { promptEntryID = nextQueuedEntry() }
            presentedEditor = nil
            editorDraft = nil
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !isDemo else { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin {
                statusMessage = text("请在系统设置的登录项中允许 JustNow。", "Allow JustNow in System Settings → Login Items.")
            }
        } catch { report(error) }
    }

    func exportCSV() {
        guard flushDrafts() else { return }
        export(data: Data(JournalExport.csv(entries: entries).utf8), filename: "JustNow-journal.csv", type: .commaSeparatedText)
    }

    func exportJSON() {
        guard flushDrafts() else { return }
        do { export(data: try JournalExport.json(entries: entries), filename: "JustNow-journal.json", type: .json) }
        catch { report(error) }
    }

    private func export(data: Data, filename: String, type: UTType) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = filename
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url, options: .atomic)
                statusMessage = text("日志已导出。", "Journal exported.")
            } catch { report(error) }
        }
    }

    func revealDataDirectory() {
        do { try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true) }
        catch { report(error); return }
        NSWorkspace.shared.open(dataDirectory)
    }

    func restoreBackup() {
        do {
            var restored = try storage.restoreBackup()
            _ = restored.recoverInterruptedSession()
            try storage.save(restored)
            let date = Date()
            applicationTracker?.stop(at: date)
            applicationTracker?.acknowledge(through: date)
            draftSave?.cancel()
            drafts.removeAll()
            promptQueue.removeAll()
            promptEntryID = nil
            presentedEditor = nil
            journal = restored
            editorDraft = restored.editorDraft
            if let draft = editorDraft,
               draft.entryID == nil || entries.contains(where: { $0.id == draft.entryID }) {
                presentedEditor = EntryEditorRequest(entry: entries.first { $0.id == draft.entryID }, draft: draft)
            }
            storageLoaded = true
            hasStorageError = false
            errorMessage = nil
            statusMessage = text("已恢复上一次保存的日志，原文件也已保留。", "The previous journal was restored. The original file was preserved.")
        } catch { report(error) }
    }

    func showMainWindow() {
        onShowMainWindow?()
    }

    func showSettings() {
        selectedSection = .settings
        showMainWindow()
    }

    func quit() { NSApp.terminate(nil) }

    func prepareForQuit() -> Bool {
        draftSave?.cancel()
        guard storageLoaded else { return true }
        if updating, let continuation = journal.updateContinuation {
            let prepared = prepareForUpdate(sourceVersion: continuation.sourceVersion, targetVersion: continuation.targetVersion)
            if prepared { applicationTracker?.stop(at: now) }
            return prepared
        }
        let date = Date()
        return commit(at: date) { state in
            applyDrafts(to: &state)
            state.updateContinuation = nil
            if state.pauseDate == nil { _ = state.stop(at: date) }
        }
    }

    func prepareForUpdate(sourceVersion: String, targetVersion: String) -> Bool {
        guard !sourceVersion.isEmpty, !targetVersion.isEmpty else { return false }
        draftSave?.cancel()
        now = Date()
        var due: [UUID] = []
        guard commit(at: now, { state in
            applyDrafts(to: &state)
            due = state.advance(to: now)
            state.updateContinuation = AppUpdateContinuation(
                preparedAt: now, sourceVersion: sourceVersion, targetVersion: targetVersion,
                promptEntryID: promptEntryID ?? due.first,
                promptQueue: promptQueue + due.filter { $0 != (promptEntryID ?? due.first) && !promptQueue.contains($0) },
                editorDraft: editorDraft ?? (presentedEditor == nil ? nil : journal.updateContinuation?.editorDraft))
        }) else { return false }
        updating = true
        lastCheckpoint = now
        showDueEntries(due)
        return true
    }

    @discardableResult
    func cancelPreparedUpdate() -> Bool {
        updating = false
        guard journal.updateContinuation != nil else { return true }
        if commit({ $0.updateContinuation = nil }) { return true }
        journal.updateContinuation = nil
        return false
    }

    func handleSleep() {
        setEnvironmentPaused(true, for: .systemSleep)
    }

    func handleWake() {
        now = Date()
        setEnvironmentPaused(false, for: .systemSleep, at: now)
    }

    private func pauseRecording(at date: Date) {
        guard journal.isRecording, !isPaused else { return }
        draftSave?.cancel()
        var paused = journal
        paused.appendApplicationActivity(applicationTracker?.snapshot(at: date) ?? [])
        applyDrafts(to: &paused)
        let due = paused.pause(at: date)
        offeredPauseResolution = false
        // Preserve the paused in-memory state even if the disk becomes unavailable.
        do {
            try storage.save(paused)
            applicationTracker?.acknowledge(through: date)
        } catch { report(error) }
        applicationTracker?.stop(at: date)
        journal = paused
        lastCheckpoint = date
        promptQueue.append(contentsOf: due.filter { !promptQueue.contains($0) && $0 != promptEntryID })
    }

    func showDemoReminder() {
        if let id = pendingEntries.last?.id { openPendingEntry(id) }
    }

    func tick(at date: Date = Date()) {
        now = date
        guard storageLoaded, journal.isRecording else { return }
        if isPaused {
            offerPauseResolutionIfActive()
            return
        }
        let inactivity = idleSeconds()
        if !environmentPauses.isEmpty || (!isDemo && preferences.pauseWhenInactive != false && inactivity.isFinite && inactivity >= 1_800) {
            pauseRecording(at: now)
            return
        }
        guard nextReminderDate.map({ $0 <= now }) == true || now.timeIntervalSince(lastCheckpoint) >= 60 else { return }
        var due: [UUID] = []
        if commit(at: now, { state in
            due = state.advance(to: now)
            applyDrafts(to: &state)
        }) {
            lastCheckpoint = now
            if !due.isEmpty {
                if preferences.playSound { NSSound(named: "Tink")?.play() }
                showDueEntries(due)
            }
        }
    }

    private func offerPauseResolutionIfActive() {
        let inactivity = idleSeconds()
        guard !offeredPauseResolution, presentedEditor == nil, promptEntryID == nil,
              environmentPauses.isEmpty, inactivity.isFinite, inactivity >= 0, inactivity < 2 else { return }
        offeredPauseResolution = true
        showingPauseResolution = true
        selectedSection = .today
        showMainWindow()
    }

    private func showDueEntries(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        if promptEntryID == nil {
            promptEntryID = ids.first
            promptQueue = Array(ids.dropFirst())
        } else {
            promptQueue.append(contentsOf: ids.filter { !promptQueue.contains($0) && $0 != promptEntryID })
        }
    }

    private func nextQueuedEntry() -> UUID? {
        while !promptQueue.isEmpty {
            let id = promptQueue.removeFirst()
            if entries.contains(where: { $0.id == id && $0.isPending }) { return id }
        }
        return nil
    }

    @discardableResult
    private func flushDrafts() -> Bool {
        draftSave?.cancel()
        guard !drafts.isEmpty || editorDraft != journal.editorDraft else { return true }
        return commit { applyDrafts(to: &$0) }
    }

    private func applyDrafts(to state: inout JournalState) {
        for (id, text) in drafts { state.setDraft(id: id, text: text, events: JournalEvents.parse(text)) }
        state.editorDraft = editorDraft
    }

    @discardableResult
    private func commit(at date: Date = Date(), _ update: (inout JournalState) throws -> Void) -> Bool {
        guard storageLoaded else {
            errorMessage = text("请先恢复日志。原文件受保护，不会被空数据覆盖。", "Restore your journal first. Its original file is protected from being overwritten.")
            return false
        }
        do {
            var next = journal
            next.appendApplicationActivity(applicationTracker?.snapshot(at: date) ?? [])
            try update(&next)
            try storage.save(next)
            journal = next
            applicationTracker?.acknowledge(through: date)
            syncApplicationTracking(at: date)
            return true
        } catch { report(error); return false }
    }

    private func syncApplicationTracking(at date: Date) {
        if isRecording && environmentPauses.isEmpty && preferences.captureApplicationUsage != false {
            if applicationTracker?.isTracking == false { applicationTracker?.start(at: date) }
        } else {
            applicationTracker?.stop(at: date)
        }
    }

    private func report(_ error: Error) {
        var detail = error.localizedDescription
        if error as? JournalError == .emptyNote {
            detail = text("每一项都需要填写具体内容后再保存。", "Add details to each event before saving.")
        }
        if preferences.language.usesChinese, let journalError = error as? JournalError {
            switch journalError {
            case .unsupportedVersion(let version): detail = "这份日志的格式版本（\(version)）暂不支持。"
            case .invalidInterval: detail = "提醒间隔需要在 1 到 240 分钟之间。"
            case .invalidDates: detail = "结束时间需要晚于开始时间。"
            case .emptyNote: detail = "每一项都需要填写具体内容后再保存。"
            case .duplicateID: detail = "日志中有重复的记录标识，请从备份恢复。"
            case .overlappingEntries: detail = "这段时间与已有记录重叠，请调整开始或结束时间。"
            case .activeSessionConflict: detail = "这段时间正在记录中，请结束记录后再补记。"
            case .entryNotFound: detail = "这条记录已不存在。"
            case .noBackup: detail = "还没有可恢复的备份。"
            case .invalidApplicationUsage: detail = "保存的应用使用时间无效，请从备份恢复。"
            case .invalidEvents: detail = "保存的事项与记录文本不一致，请从备份恢复。"
            }
        }
        errorMessage = text("操作未完成，已有记录已保留。", "The operation could not finish. Existing records are preserved.") + "\n" + detail
    }

    private static func demoJournal(showOnboarding: Bool) -> JournalState {
        var state = JournalState()
        state.preferences.completedOnboarding = !showOnboarding
        let day = Calendar.current.startOfDay(for: Date())
        let samples: [(Int, Int, String, EntryStatus)] = [
            (540, 570, "梳理今天的重点，把想法写进笔记。", .recorded),
            (570, 600, "读完论文的方法部分，整理三个值得继续研究的问题。", .recorded),
            (600, 630, "实现日志编辑界面，处理跨天时间段。", .recorded),
            (630, 660, "", .pending),
            (660, 690, "和同事讨论交互细节，确定提醒窗口的布局。", .recorded),
            (780, 810, "散步，然后回来继续阅读。", .recorded)
        ]
        for sample in samples {
            state.entries.append(JournalEntry(
                start: day.addingTimeInterval(Double(sample.0) * 60),
                end: day.addingTimeInterval(Double(sample.1) * 60), text: sample.2, status: sample.3))
        }
        if !showOnboarding {
            _ = state.start(at: Date().addingTimeInterval(-11 * 60))
            _ = state.advance(to: Date())
        }
        return state
    }
}
