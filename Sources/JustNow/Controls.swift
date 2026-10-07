import AppKit
import SwiftUI
import JustNowCore

struct JournalTextEditor: View {
    @Binding var text: String
    let placeholder: String
    @Binding var focused: Bool

    var body: some View {
        NativeJournalEditor(text: $text, placeholder: placeholder, focused: $focused)
            .background(Theme.inset)
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13)
                .strokeBorder(focused ? Theme.accent.opacity(0.65) : Theme.line, lineWidth: 1))
    }
}

private struct NativeJournalEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    @Binding var focused: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        let editor = JournalNSTextView(frame: scroll.contentView.bounds)
        editor.isEditable = true
        editor.isSelectable = true
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 13)
        editor.textColor = NSColor(Theme.ink)
        editor.insertionPointColor = NSColor(Theme.accent)
        editor.selectedTextAttributes = [.backgroundColor: NSColor(Theme.accent.opacity(0.22)),
                                         .foregroundColor: NSColor(Theme.ink)]
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        editor.defaultParagraphStyle = paragraph
        editor.typingAttributes = [.font: editor.font!, .paragraphStyle: paragraph, .foregroundColor: NSColor(Theme.ink)]
        editor.textContainerInset = NSSize(width: 14, height: 12)
        editor.textContainer?.lineFragmentPadding = 0
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.onFocusChanged = { context.coordinator.parent.focused = $0 }
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? JournalNSTextView else { return }
        if editor.string != text, !editor.hasMarkedText() { editor.string = text }
        editor.placeholder = placeholder
        editor.wantsFocus = focused
        editor.setAccessibilityLabel(placeholder)
        editor.needsDisplay = true
        editor.focusIfRequested()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeJournalEditor
        private let editorUndoManager = UndoManager()
        init(_ parent: NativeJournalEditor) { self.parent = parent }
        func undoManager(for view: NSTextView) -> UndoManager? { editorUndoManager }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}

private final class JournalNSTextView: NSTextView {
    var placeholder = ""
    var wantsFocus = false
    var onFocusChanged: ((Bool) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusIfRequested()
    }

    func focusIfRequested() {
        guard wantsFocus, let window, window.firstResponder !== self else { return }
        window.initialFirstResponder = self
        DispatchQueue.main.async { [weak self] in
            guard let self, self.wantsFocus else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            let rect = NSRect(origin: textContainerOrigin, size: NSSize(width: bounds.width - textContainerOrigin.x * 2, height: bounds.height))
            (placeholder as NSString).draw(in: rect, withAttributes: [
                .font: font ?? NSFont.systemFont(ofSize: 13),
                .paragraphStyle: defaultParagraphStyle ?? NSParagraphStyle.default,
                .foregroundColor: NSColor(Theme.secondary)
            ])
        }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChanged?(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocusChanged?(false) }
        return accepted
    }
}

struct JournalDateField: View {
    @Binding var date: Date
    let label: String
    let locale: Locale
    @State private var showingCalendar = false
    @State private var hovering = false

    var body: some View {
        Button { showingCalendar.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar").foregroundStyle(Theme.secondary)
                Text(date.formatted(.dateTime.year().month(.abbreviated).day().locale(locale)))
                    .lineLimit(1).minimumScaleFactor(0.9)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.secondary)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12).frame(height: 36)
            .background(hovering ? Theme.inset : Theme.card, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(showingCalendar ? Theme.accent.opacity(0.65) : Theme.line))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .accessibilityLabel(label)
        .accessibilityValue(date.formatted(.dateTime.year().month(.wide).day().locale(locale)))
        .popover(isPresented: $showingCalendar, arrowEdge: .bottom) {
            JournalCalendar(date: $date, locale: locale) { showingCalendar = false }
        }
    }
}

struct JournalTimeField: View {
    @Binding var date: Date
    let label: String
    var locale: Locale = .current
    @State private var showingTime = false
    @State private var hovering = false

