import AppKit
import SwiftUI
import JustNowCore

struct MainView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdateController
    @State private var hoveredSection: AppSection?
    @FocusState private var focusedSection: AppSection?
    @FocusState private var searching: Bool

    var body: some View {
        Group {
            if model.preferences.completedOnboarding || model.hasStorageError {
                HStack(spacing: 0) {
                    sidebar
                    Rectangle().fill(Theme.line).frame(width: 1)
                    VStack(spacing: 0) {
                        header
                        ScrollView {
                            VStack(alignment: .leading, spacing: 22) {
                                switch model.selectedSection {
                                case .today:
                                    RecordingCard(model: model)
                                    daySummary
                                    timeline
                                case .history:
                                    historyControls
                                    daySummary
                                    timeline
                                case .topics:
                                    TopicsView(model: model)
                                case .settings:
                                    SettingsView(model: model, updates: updates)
                                }
                            }
                            .padding(32)
                            .frame(maxWidth: 1000)
                            .frame(maxWidth: .infinity)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            } else {
                OnboardingView(model: model)
            }
        }
        .background(Theme.background)
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .preferredColorScheme(model.preferences.appearance == .system ? nil : model.preferences.appearance == .dark ? .dark : .light)
        .frame(minWidth: 900, minHeight: 650)
        .sheet(item: $model.presentedEditor) { request in
            EntryEditorView(model: model, request: request)
        }
        .overlay {
            if model.showingPauseResolution, model.isPaused, model.presentedEditor == nil {
                ZStack {
                    Theme.background.opacity(0.75).ignoresSafeArea()
                    PauseResolutionView(model: model)
                        .frame(width: 470)
                        .journalCard(padding: 28)
                        .shadow(color: .black.opacity(0.10), radius: 24, y: 8)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let message = model.errorMessage ?? model.statusMessage {
                HStack(spacing: 10) {
                    Image(systemName: model.errorMessage != nil ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(model.errorMessage != nil ? Theme.amber : Theme.accent)
                    Text(message).font(.system(size: 12)).lineLimit(3)
                    Button {
                        model.errorMessage = nil
                        model.statusMessage = nil
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                            .frame(width: 36, height: 36).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.text("关闭提示", "Dismiss message"))
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
                .padding(20)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(size: 37)
                VStack(alignment: .leading, spacing: 2) {
                    Text("JustNow").font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(model.text("记下刚才，留住日常", "A little record of your day"))
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(.bottom, 38)

            Text(model.text("我的时间", "YOUR TIME"))
                .font(.system(size: 10, weight: .semibold)).tracking(1.4)
                .foregroundStyle(Theme.secondary).padding(.leading, 12).padding(.bottom, 10)
            navigationButton(.today, title: model.text("今日", "Today"), icon: "sun.max")
            navigationButton(.history, title: model.text("时间档案", "Journal"), icon: "clock.arrow.circlepath")
            navigationButton(.topics, title: model.text("主题", "Topics"), icon: "square.grid.2x2")
            Spacer(minLength: 24)
            if model.isRecording {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.accent).frame(width: 5, height: 5)
                        Text(model.text("正在记录", "Recording"))
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text(countdown(model.remainingSeconds))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }
                    ProgressView(value: model.progress).tint(Theme.accent)
                        .progressViewStyle(.linear)
                }
                .padding(13).background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
                .padding(.bottom, 17)
            }
            navigationButton(.settings, title: model.text("设置", "Settings"), icon: "slider.horizontal.3")
            HStack(spacing: 5) {
                Image(systemName: "lock.shield").font(.system(size: 10))
                Text(model.text("只存在你的 Mac 上", "Private. On your Mac."))
                    .font(.system(size: 10))
            }
            .foregroundStyle(Theme.secondary).padding(.leading, 12).padding(.top, 19)
        }
        .padding(.horizontal, 18).padding(.top, 42).padding(.bottom, 24)
        .frame(width: 217)
        .background(Theme.sidebar)
    }

    private func navigationButton(_ section: AppSection, title: String, icon: String) -> some View {
        Button {
            model.selectedSection = section
            if section == .today { model.selectedDay = model.now }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 15)).frame(width: 20)
                Text(title).font(.system(size: 13, weight: model.selectedSection == section ? .semibold : .medium))
                Spacer()
                if section == .today, model.todayPendingCount > 0 {
                    Text("\(model.todayPendingCount)").font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                }
            }
            .foregroundStyle(model.selectedSection == section ? Theme.accent : Theme.secondary)
            .padding(.horizontal, 12).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(model.selectedSection == section ? Theme.card : hoveredSection == section ? Theme.accent.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(focusedSection == section ? Theme.accent.opacity(0.7) : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain).focused($focusedSection, equals: section)
        .onHover { hoveredSection = $0 ? section : nil }
        .padding(.bottom, 4)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(sectionTitle)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(sectionSubtitle)
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            if model.selectedSection != .settings {
                Button { model.openEditor() } label: {
                    Label(model.text("补记一段", "Add entry"), systemImage: "plus")
                        .actionLabel(compact: true)
                }
                .buttonStyle(ActionButtonStyle(primary: false, compact: true))
                .keyboardShortcut("n", modifiers: .command)
                .help(model.text("手动补记一段时间（⌘N）", "Add a time entry (⌘N)"))
            }
        }
        .padding(.horizontal, 32).padding(.top, 35).padding(.bottom, 25)
        .background(Theme.background)
    }

    private var sectionTitle: String {
        switch model.selectedSection {
        case .today: return model.text("今日", "Today")
        case .history: return model.text("时间档案", "Your journal")
        case .topics: return model.text("主题", "Topics")
        case .settings: return model.text("设置", "Settings")
        }
    }

    private var sectionSubtitle: String {
        switch model.selectedSection {
        case .today: return dateLabel(model.now, model: model)
        case .history: return model.text("回看那些做过的小事。", "The little things that made up your day.")
        case .topics: return model.text("全部已保存时段中的主题与具体事件。", "Topics and details across all saved intervals.")
        case .settings: return model.text("按你的节奏，记录你的时间。", "A rhythm that feels right for you.")
        }
    }

    private var daySummary: some View {
        HStack(spacing: 0) {
            summaryMetric(value: durationLabel(model.recordedDuration, model: model), title: model.text("已记录的时间", "Time captured"), icon: "clock")
            Rectangle().fill(Theme.line).frame(width: 1, height: 32).padding(.horizontal, 16)
            summaryMetric(value: "\(model.completedCount)", title: model.text("日常片段", "Entries written"), icon: "text.alignleft")
            Rectangle().fill(Theme.line).frame(width: 1, height: 32).padding(.horizontal, 16)
            summaryMetric(value: "\(model.pendingCount)", title: model.text("待补记", "To fill in"), icon: "square.and.pencil")
        }
        .journalCard(padding: 21)
    }

    private func summaryMetric(value: String, title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 17, weight: .light))
                .foregroundStyle(Theme.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(value).font(.system(size: 21, weight: .semibold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(title).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var historyControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { historyDateNavigation; Spacer(minLength: 12); historySearch.frame(width: 210) }
            VStack(alignment: .leading, spacing: 12) { historyDateNavigation; historySearch }
        }
    }

    private var historyDateNavigation: some View {
        HStack(spacing: 10) {
            Button { shiftDay(-1) } label: { Image(systemName: "chevron.left").actionLabel(compact: true, iconOnly: true) }
                .buttonStyle(IconButtonStyle()).help(model.text("前一天", "Previous day"))
            JournalDateField(date: $model.selectedDay, label: model.text("日期", "Date"), locale: Locale(identifier: model.text("zh_CN", "en_US")))
                .frame(width: 174)
            Button { shiftDay(1) } label: { Image(systemName: "chevron.right").actionLabel(compact: true, iconOnly: true) }
                .buttonStyle(IconButtonStyle()).help(model.text("后一天", "Next day"))
            Button { model.selectedDay = model.now } label: { Text(model.text("今天", "Today")).actionLabel(compact: true) }
                .buttonStyle(ActionButtonStyle(primary: false, compact: true))
        }
    }

    private var historySearch: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
            TextField(model.text("搜索当天记录", "Search this day"), text: $model.searchText)
                .textFieldStyle(.plain).font(.system(size: 12)).focused($searching)
            if !model.searchText.isEmpty {
                Button { model.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 36, height: 36).contentShape(Rectangle())
                }
                    .buttonStyle(.plain).foregroundStyle(Theme.secondary)
                    .accessibilityLabel(model.text("清空搜索", "Clear search"))
            }
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .simultaneousGesture(TapGesture().onEnded { searching = true })
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(model.selectedSection == .today ? model.text("今天的片段", "Today's entries") : dateLabel(model.selectedDay, model: model))
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1).layoutPriority(1)
                Spacer()
                Text(model.text("每一小段，都算数", "Every little moment counts"))
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            if model.selectedDayEntries.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: model.searchText.isEmpty ? "text.book.closed" : "magnifyingglass")
                        .font(.system(size: 29, weight: .ultraLight)).foregroundStyle(Theme.accent.opacity(0.75))
                        .frame(width: 62, height: 62)
                        .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                    Text(model.searchText.isEmpty ? model.text("时间还留着空白", "A little space for your day") : model.text("没有找到匹配的记录", "No matching entries"))
                        .font(.system(size: 15, weight: .medium))
                    Text(model.searchText.isEmpty ? model.text("开始记录，提醒时写一句刚才做了什么。\n也可以随时补记一段。", "Start recording, then write a few words when reminded.\nYou can add an entry whenever you like.") : model.text("换个关键词再试试。", "Try a different word."))
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center).lineSpacing(5)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 35)
                .journalCard(padding: 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.selectedDayEntries.enumerated()), id: \.element.id) { index, entry in
                        EntryRow(model: model, entry: entry)
                        if index < model.selectedDayEntries.count - 1 {
                            Rectangle().fill(Theme.line).frame(height: 1)
                                .padding(.leading, 142).padding(.trailing, 24)
                        }
                    }
                }
                .journalCard(padding: 0)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            }
        }
    }

    private func shiftDay(_ amount: Int) {
        if let date = Calendar.current.date(byAdding: .day, value: amount, to: model.selectedDay) {
            model.selectedDay = date
        }
    }
}

