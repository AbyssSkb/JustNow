import AppKit
import SwiftUI

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
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        let editor = JournalNSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 180))
        editor.isEditable = true
        editor.isSelectable = true
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 13)
        editor.textColor = NSColor(Theme.ink)
        editor.insertionPointColor = NSColor(Theme.accent)
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
            NativeJournalDatePicker(date: $date, calendar: true, label: label, locale: locale, focused: .constant(false))
                .frame(width: 260, height: 210).padding(12)
        }
    }
}

struct JournalTimeField: View {
    @Binding var date: Date
    let label: String
    @State private var focused = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            NativeJournalDatePicker(date: $date, calendar: false, label: label, locale: Locale(identifier: "en_GB"), focused: $focused)
                .frame(width: 56, height: 20)
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(focused ? Theme.accent.opacity(0.65) : Theme.line))
    }
}

private struct NativeJournalDatePicker: NSViewRepresentable {
    @Binding var date: Date
    let calendar: Bool
    let label: String
    let locale: Locale
    @Binding var focused: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> JournalNSDatePicker {
        let picker = JournalNSDatePicker()
        picker.datePickerStyle = calendar ? .clockAndCalendar : .textField
        picker.datePickerElements = calendar ? .yearMonthDay : .hourMinute
        picker.isBezeled = false
        picker.isBordered = false
        picker.drawsBackground = false
        picker.focusRingType = .none
        picker.isContinuous = true
        picker.font = calendar ? .systemFont(ofSize: 13) : .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        picker.textColor = NSColor(Theme.ink)
        picker.dateValue = date
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        picker.onFocusChanged = { context.coordinator.parent.focused = $0 }
        return picker
    }

    func updateNSView(_ picker: JournalNSDatePicker, context: Context) {
        context.coordinator.parent = self
        if picker.locale != locale { picker.locale = locale }
        picker.setAccessibilityLabel(label)
        if picker.dateValue != date { picker.dateValue = date }
    }

    final class Coordinator: NSObject {
        var parent: NativeJournalDatePicker
        init(_ parent: NativeJournalDatePicker) { self.parent = parent }
        @objc func changed(_ picker: NSDatePicker) { parent.date = picker.dateValue }
    }
}

private final class JournalNSDatePicker: NSDatePicker {
    var onFocusChanged: ((Bool) -> Void)?
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