    var body: some View {
        Button { showingTime.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock").foregroundStyle(Theme.secondary)
                Text(date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "en_GB"))))
                    .monospacedDigit()
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.secondary)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12).frame(height: 36)
            .background(hovering ? Theme.inset : Theme.card, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(showingTime ? Theme.accent.opacity(0.65) : Theme.line))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .accessibilityLabel(label)
        .accessibilityValue(date.formatted(.dateTime.hour().minute().locale(locale)))
        .popover(isPresented: $showingTime, arrowEdge: .bottom) {
            JournalTimeChooser(date: $date, locale: locale) { showingTime = false }
        }
    }
}

private struct JournalCalendar: View {
    @Binding var date: Date
    let locale: Locale
    let close: () -> Void
    @State private var month: Date
    @State private var page = Page.days
    @State private var yearPage: Int

    private enum Page { case days, months, years }
    private let calendar = Calendar(identifier: .gregorian)
    private var chinese: Bool { locale.identifier.hasPrefix("zh") }
    private var year: Int { calendar.component(.year, from: month) }
    private var monthNumber: Int { calendar.component(.month, from: month) }

    init(date: Binding<Date>, locale: Locale, close: @escaping () -> Void) {
        _date = date
        self.locale = locale
        self.close = close
        let calendar = Calendar(identifier: .gregorian)
        _month = State(initialValue: calendar.dateInterval(of: .month, for: date.wrappedValue)!.start)
        let year = calendar.component(.year, from: date.wrappedValue)
        _yearPage = State(initialValue: year - (year % 12))
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            switch page {
            case .days: dayGrid
            case .months: monthGrid
            case .years: yearGrid
            }
            HStack(spacing: 8) {
                Button { select(Date()) } label: { Text(chinese ? "今天" : "Today").calendarChoiceLabel() }
                    .buttonStyle(CalendarChoiceStyle())
                    .disabled(CalendarSelection.replacingDay(of: date, with: Date(), calendar: calendar) == nil)
                Button(action: close) { Text(chinese ? "关闭" : "Close").calendarChoiceLabel() }
                    .buttonStyle(CalendarChoiceStyle())
            }
        }
        .padding(20).frame(width: 316)
        .background(Theme.card)
        .foregroundStyle(Theme.ink)
        .onExitCommand(perform: close)
    }

    private var header: some View {
        HStack(spacing: 4) {
            if page == .years {
                Text(verbatim: "\(yearPage) – \(yearPage + 11)").font(.system(size: 14, weight: .semibold)).monospacedDigit()
                Spacer(minLength: 4)
            } else {
                Button {
                    yearPage = year - (year % 12)
                    page = page == .years ? .days : .years
                } label: {
                    HStack(spacing: 5) {
                        Text(chinese ? "\(year)年" : String(year))
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .calendarChoiceLabel()
                }
                .buttonStyle(CalendarChoiceStyle(selected: page == .years))
                Button { page = page == .months ? .days : .months } label: {
                    HStack(spacing: 5) {
                        Text(month.formatted(.dateTime.month(.wide).locale(locale)))
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .calendarChoiceLabel()
                }
                .buttonStyle(CalendarChoiceStyle(selected: page == .months))
                Spacer(minLength: 0)
            }
            Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36).contentShape(RoundedRectangle(cornerRadius: 8)) }
                .buttonStyle(CalendarChoiceStyle())
                .accessibilityLabel(chinese ? "上一页" : "Previous page")
            Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36).contentShape(RoundedRectangle(cornerRadius: 8)) }
                .buttonStyle(CalendarChoiceStyle())
                .accessibilityLabel(chinese ? "下一页" : "Next page")
        }
    }

    private var dayGrid: some View {
        let firstWeekday = (calendar.component(.weekday, from: month) + 5) % 7
        let count = calendar.range(of: .day, in: .month, for: month)!.count
        let rows = (firstWeekday + count + 6) / 7
        let formatter = DateFormatter()
        formatter.locale = locale
        let weekdays = formatter.shortStandaloneWeekdaySymbols!
        return VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<7) { column in
                    Text(weekdays[(column + 1) % 7])
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.secondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<(rows * 7), id: \.self) { index in
                    let number = index - firstWeekday + 1
                    if (1...count).contains(number) {
                        let day = calendar.date(byAdding: .day, value: number - 1, to: month)!
                        let selected = calendar.isDate(day, inSameDayAs: date)
                        let available = CalendarSelection.replacingDay(of: date, with: day, calendar: calendar) != nil
                        Button { select(day) } label: { Text(String(number)).monospacedDigit().calendarChoiceLabel() }
                            .buttonStyle(CalendarChoiceStyle(selected: selected, today: calendar.isDateInToday(day)))
                            .disabled(!available)
                            .accessibilityLabel(day.formatted(.dateTime.year().month(.wide).day().weekday(.wide).locale(locale)))
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .help(available ? (chinese ? "保留当前时间，选择这个日期" : "Choose this date and keep the current time") : (chinese ? "夏令时切换导致当天的这个时刻不存在。" : "The current time does not exist on this date because of daylight saving."))
                    } else {
                        Color.clear.frame(height: 36).accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(1...12, id: \.self) { number in
                let value = calendar.date(from: DateComponents(year: year, month: number, day: 1))!
                Button { month = value; page = .days } label: {
                    Text(value.formatted(.dateTime.month(.abbreviated).locale(locale))).calendarChoiceLabel(height: 40)
                }
                .buttonStyle(CalendarChoiceStyle(selected: number == monthNumber))
                .accessibilityAddTraits(number == monthNumber ? .isSelected : [])
            }
        }
    }

    private var yearGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(yearPage..<(yearPage + 12), id: \.self) { value in
                Button {
                    month = calendar.date(from: DateComponents(year: value, month: monthNumber, day: 1))!
                    page = .months
                } label: { Text(String(value)).monospacedDigit().calendarChoiceLabel(height: 40) }
                .buttonStyle(CalendarChoiceStyle(selected: value == year))
                .accessibilityAddTraits(value == year ? .isSelected : [])
            }
        }
    }

    private func move(_ step: Int) {
        switch page {
        case .years: yearPage = max(1, yearPage + step * 12)
        case .months: month = calendar.date(byAdding: .year, value: step, to: month)!
        case .days: month = calendar.date(byAdding: .month, value: step, to: month)!
        }
    }

    private func select(_ day: Date) {
        guard let selected = CalendarSelection.replacingDay(of: date, with: day, calendar: calendar) else { return }
        date = selected
        close()
    }
}