private struct RecordingCard: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 6) {
                    Circle().fill(model.isRecording ? Theme.accent : Theme.secondary.opacity(0.6)).frame(width: 5, height: 5)
                    Text(model.isPaused ? model.text("记录已暂停", "PAUSED") : model.isRecording ? model.text("记录进行中", "RECORDING") : model.text("从现在开始", "A MOMENT TO BEGIN"))
                        .font(.system(size: 11, weight: .semibold)).tracking(0.8)
                        .foregroundStyle(model.isRecording ? Theme.accent : Theme.secondary)
                }
                Text(model.isPaused ? model.text("回来了？接着记。", "Welcome back. Pick up here.") : model.isRecording ? model.text("专注眼前，稍后记下。", "Be here. Write it down later.") : model.text("刚才，你做了什么？", "What have you been up to?"))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.isPaused ? model.text("已在 ", "Paused at ") + timeLabel(model.pauseDate ?? model.now) : model.isRecording ? model.text("下一次提醒", "Next reminder") + "  " + timeLabel(model.nextReminderDate ?? model.now) : model.text("每隔 \(model.preferences.intervalMinutes) 分钟，用一句话留住刚才。", "Every \(model.preferences.intervalMinutes) min, capture what you just did."))
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        recordingButton
                        if !model.isRecording { recordingHint.fixedSize() }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        recordingButton
                        if !model.isRecording { recordingHint }
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ZStack {
                Circle().stroke(Theme.accent.opacity(0.10), lineWidth: 5)
                if model.isRecording {
                    Circle().trim(from: 0, to: min(1, max(0, model.progress)))
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 5) {
                    if model.isRecording {
                        Text(countdown(model.remainingSeconds))
                            .font(.system(size: 28, weight: .medium, design: .monospaced))
                        Text(model.text("距离提醒", "until next check-in"))
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    } else {
                        Image(systemName: "clock").font(.system(size: 32, weight: .ultraLight)).foregroundStyle(Theme.accent)
                        Text(model.text("\(model.preferences.intervalMinutes) 分钟", "\(model.preferences.intervalMinutes) min"))
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
                    }
                }
            }
            .frame(width: 126, height: 126).padding(.trailing, 5)
            .accessibilityElement(children: .combine)
        }
        .journalCard(padding: 28)
    }

    private var recordingButton: some View {
        Button { model.isRecording ? model.stopRecording() : model.startRecording() } label: {
            Label(model.isPaused ? model.text("继续记录", "Continue recording") : model.isRecording ? model.text("结束记录", "Stop recording") : model.text("开始记录", "Start recording"), systemImage: model.isRecording ? "stop.fill" : "play.fill")
                .actionLabel()
        }
        .buttonStyle(ActionButtonStyle(primary: !model.isRecording))
        .disabled(model.hasStorageError)
        .fixedSize()
    }

    private var recordingHint: some View {
        Text(model.isPaused ? model.text("离开的时间，由你决定是否保留", "You decide whether to keep the time away") : model.text("随时开始，也随时结束", "Start and stop whenever you like"))
            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PauseResolutionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "pause.circle").font(.system(size: 30, weight: .light)).foregroundStyle(Theme.accent)
            Text(model.text("欢迎回来", "Welcome back"))
                .font(.system(size: 25, weight: .semibold, design: .rounded))
            Text(model.text("记录已在 ", "Recording paused at ") + pauseLabel + model.text(" 暂停。之后的这段时间，需要留在日志里吗？", ". Would you like to keep the time since then in your journal?"))
                .font(.system(size: 13)).foregroundStyle(Theme.secondary).lineSpacing(5)
            VStack(spacing: 10) {
                choice(title: model.text("刚才离开了，从现在继续", "I was away. Continue from now"), detail: model.text("跳过暂停后的时间", "Skip the time since pausing"), recordGap: false)
                choice(title: model.text("仍在做事，保留这段时间", "I was still busy. Keep that time"), detail: model.text("把这段时间留作待补记录", "Keep those intervals to fill in later"), recordGap: true)
            }
            HStack {
                Button { model.stopRecording() } label: {
                    Text(model.text("结束记录", "Stop recording")).actionLabel(compact: true)
                }
                .buttonStyle(ActionButtonStyle(primary: false, compact: true))
                Spacer()
                Button { model.showingPauseResolution = false } label: {
                    Text(model.text("稍后决定", "Decide later")).actionLabel(compact: true)
                }
                .buttonStyle(ActionButtonStyle(primary: false, compact: true))
            }
        }
    }

    private var pauseLabel: String {
        let date = model.pauseDate ?? model.now
        if Calendar.current.isDate(date, inSameDayAs: model.now) { return timeLabel(date) }
        return date.formatted(.dateTime.month().day().locale(Locale(identifier: model.text("zh_CN", "en_US")))) + " " + timeLabel(date)
    }

    private func choice(title: String, detail: String, recordGap: Bool) -> some View {
        Button { _ = model.resolvePause(recordGap: recordGap) } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(detail).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.right").font(.system(size: 12))
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(model.hasStorageError)
    }
}

