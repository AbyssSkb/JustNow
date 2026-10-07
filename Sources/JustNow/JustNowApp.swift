import AppKit
import Combine
import Darwin
import SwiftUI

@main
enum JustNowApp {
    @MainActor
    static func main() {
        var lockFileDescriptor: Int32 = -1
        if !ProcessInfo.processInfo.arguments.contains("--demo") {
            do {
                let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("JustNow", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let descriptor = Darwin.open(directory.appendingPathComponent(".instance-lock").path,
                                             O_CREAT | O_RDWR | O_CLOEXEC, mode_t(0o600))
                guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
                    let failure = errno
                    Darwin.close(descriptor)
                    if failure == EWOULDBLOCK || failure == EAGAIN {
                        if let identifier = Bundle.main.bundleIdentifier,
                           let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
                            running.activate(options: [.activateAllWindows])
                        }
                        return
                    }
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure))
                }
                lockFileDescriptor = descriptor
            } catch {
                let chinese = (Locale.preferredLanguages.first ?? "").hasPrefix("zh")
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = chinese ? "无法安全打开 JustNow 日志" : "JustNow could not safely open your journal"
                alert.informativeText = (chinese ? "无法锁定数据目录。为保护已有记录，应用不会继续启动。\n\n" : "The data directory could not be locked. JustNow will not start, to protect your existing records.\n\n") + error.localizedDescription
                alert.runModal()
                return
            }
        }
        defer { if lockFileDescriptor >= 0 { Darwin.close(lockFileDescriptor) } }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, NSMenuItemValidation {
    private var model: AppModel!
    private var updates: UpdateController!
    private var mainWindow: NSWindow!
    private var reminderPanel: NSPanel?
    private var statusItem: NSStatusItem!
    private var subscriptions = Set<AnyCancellable>()
    private var workspaceObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        model = AppModel(isDemo: arguments.contains("--demo"), showOnboarding: arguments.contains("--onboarding"))
        updates = UpdateController(enabled: !model.isDemo)
        updates.onBeforeRelaunch = { [weak self] targetVersion in
            guard let self else { return false }
            let sourceVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0.1.9"
            return self.model.prepareForUpdate(sourceVersion: sourceVersion, targetVersion: targetVersion)
        }
        updates.onCancel = { [weak self] in _ = self?.model.cancelPreparedUpdate() }
        updates.onError = { [weak self] detail in
            guard let self else { return }
            self.model.errorMessage = self.model.text("更新未完成：", "Update could not finish: ") + detail
        }
        model.onShowMainWindow = { [weak self] in self?.showMainWindow() }
        createMainMenu()
        createMainWindow()
        createStatusItem()
        model.$promptEntryID.sink { [weak self] id in
            self?.updateReminder(id: id)
        }.store(in: &subscriptions)
        model.$now.sink { [weak self] _ in self?.updateStatusTitle() }.store(in: &subscriptions)
        model.$journal.map { $0.preferences.language }.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.createMainMenu()
        }.store(in: &subscriptions)
        let center = NSWorkspace.shared.notificationCenter
        let environmentEvents: [(Notification.Name, ApplicationUsageTracker.PauseReason, Bool)] = [
            (NSWorkspace.willSleepNotification, .systemSleep, true),
            (NSWorkspace.didWakeNotification, .systemSleep, false),
            (NSWorkspace.screensDidSleepNotification, .screenSleep, true),
            (NSWorkspace.screensDidWakeNotification, .screenSleep, false),
            (NSWorkspace.sessionDidResignActiveNotification, .inactiveSession, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, .inactiveSession, false)
        ]
        for (notification, reason, paused) in environmentEvents {
            workspaceObservers.append(center.addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.setEnvironmentPaused(paused, for: reason) }
            })
        }
        showMainWindow()
        model.beginOnLaunch()
        updates.start()
        if arguments.contains("--show-reminder") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.model.showDemoReminder() }
        }
    }

    private func createMainWindow() {
        mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        mainWindow.title = "JustNow"
        mainWindow.titleVisibility = .hidden
        mainWindow.titlebarAppearsTransparent = true
        mainWindow.isReleasedWhenClosed = false
        mainWindow.minSize = NSSize(width: 900, height: 650)
        mainWindow.backgroundColor = .windowBackgroundColor
        mainWindow.delegate = self
        mainWindow.contentView = NSHostingView(rootView: MainView(model: model, updates: updates))
        mainWindow.setFrameAutosaveName("JustNowMainWindow")
        mainWindow.center()
    }

    private func updateReminder(id: UUID?) {
        guard let id else { reminderPanel?.orderOut(nil); return }
        if reminderPanel == nil {
            let panel = ReminderPanel(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 430),
                styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            panel.title = "JustNow"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.delegate = self
            reminderPanel = panel
        }
        guard let panel = reminderPanel else { return }
        let hasClues = model.entries.first(where: { $0.id == id })?.applicationUsage != nil
        panel.setContentSize(NSSize(width: 520, height: hasClues ? 570 : 430))
        panel.contentView = NSHostingView(rootView: PromptView(model: model, entryID: id).id(id))
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func window(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: NSRect) -> NSRect {
        // The application delegate saves drafts before allowing termination.
        sheet.preventsApplicationTerminationWhenModal = false
        return rect
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === reminderPanel {
            model.dismissPrompt()
            return false
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model != nil else { return .terminateNow }
        if model.prepareForQuit() { return .terminateNow }
        updates.cancelPreparedUpdate()
        showMainWindow()
        return .terminateCancel
    }

    @objc private func showMainWindow() {
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "clock", accessibilityDescription: "JustNow")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            button.toolTip = "JustNow"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusTitle()
    }

    private func updateStatusTitle() {
        guard model != nil, let button = statusItem?.button else { return }
        if model.isRecording {
            let seconds = Int(ceil(model.remainingSeconds))
            button.title = String(format: " %02d:%02d", seconds / 60, seconds % 60)
            button.toolTip = model.text("JustNow · 正在记录", "JustNow · Recording")
        } else {
            button.title = ""
            button.toolTip = model.isPaused ? model.text("JustNow · 已暂停", "JustNow · Paused") : model.text("JustNow · 点击开始记录", "JustNow · Start when you're ready")
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let header = NSMenuItem(title: model.isPaused ? model.text("记录已暂停", "Recording paused") : model.isRecording ? model.text("正在记录这一段", "Recording this moment") : "JustNow", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        addMenuItem(to: menu, title: model.isPaused ? model.text("继续记录", "Continue recording") : model.isRecording ? model.text("停止记录", "Stop recording") : model.text("开始记录", "Start recording"), action: #selector(toggleRecording))
        if !model.pendingEntries.isEmpty {
            addMenuItem(to: menu, title: model.text("补记待填时段", "Fill a pending moment") + " (\(model.pendingEntries.count))", action: #selector(openPending))
        }
        menu.addItem(.separator())
        addMenuItem(to: menu, title: model.text("打开日志", "Open journal"), action: #selector(showMainWindow))
        addMenuItem(to: menu, title: model.text("设置…", "Settings…"), action: #selector(openSettings), key: ",")
        menu.addItem(.separator())
        addMenuItem(to: menu, title: model.text("退出 JustNow", "Quit JustNow"), action: #selector(quit), key: "q")
    }

    @objc private func toggleRecording() {
        if model.isRecording { model.stopRecording() } else { model.startRecording() }
        updateStatusTitle()
    }

    @objc private func openPending() {
        if let id = model.pendingEntries.first?.id { model.openPendingEntry(id) }
    }

    @objc private func openSettings() { model.showSettings() }
    @objc private func checkForUpdates() { updates.checkForUpdates() }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates) { return updates?.canCheckForUpdates == true }
        return true
    }
    @objc private func quit() { model.quit() }
    @objc private func addEntry() { model.showMainWindow(); model.openEditor() }
    @objc private func exportJournal() { model.exportCSV() }
    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "JustNow · 刚才",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.9",
            .credits: NSAttributedString(string: model.text("一句话，留下刚才。\n免费开源 · MIT", "A small pause. A clearer day.\nFree & open source · MIT"))
        ])
    }

    private func createMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "JustNow")
        appItem.submenu = appMenu
        addMenuItem(to: appMenu, title: model.text("关于 JustNow", "About JustNow"), action: #selector(showAbout))
        appMenu.addItem(.separator())
        addMenuItem(to: appMenu, title: model.text("设置…", "Settings…"), action: #selector(openSettings), key: ",")
        addMenuItem(to: appMenu, title: model.text("检查更新…", "Check for Updates…"), action: #selector(checkForUpdates))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: model.text("隐藏 JustNow", "Hide JustNow"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: model.text("显示全部", "Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        addMenuItem(to: appMenu, title: model.text("退出 JustNow", "Quit JustNow"), action: #selector(quit), key: "q")
        menu.addItem(appItem)

        let file = NSMenu(title: model.text("文件", "File"))
        addMenuItem(to: file, title: model.text("补记一段…", "Add a moment…"), action: #selector(addEntry), key: "n")
        addMenuItem(to: file, title: model.text("导出日志…", "Export journal…"), action: #selector(exportJournal), key: "e")
        file.addItem(.separator())
        file.addItem(withTitle: model.text("关闭窗口", "Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileItem = NSMenuItem(title: file.title, action: nil, keyEquivalent: "")
        fileItem.submenu = file
        menu.addItem(fileItem)

        let edit = NSMenu(title: model.text("编辑", "Edit"))
        edit.addItem(withTitle: model.text("撤销", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: model.text("重做", "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: model.text("剪切", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: model.text("复制", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: model.text("粘贴", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: model.text("全选", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: edit.title, action: nil, keyEquivalent: "")
        editItem.submenu = edit
        menu.addItem(editItem)

        let windowMenu = NSMenu(title: model.text("窗口", "Window"))
        windowMenu.addItem(withTitle: model.text("最小化", "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: model.text("缩放", "Zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        let windowItem = NSMenuItem(title: windowMenu.title, action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
    }

    private func addMenuItem(to menu: NSMenu, title: String, action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }
}

private final class ReminderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