private struct JournalTimeChooser: View {
    @Binding var date: Date
    let locale: Locale
    let close: () -> Void
    @State private var hour: Int
    @State private var minute: Int
    @State private var choosingHour = true
    private let calendar = Calendar(identifier: .gregorian)
    private var chinese: Bool { locale.identifier.hasPrefix("zh") }
    private var selectedDate: Date? { CalendarSelection.replacingTime(of: date, hour: hour, minute: minute, calendar: calendar) }

    init(date: Binding<Date>, locale: Locale, close: @escaping () -> Void) {
        _date = date
        self.locale = locale
        self.close = close
        let calendar = Calendar(identifier: .gregorian)
        _hour = State(initialValue: calendar.component(.hour, from: date.wrappedValue))
        _minute = State(initialValue: calendar.component(.minute, from: date.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Button { choosingHour = true } label: {
                    VStack(spacing: 4) {
                        Text(chinese ? "小时" : "Hour").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        Text(String(format: "%02d", hour)).font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
                    }
                    .calendarChoiceLabel(height: 64)
                }
                .buttonStyle(CalendarChoiceStyle(selected: choosingHour))
                .accessibilityLabel(chinese ? "选择小时" : "Choose hour")
                .accessibilityValue(String(format: "%02d", hour))
                .accessibilityAddTraits(choosingHour ? .isSelected : [])
                Text(":").font(.system(size: 22, weight: .medium)).foregroundStyle(Theme.secondary)
                Button { choosingHour = false } label: {
                    VStack(spacing: 4) {
                        Text(chinese ? "分钟" : "Minute").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        Text(String(format: "%02d", minute)).font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
                    }
                    .calendarChoiceLabel(height: 64)
                }
                .buttonStyle(CalendarChoiceStyle(selected: !choosingHour))
                .accessibilityLabel(chinese ? "选择分钟" : "Choose minute")
                .accessibilityValue(String(format: "%02d", minute))
                .accessibilityAddTraits(!choosingHour ? .isSelected : [])
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(choosingHour ? (chinese ? "选择小时" : "Choose an hour") : (chinese ? "选择分钟" : "Choose a minute"))
                    Spacer()
                    Text(chinese ? "24 小时制" : "24-hour clock")
                }
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                    ForEach(0..<(choosingHour ? 24 : 60), id: \.self) { value in
                        Button {
                            if choosingHour { hour = value; choosingHour = false }
                            else { minute = value }
                        } label: { Text(String(format: "%02d", value)).monospacedDigit().calendarChoiceLabel() }
                        .buttonStyle(CalendarChoiceStyle(selected: (choosingHour ? hour : minute) == value))
                        .disabled(!choosingHour && CalendarSelection.replacingTime(of: date, hour: hour, minute: value, calendar: calendar) == nil)
                        .accessibilityLabel(choosingHour ? (chinese ? "\(value)时" : "Hour \(value)") : (chinese ? "\(value)分" : "Minute \(value)"))
                        .accessibilityAddTraits((choosingHour ? hour : minute) == value ? .isSelected : [])
                    }
                }
            }
            if selectedDate == nil {
                Text(chinese ? "夏令时切换导致这个时间不存在，请选择其他时间。" : "This time does not exist because of daylight saving. Choose another time.")
                    .font(.system(size: 11)).foregroundStyle(Theme.amber).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button(action: close) { Text(chinese ? "取消" : "Cancel").calendarChoiceLabel() }
                    .buttonStyle(CalendarChoiceStyle())
                Button {
                    if let selectedDate { date = selectedDate; close() }
                } label: { Text(chinese ? "确定" : "Done").calendarChoiceLabel() }
                .buttonStyle(CalendarChoiceStyle(selected: true))
                .disabled(selectedDate == nil)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(20).frame(width: 316)
        .background(Theme.card).foregroundStyle(Theme.ink)
        .onExitCommand(perform: close)
    }
}

private struct CalendarChoiceStyle: ButtonStyle {
    var selected = false
    var today = false
    func makeBody(configuration: Configuration) -> some View {
        CalendarChoiceSurface(configuration: configuration, selected: selected, today: today)
    }
}

private struct CalendarChoiceSurface: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    let today: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        configuration.label
            .font(.system(size: 12, weight: selected || today ? .semibold : .medium))
            .lineLimit(1).minimumScaleFactor(0.85)
            .foregroundStyle((selected || today) && colorScheme != .dark ? Theme.accent : Theme.ink)
            .background(selected ? Theme.accent.opacity(0.14) : hovering ? Theme.inset : .clear, in: shape)
            .overlay(shape.strokeBorder(focused ? Theme.accent.opacity(0.6) : today ? Theme.accent.opacity(0.25) : .clear))
            .opacity(enabled ? configuration.isPressed ? 0.65 : 1 : 0.3)
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private extension View {
    func calendarChoiceLabel(height: CGFloat = 36) -> some View {
        frame(maxWidth: .infinity).frame(height: height)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