private struct EntryRow: View {
    @ObservedObject var model: AppModel
    let entry: JournalEntry
    @State private var hovering = false
    var body: some View {
        Button { model.openEditor(entry) } label: {
            HStack(alignment: .center, spacing: 20) {
                Text(timeRangeLabel(entry.start, entry.end))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .frame(width: 128, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    if entry.isPending {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.pencil").font(.system(size: 11))
                            Text(model.text("待补记", "To fill in")).font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(Theme.amber)
                        entryContent
                    } else {
                        entryContent
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "pencil").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    .opacity(hovering ? 1 : 0.35)
            }
            .padding(.horizontal, 24).padding(.vertical, 19)
            .frame(minHeight: 56)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? Theme.accent.opacity(0.035) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .help(model.text("点击编辑这段记录", "Click to edit this entry"))
    }

    @ViewBuilder private var entryContent: some View {
        if let events = entry.events, !events.isEmpty {
            JournalEventList(model: model, events: events, maxEvents: 4, lineLimit: 2)
        } else {
            Text(entry.text.isEmpty ? model.text("这段时间，你做了什么？", "What did you do during this time?") : entry.text)
                .font(.system(size: 13)).foregroundStyle(entry.text.isEmpty ? Theme.secondary : Theme.ink)
                .lineLimit(4).lineSpacing(5).multilineTextAlignment(.leading)
        }
    }
}

struct JournalEventList: View {
    @ObservedObject var model: AppModel
    let events: [JournalEvent]
    var maxEvents: Int? = nil
    var lineLimit: Int? = nil
    var fontSize: CGFloat = 13

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(events.prefix(maxEvents ?? events.count).enumerated()), id: \.offset) { _, event in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("•").foregroundStyle(Theme.secondary)
                    (Text(event.topic ?? model.text("其他", "Other")).fontWeight(.semibold).foregroundColor(Theme.accent)
                     + Text("  " + event.content))
                        .lineLimit(lineLimit).lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let maxEvents, events.count > maxEvents {
                Text(model.text("另有 \(events.count - maxEvents) 件事", "\(events.count - maxEvents) more events"))
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
        }
        .font(.system(size: fontSize)).foregroundStyle(Theme.ink)
        .multilineTextAlignment(.leading)
    }
}

private struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdateController
    @State private var intervalText = ""
    @State private var intervalError: String?
    @FocusState private var editingInterval: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 20) {
                sectionHeading(model.text("记录节奏", "Your rhythm"), icon: "timer")
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.text("提醒间隔", "Check-in interval")).font(.system(size: 13, weight: .medium))
                        Text(model.text("从开始记录时计时。修改后，下次开始记录时生效。", "Timed from the start of a session. Changes apply to your next session."))
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                }
                HStack(spacing: 9) {
                    ForEach([15, 30, 45, 60], id: \.self) { minutes in
                        Button {
                            intervalText = String(minutes)
                            intervalError = nil
                            editingInterval = false
                            change { $0.intervalMinutes = minutes }
                        } label: { Text(model.text("\(minutes) 分钟", "\(minutes) min")).actionLabel(compact: true) }
                            .buttonStyle(ActionButtonStyle(primary: model.preferences.intervalMinutes == minutes, compact: true))
                    }
                    Spacer()
                }
                HStack(spacing: 12) {
                    Text(model.text("自定义", "Custom")).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    HStack(spacing: 6) {
                        TextField("30", text: $intervalText)
                            .textFieldStyle(.plain).font(.system(size: 13, weight: .medium))
                            .monospacedDigit().multilineTextAlignment(.center).frame(width: 40)
                            .focused($editingInterval).onSubmit(applyInterval)
                            .accessibilityLabel(model.text("自定义提醒间隔（分钟）", "Custom interval in minutes"))
                        Text(model.text("分钟", "min")).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(Theme.inset, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(intervalError != nil ? Theme.amber : editingInterval ? Theme.accent.opacity(0.65) : Theme.line))
                    .contentShape(RoundedRectangle(cornerRadius: 9))
                    .simultaneousGesture(TapGesture().onEnded { editingInterval = true })
                    Text(model.text("1–240 分钟", "1–240 minutes")).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Spacer()
                }
                if let intervalError {
                    Text(intervalError).font(.system(size: 11)).foregroundStyle(Theme.amber)
                }
                Divider().overlay(Theme.line)
                settingRow(title: model.text("提醒声音", "Reminder sound"), subtitle: model.text("弹窗出现时播放轻提示音", "A gentle sound when a check-in appears")) {
                    Toggle(model.text("提醒声音", "Reminder sound"), isOn: Binding(get: { model.preferences.playSound }, set: { value in change { $0.playSound = value } })).labelsHidden().toggleStyle(JournalToggleStyle())
                }
                Divider().overlay(Theme.line)
                settingRow(title: model.text("应用使用线索", "App clues"), subtitle: model.text("记录前台应用与停留时间，随时段保存在本机，帮助回忆细节", "Keep foreground apps and time with each moment, locally, to help recall the details")) {
                    Toggle(model.text("应用使用线索", "App clues"), isOn: Binding(get: { model.preferences.captureApplicationUsage != false }, set: { value in change { $0.captureApplicationUsage = value } })).labelsHidden().toggleStyle(JournalToggleStyle())
                }
                Divider().overlay(Theme.line)
                settingRow(title: model.text("离开时自动暂停", "Pause when inactive"), subtitle: model.text("连续 30 分钟无键鼠操作时暂停，回来后可保留或跳过这段时间", "Pause after 30 minutes without input. Keep or skip the gap when you return")) {
                    Toggle(model.text("离开时自动暂停", "Pause when inactive"), isOn: Binding(get: { model.preferences.pauseWhenInactive != false }, set: { value in change { $0.pauseWhenInactive = value } })).labelsHidden().toggleStyle(JournalToggleStyle())
                }
            }
            .journalCard()

            VStack(alignment: .leading, spacing: 20) {
                sectionHeading(model.text("外观与启动", "Make it yours"), icon: "paintbrush.pointed")
                VStack(alignment: .leading, spacing: 14) {
                    settingDescription(title: model.text("外观", "Appearance"), subtitle: model.text("让 JustNow 融入你的桌面", "A comfortable fit for your desktop"))
                    HStack(spacing: 9) {
                        ForEach(AppAppearance.allCases, id: \.self) { option in
                            Button { change { $0.appearance = option } } label: {
                                Label(appearanceTitle(option), systemImage: appearanceIcon(option))
                                    .frame(maxWidth: .infinity).actionLabel(compact: true)
                            }
                            .buttonStyle(ActionButtonStyle(primary: model.preferences.appearance == option, compact: true))
                            .accessibilityAddTraits(model.preferences.appearance == option ? .isSelected : [])
                        }
                    }
                }
                Divider().overlay(Theme.line)
                VStack(alignment: .leading, spacing: 14) {
                    settingDescription(title: model.text("语言", "Language"), subtitle: model.text("界面语言即时切换", "Changes immediately"))
                    HStack(spacing: 9) {
                        ForEach(AppLanguage.allCases, id: \.self) { option in
                            Button { change { $0.language = option } } label: {
                                Text(languageTitle(option)).frame(maxWidth: .infinity).actionLabel(compact: true)
                            }
                            .buttonStyle(ActionButtonStyle(primary: model.preferences.language == option, compact: true))
                            .accessibilityAddTraits(model.preferences.language == option ? .isSelected : [])
                        }
                    }
                }
                Divider().overlay(Theme.line)
                settingRow(title: model.text("打开时开始记录", "Start recording on launch"), subtitle: model.text("打开应用就开始新时段，手动结束后不会自行重启", "Start a new session when the app launches. A manual stop stays stopped")) {
                    Toggle(model.text("打开时开始记录", "Start recording on launch"), isOn: Binding(get: { model.preferences.autoStartRecording != false }, set: { value in change { $0.autoStartRecording = value } })).labelsHidden().toggleStyle(JournalToggleStyle())
                }
                Divider().overlay(Theme.line)
                settingRow(title: model.text("登录时启动", "Launch at login"), subtitle: model.text("登录 Mac 时自动打开应用", "Open the app when you log in to your Mac")) {
                    Toggle(model.text("登录时启动", "Launch at login"), isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin)).labelsHidden().toggleStyle(JournalToggleStyle())
                }
            }
            .journalCard()

            VStack(alignment: .leading, spacing: 18) {
                sectionHeading(model.text("你的记录，属于你", "Your journal belongs to you"), icon: "lock.shield")
                Text(model.text("所有记录都保存在本机。不需要账号，不上传记录，没有分析追踪。", "Everything stays on your Mac. No account, no uploads, no analytics."))
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(5)
                HStack(spacing: 9) {
                    Button { model.exportCSV() } label: { Label(model.text("导出 CSV", "Export CSV"), systemImage: "tablecells").actionLabel(compact: true) }
                        .buttonStyle(ActionButtonStyle(primary: false, compact: true))
                    Button { model.exportJSON() } label: { Label(model.text("导出 JSON", "Export JSON"), systemImage: "arrow.down.doc").actionLabel(compact: true) }
                        .buttonStyle(ActionButtonStyle(primary: false, compact: true))
                    Button { model.revealDataDirectory() } label: { Label(model.text("数据文件夹", "Data folder"), systemImage: "folder").actionLabel(compact: true) }
                        .buttonStyle(ActionButtonStyle(primary: false, compact: true))
                }
                if model.hasStorageError {
                    Button { model.restoreBackup() } label: { Text(model.text("从备份恢复", "Restore backup")).actionLabel(compact: true) }
                        .buttonStyle(ActionButtonStyle(primary: false, compact: true))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .journalCard()
            VStack(alignment: .leading, spacing: 18) {
                sectionHeading(model.text("版本与更新", "App updates"), icon: "arrow.triangle.2.circlepath")
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.text("更新时继续记录", "Keep recording through updates"))
                            .font(.system(size: 13, weight: .medium))
                        Text(model.text("安装新版后，自动接着当前时段记录，保留未写完的草稿。", "After installing, your current session and unfinished drafts continue automatically."))
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(3)
                    }
                    Spacer(minLength: 0)
                    Button { updates.checkForUpdates() } label: {
                        Text(model.text("检查更新", "Check for updates")).actionLabel(compact: true)
                    }
                    .buttonStyle(ActionButtonStyle(primary: false, compact: true))
                    .disabled(!updates.canCheckForUpdates)
                }
                if !updates.isConfigured {
                    Text(model.text("更新通道尚未开放。", "The update channel is not available yet."))
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
            .journalCard()
            HStack {
                BrandMark(size: 22)
                Text("JustNow").font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.12")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Spacer()
                Text(model.text("用 MIT 许可开源 · 为日常留一点空间", "Open source under MIT · A little room for your day"))
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    .lineLimit(1).minimumScaleFactor(0.9)
            }
            .padding(.horizontal, 4).padding(.bottom, 8)
        }
        .onAppear { intervalText = String(model.preferences.intervalMinutes) }
        .onChange(of: model.preferences.intervalMinutes) { _, value in
            intervalText = String(value)
            intervalError = nil
        }
        .onChange(of: editingInterval) { wasEditing, isEditing in
            if wasEditing && !isEditing { applyInterval() }
        }
        .onDisappear { applyInterval() }
    }

    private func applyInterval() {
        guard let value = Int(intervalText.trimmingCharacters(in: .whitespacesAndNewlines)), (1...240).contains(value) else {
            intervalError = model.text("请输入 1–240 之间的整数。", "Enter a whole number between 1 and 240.")
            return
        }
        intervalText = String(value)
        intervalError = nil
        if value != model.preferences.intervalMinutes { change { $0.intervalMinutes = value } }
    }

    private func appearanceTitle(_ option: AppAppearance) -> String {
        switch option {
        case .system: return model.text("跟随系统", "System")
        case .light: return model.text("浅色", "Light")
        case .dark: return model.text("深色", "Dark")
        }
    }

    private func languageTitle(_ option: AppLanguage) -> String {
        switch option {
        case .system: return model.text("跟随系统", "System")
        case .chinese: return "简体中文"
        case .english: return "English"
        }
    }

    private func appearanceIcon(_ option: AppAppearance) -> String {
        switch option {
        case .system: return "desktopcomputer"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    private func change(_ update: (inout Preferences) -> Void) {
        var preferences = model.preferences
        update(&preferences)
        model.updatePreferences(preferences)
    }

    private func sectionHeading(_ title: String, icon: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Theme.accent)
            Text(title).font(.system(size: 15, weight: .semibold))
        }
    }

    private func settingRow<Content: View>(title: String, subtitle: String, @ViewBuilder control: () -> Content) -> some View {
        HStack(spacing: 20) {
            settingDescription(title: title, subtitle: subtitle)
            Spacer()
            control()
        }
    }

    private func settingDescription(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 13, weight: .medium))
            Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 65) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    BrandMark(size: 48)
                    Text("JustNow").font(.system(size: 26, weight: .bold, design: .rounded))
                }
                Text(model.text("让忙碌的日子，\n留下几句话。", "Give your busy day\na few words."))
                    .font(.system(size: 36, weight: .semibold, design: .rounded)).lineSpacing(9)
                Text(model.text("不用预先计划任务。打开应用，开始记录，\n定时回顾刚才，用自己的话写下来。", "No tasks to set up. Open the app to begin,\nthen pause to capture what you just did."))
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary).lineSpacing(7)
                VStack(alignment: .leading, spacing: 16) {
                    onboardingStep("play", title: model.text("打开就开始，随时可停", "Open to begin. Stop anytime"), detail: model.text("离开电脑时自动暂停，回来后再继续", "Pause when you're away. Continue when you return"))
                    onboardingStep("timer", title: model.text("每 30 分钟，轻轻提醒", "A check-in every 30 minutes"), detail: model.text("提醒间隔可以在设置中调整", "Choose your own interval in Settings"))
                    onboardingStep("text.alignleft", title: model.text("一句话，留住刚才", "A few words about just now"), detail: model.text("自由填写，之后也能补记和修改", "Write freely. Fill in or edit entries later"))
                }
                .padding(.vertical, 8)
                Button { model.completeOnboarding() } label: {
                    HStack(spacing: 35) { Text(model.text("开始使用", "Make yourself at home")); Image(systemName: "arrow.right") }
                        .actionLabel()
                }
                .buttonStyle(ActionButtonStyle())
                .keyboardShortcut(.return, modifiers: [])
                Text(model.text("本地保存 · 无需账号 · 开源免费", "Saved locally · No account · Free & open source"))
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
            .frame(width: 410, alignment: .leading)
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text(model.text("一天中的小小片段", "LITTLE MOMENTS OF A DAY"))
                        .font(.system(size: 10, weight: .medium)).tracking(1).foregroundStyle(Theme.secondary)
                    Spacer()
                    Image(systemName: "sun.max").foregroundStyle(Theme.accent)
                }
                previewEntry("09:00 — 09:30", text: model.text("读完一篇论文，记下几个\n值得继续想的问题。", "Finished a paper. Jotted down\na few questions to come back to."))
                Divider().overlay(Theme.line)
                previewEntry("09:30 — 10:00", text: model.text("改好了昨天卡住的功能。\n出去走了一小圈。", "Fixed the feature I got stuck on.\nWent for a short walk."))
                Divider().overlay(Theme.line)
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil").foregroundStyle(Theme.accent)
                    Text(model.text("10:00 — 10:30 · 等你写下", "10:00 — 10:30 · Your words go here"))
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
            .journalCard(padding: 27)
            .frame(width: 305)
            .rotationEffect(.degrees(2))
            .shadow(color: Theme.accent.opacity(0.06), radius: 35, y: 16)
        }
        .padding(.horizontal, 50).padding(.vertical, 36).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func onboardingStep(_ icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30).background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
        }
    }

    private func previewEntry(_ time: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(time).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Theme.accent)
            Text(text).font(.system(size: 14)).lineSpacing(7)
        }
    }
}

struct PromptView: View {
    @ObservedObject var model: AppModel
    let entryID: UUID
    var onHeightChange: ((CGFloat) -> Void)?
    @State private var draft: String
    @State private var writing = false
    @State private var showingPrevious = false
    @State private var editorHeight: CGFloat = 90

    init(model: AppModel, entryID: UUID, onHeightChange: ((CGFloat) -> Void)? = nil) {
        self.model = model
        self.entryID = entryID
        self.onHeightChange = onHeightChange
        let entry = model.entries.first { $0.id == entryID }
        _draft = State(initialValue: entry?.events == nil ? JournalEvents.legacyInputText(entry?.text ?? "") : entry?.text ?? "")
    }

    private var entry: JournalEntry? { model.entries.first { $0.id == entryID } }
    private var previous: JournalEntry? { model.previousEntry(for: entryID) }
    private var preferredHeight: CGFloat {
        Self.height(editorHeight: editorHeight, hasPrevious: previous != nil, hasClues: entry?.applicationUsage != nil, hasError: model.errorMessage != nil)
    }

    static func height(editorHeight: CGFloat = 90, hasPrevious: Bool, hasClues: Bool, hasError: Bool = false) -> CGFloat {
        min(560, 142 + editorHeight + (hasPrevious ? 85 : 0) + (hasClues ? 50 : 0) + (hasError ? 44 : 0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 9) {
                    BrandMark(size: 26)
                    Text(model.text("记下刚才", "Capture this moment"))
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                }
                Spacer()
                if let entry {
                    Text(contextRange(entry))
                        .font(.system(size: 19, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1).minimumScaleFactor(0.65)
                }
            }
            if let previous { previousReference(previous) }
            if let summary = entry?.applicationUsage {
                ApplicationRecallView(model: model, summary: summary, inline: true)
            }
            JournalEventEditor(model: model, text: $draft, focused: $writing, onHeightChange: { editorHeight = $0 })
                .frame(minHeight: 90, maxHeight: .infinity)
            HStack {
                if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, model.canDiscardPrompt(entryID) {
                    Button { _ = model.discardPrompt(id: entryID) } label: {
                        Text(model.text("不记录这段", "Skip this interval")).actionLabel(compact: true)
                    }
                    .buttonStyle(ActionButtonStyle(primary: false, compact: true))
                    .disabled(model.hasStorageError)
                }
                Spacer()
                Button { model.dismissPrompt() } label: { Text(model.text("稍后", "Later")).actionLabel(compact: true) }
                    .buttonStyle(ActionButtonStyle(primary: false, compact: true))
                    .keyboardShortcut(.escape, modifiers: [])
                Button { _ = model.savePrompt(id: entryID, text: draft) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) { Text(model.text("保存", "Save")); Text("⌘↵").font(.system(size: 10)).opacity(0.65) }
                        .actionLabel(compact: true)
                }
                .buttonStyle(ActionButtonStyle(compact: true))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.hasStorageError)
            }
            if let error = model.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(Theme.amber).lineLimit(3)
            }
        }
        .padding(.horizontal, 22).padding(.top, 30).padding(.bottom, 20)
        .background(Theme.background).foregroundStyle(Theme.ink).tint(Theme.accent)
        .ignoresSafeArea(edges: .top)
        .preferredColorScheme(model.preferences.appearance == .system ? nil : model.preferences.appearance == .dark ? .dark : .light)
        .onAppear { writing = true; onHeightChange?(preferredHeight) }
        .onChange(of: preferredHeight) { _, value in onHeightChange?(value) }
        .onChange(of: draft) { _, value in model.setDraft(id: entryID, text: value) }
    }

    @ViewBuilder private func previousReference(_ previous: JournalEntry) -> some View {
        if previous.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            previousSummary(previous)
        } else {
            Button { showingPrevious = true } label: { previousSummary(previous) }
                .buttonStyle(.plain)
                .help(model.text("查看上一段完整内容", "Read the previous interval in full"))
                .popover(isPresented: $showingPrevious) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.text("上一段的记录", "Previous interval"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(contextRange(previous))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.secondary)
                        ViewThatFits(in: .vertical) {
                            previousText(previous).fixedSize(horizontal: false, vertical: true)
                            ScrollView { previousText(previous) }.scrollIndicators(.hidden)
                        }
                        .frame(maxHeight: 240, alignment: .topLeading)
                    }
                    .padding(18).frame(width: 380)
                    .foregroundStyle(Theme.ink).background(Theme.background)
                }
        }
    }

    private func previousSummary(_ previous: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(model.text("上一段", "Previous interval")).font(.system(size: 11, weight: .semibold))
                Text(contextRange(previous)).font(.system(size: 10, design: .monospaced))
                if previous.isPending {
                    Text(model.text("待补记", "Unfinished")).font(.system(size: 10))
                }
                Spacer(minLength: 0)
                if !previous.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                }
            }
            .foregroundStyle(Theme.secondary)
            if let events = previous.events, !events.isEmpty {
                JournalEventList(model: model, events: events, maxEvents: 1, lineLimit: 1, fontSize: 12)
            } else {
                Text(previous.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? model.text("这一段还没有填写。", "This interval has not been written yet.") : previous.text)
                    .font(.system(size: 12)).lineSpacing(2).lineLimit(2)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12).background(Theme.inset, in: RoundedRectangle(cornerRadius: 11))
        .contentShape(RoundedRectangle(cornerRadius: 11))
    }

    @ViewBuilder private func previousText(_ previous: JournalEntry) -> some View {
        if let events = previous.events, !events.isEmpty {
            JournalEventList(model: model, events: events).textSelection(.enabled)
        } else {
            Text(previous.text).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func contextRange(_ entry: JournalEntry) -> String {
        let calendar = Calendar.current
        let date = Date.FormatStyle.dateTime.month(.abbreviated).day()
            .locale(Locale(identifier: model.text("zh_CN", "en_US")))
        if !calendar.isDate(entry.start, inSameDayAs: entry.end) {
            return entry.start.formatted(date) + " " + timeLabel(entry.start) + " – "
                + entry.end.formatted(date) + " " + timeLabel(entry.end)
        }
        let prefix = calendar.isDate(entry.start, inSameDayAs: model.now) ? "" : entry.start.formatted(date) + " "
        return prefix + timeRangeLabel(entry.start, entry.end)
    }
}

private struct EntryEditorView: View {
    @ObservedObject var model: AppModel
    let request: EntryEditorRequest
    @State private var start: Date
    @State private var end: Date
    @State private var draft: String
    @State private var confirmDelete = false
    @State private var savedOrDeleted = false
    @State private var writing = false
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, request: EntryEditorRequest) {
        self.model = model
        self.request = request
        let initialEnd = request.draft?.end ?? request.entry?.end ?? (Calendar.current.isDateInToday(model.displayDay) ? model.now : Calendar.current.date(bySettingHour: 9, minute: 30, second: 0, of: model.displayDay) ?? model.displayDay)
        _end = State(initialValue: initialEnd)
        _start = State(initialValue: request.draft?.start ?? request.entry?.start ?? initialEnd.addingTimeInterval(-Double(model.preferences.intervalMinutes * 60)))
        let initialText = request.draft?.text ?? request.entry?.text ?? ""
        let structured = request.draft.map { $0.usesStructuredEvents == true } ?? (request.entry?.events != nil)
        _draft = State(initialValue: structured ? initialText : JournalEvents.legacyInputText(initialText))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(request.entry == nil ? model.text("补记一段时间", "Add a little moment") : model.text("编辑这段记录", "Edit this moment"))
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text(model.text("那些做过的小事，都值得被记下。", "The little things you did deserve a few words."))
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                BrandMark(size: 30)
            }
            VStack(spacing: 15) {
                HStack {
                    Text(model.text("开始", "From")).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    Spacer()
                    JournalDateField(date: $start, label: model.text("开始日期", "Start date"), locale: Locale(identifier: model.text("zh_CN", "en_US")))
                        .frame(width: 185)
                    JournalTimeField(date: $start, label: model.text("开始时间", "Start time"), locale: Locale(identifier: model.text("zh_CN", "en_US")))
                }
                Divider().overlay(Theme.line)
                HStack {
                    Text(model.text("结束", "To")).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    Spacer()
                    JournalDateField(date: $end, label: model.text("结束日期", "End date"), locale: Locale(identifier: model.text("zh_CN", "en_US")))
                        .frame(width: 185)
                    JournalTimeField(date: $end, label: model.text("结束时间", "End time"), locale: Locale(identifier: model.text("zh_CN", "en_US")))
                }
            }
            .padding(16).background(Theme.inset, in: RoundedRectangle(cornerRadius: 12))
            if let summary = request.entry?.applicationUsage {
                ApplicationRecallView(model: model, summary: summary, compact: true)
                if abs(summary.start.timeIntervalSince(start)) > 1 || abs(summary.end.timeIntervalSince(end)) > 1 {
                    Text(model.text("线索来自原时段 ", "Clues come from the original interval ") + timeLabel(summary.start) + " – " + timeLabel(summary.end))
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                JournalEventEditor(model: model, text: $draft, focused: $writing)
                    .frame(height: 200)
            }
            if end <= start {
                Text(model.text("结束时间需要晚于开始时间。", "The end needs to be after the start."))
                    .font(.system(size: 11)).foregroundStyle(Theme.amber)
            } else if let error = model.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(Theme.amber).lineLimit(3)
            }
            HStack {
                if request.entry != nil {
                    Button { confirmDelete = true } label: { Image(systemName: "trash").actionLabel(iconOnly: true) }
                        .buttonStyle(IconButtonStyle(compact: false)).help(model.text("删除记录", "Delete entry"))
                }
                Spacer()
                Button {
                    if model.discardEditorDraft() { savedOrDeleted = true; dismiss() }
                } label: { Text(model.text("取消", "Cancel")).actionLabel() }
                    .buttonStyle(ActionButtonStyle(primary: false))
                    .keyboardShortcut(.escape, modifiers: [])
                Button {
                    if model.saveEditedEntry(id: request.entry?.id, start: start, end: end, text: draft) {
                        savedOrDeleted = true
                        dismiss()
                    }
                } label: { Text(model.text("保存记录", "Save entry")).actionLabel() }
                .buttonStyle(ActionButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || end <= start || model.hasStorageError)
            }
        }
        .padding(30).frame(width: 510)
        .background(Theme.background).foregroundStyle(Theme.ink).tint(Theme.accent)
        .onAppear { writing = true; preserveDraft() }
        .onChange(of: draft) { _, _ in preserveDraft() }
        .onChange(of: start) { _, _ in preserveDraft() }
        .onChange(of: end) { _, _ in preserveDraft() }
        .onDisappear { preserveDraft() }
        .confirmationDialog(model.text("删除这段记录？", "Delete this entry?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(model.text("删除", "Delete"), role: .destructive) {
                if let entry = request.entry {
                    model.deleteEntry(entry.id)
                    if !model.entries.contains(where: { $0.id == entry.id }) {
                        savedOrDeleted = true
                        dismiss()
                    }
                }
            }
            Button(model.text("取消", "Cancel"), role: .cancel) { }
        } message: { Text(model.text("删除后无法撤销。", "This cannot be undone.")) }
    }

    private func preserveDraft() {
        guard !savedOrDeleted else { return }
        model.editorDraft = JournalEditorDraft(entryID: request.entry?.id, start: start, end: end, text: draft, usesStructuredEvents: true)
        if let entry = request.entry, entry.isPending { model.setDraft(id: entry.id, text: draft) }
    }
}

private func timeLabel(_ date: Date) -> String {
    date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "en_GB")))
}

private func timeRangeLabel(_ start: Date, _ end: Date) -> String {
    if timeLabel(start) != timeLabel(end) { return timeLabel(start) + " – " + timeLabel(end) }
    let style = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits).locale(Locale(identifier: "en_GB"))
    return start.formatted(style) + " – " + end.formatted(style)
}

@MainActor private func dateLabel(_ date: Date, model: AppModel) -> String {
    date.formatted(.dateTime.year().month(.wide).day().weekday(.wide).locale(Locale(identifier: model.text("zh_CN", "en_US"))))
}

@MainActor private func durationLabel(_ seconds: TimeInterval, model: AppModel) -> String {
    let minutes = Int(max(0, seconds) / 60)
    if minutes < 60 { return model.text("\(minutes) 分钟", "\(minutes) min") }
    let hours = minutes / 60, remainder = minutes % 60
    return remainder == 0 ? model.text("\(hours) 小时", "\(hours) hr") : model.text("\(hours) 小时 \(remainder) 分", "\(hours) hr \(remainder) min")
}

private func countdown(_ seconds: TimeInterval) -> String {
    let value = Int(max(0, ceil(seconds)))
    if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) }
    return String(format: "%02d:%02d", value / 60, value % 60)
}
