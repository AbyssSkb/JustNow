import AppKit
import SwiftUI
import JustNowCore

struct JournalEventInputRow: Identifiable, Equatable {
    let id: UUID
    var topic: String
    var content: String

    init(id: UUID = UUID(), topic: String = "", content: String = "") {
        self.id = id
        self.topic = topic
        self.content = content
    }

    static func rows(for text: String) -> [Self] {
        let rows = JournalEvents.parse(text).map { Self(topic: $0.topic ?? "", content: $0.content) }
        return rows.isEmpty ? [Self()] : rows
    }

    static func inputText(for rows: [Self]) -> String {
        JournalEvents.inputText(for: rows.compactMap { row in
            let topic = row.topic.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !topic.isEmpty || !row.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let isOther = topic == "其他" || topic.caseInsensitiveCompare("Other") == .orderedSame
            return JournalEvent(topic: topic.isEmpty || isOther ? nil : topic, content: row.content)
        })
    }
}

struct JournalEventEditor: View {
    @ObservedObject var model: AppModel
    @Binding var text: String
    @Binding var focused: Bool
    var onHeightChange: ((CGFloat) -> Void)? = nil
    @State private var rows: [JournalEventInputRow] = [JournalEventInputRow()]
    @State private var focus: Field?
    @State private var lastEmitted = ""
    @State private var lastReportedHeight: CGFloat?

    private enum Field: Equatable { case topic(UUID), content(UUID) }

    init(model: AppModel, text: Binding<String>, focused: Binding<Bool>, onHeightChange: ((CGFloat) -> Void)? = nil) {
        self.model = model
        _text = text
        _focused = focused
        self.onHeightChange = onHeightChange
        _rows = State(initialValue: JournalEventInputRow.rows(for: text.wrappedValue))
        _lastEmitted = State(initialValue: text.wrappedValue)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            eventRow(row, index: index, width: geometry.size.width,
                                     viewportHeight: geometry.size.height).id(row.id)
                        }
                        Button { append(after: rows.last!.id) } label: {
                            Label(model.text("新增事项", "Add an event"), systemImage: "plus")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.secondary)
                                .frame(maxWidth: .infinity).frame(height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 2)
                }
                .scrollIndicators(.hidden)
                .onChange(of: focus) { _, newFocus in
                    focused = newFocus != nil
                    guard let newFocus else { return }
                    let id: UUID
                    switch newFocus { case .topic(let value), .content(let value): id = value }
                    proxy.scrollTo(id)
                }
                .onAppear { reportHeight(width: geometry.size.width) }
                .onChange(of: rows) { _, _ in reportHeight(width: geometry.size.width) }
                .onChange(of: geometry.size.width) { _, width in reportHeight(width: width) }
            }
        }
        .onAppear {
            if focused { focus = .topic(rows[0].id) }
        }
        .onChange(of: text) { _, value in
            if value != lastEmitted { load(value) }
        }
        .onChange(of: focused) { _, value in
            if value, focus == nil { focus = .topic(rows[0].id) }
        }
    }

    private func eventRow(_ row: JournalEventInputRow, index: Int, width: CGFloat, viewportHeight: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index + 1)").font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.secondary).frame(width: 16, height: 44)
                .accessibilityHidden(true)
            EventTopicField(text: topicBinding(row.id), focused: focusBinding(.topic(row.id)),
                            placeholder: model.text("其他", "Other"),
                            label: model.text("第 \(index + 1) 项主题", "Event \(index + 1) topic"),
                            onAdvance: { suffix in advanceToContent(row.id, suffix: suffix) },
                            onNext: { append(after: row.id) })
                .frame(height: 20).padding(.horizontal, 12).frame(width: 106, height: 44)
                .background(Theme.inset, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(focus == .topic(row.id) ? Theme.accent.opacity(0.65) : Theme.line))
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { focus = .topic(row.id) })
            JournalTextEditor(text: contentBinding(row.id), placeholder: model.text("具体做了什么？", "What did you do?"),
                              focused: focusBinding(.content(row.id)), onNextEvent: { append(after: row.id) })
                .frame(height: min(Self.contentHeight(row.content, width: width - 182), max(44, viewportHeight - 46)))
                .accessibilityLabel(model.text("第 \(index + 1) 项内容", "Event \(index + 1) details"))
            if rows.count > 1 {
                Button { remove(row.id) } label: {
                    Image(systemName: "minus").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.secondary).frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.text("删除这一项", "Remove this event"))
                .accessibilityLabel(model.text("删除第 \(index + 1) 项", "Remove event \(index + 1)"))
            } else {
                Color.clear.frame(width: 36, height: 44).accessibilityHidden(true)
            }
        }
    }

    private static func contentHeight(_ content: String, width: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        let bounds = ((content.isEmpty ? " " : content) as NSString).boundingRect(
            with: NSSize(width: max(40, width - 28), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: NSFont.systemFont(ofSize: 13), .paragraphStyle: paragraph])
        return max(44, ceil(bounds.height) + 24)
    }

    static func height(for rows: [JournalEventInputRow], width: CGFloat) -> CGFloat {
        rows.reduce(CGFloat(38 + rows.count * 8)) {
            $0 + contentHeight($1.content, width: width - 182)
        }
    }

    private func reportHeight(width: CGFloat) {
        guard width > 0 else { return }
        let height = Self.height(for: rows, width: width)
        guard height != lastReportedHeight else { return }
        lastReportedHeight = height
        onHeightChange?(height)
    }

    private func topicBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { rows.first(where: { $0.id == id })?.topic ?? "" }, set: { value in
            guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
            rows[index].topic = value
            emit()
        })
    }

    private func contentBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { rows.first(where: { $0.id == id })?.content ?? "" }, set: { value in
            guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
            rows[index].content = value
            emit()
        })
    }

    private func focusBinding(_ field: Field) -> Binding<Bool> {
        Binding(get: { focus == field }, set: { value in
            if value { focus = field }
            else if focus == field { focus = nil }
        })
    }

    private func advanceToContent(_ id: UUID, suffix: String) {
        let suffix = suffix.map { $0.isNewline ? " " : String($0) }.joined()
        if !suffix.isEmpty, let row = rows.first(where: { $0.id == id }) {
            contentBinding(id).wrappedValue = row.content.isEmpty ? suffix : row.content + " " + suffix
        }
        focus = .content(id)
    }

    private func append(after id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let row = JournalEventInputRow()
        rows.insert(row, at: index + 1)
        focus = .topic(row.id)
        emit()
    }

    private func remove(_ id: UUID) {
        guard rows.count > 1, let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows.remove(at: index)
        if focus == .topic(id) || focus == .content(id) { focus = .topic(rows[min(index, rows.count - 1)].id) }
        emit()
    }

    private func emit() {
        lastEmitted = JournalEventInputRow.inputText(for: rows)
        text = lastEmitted
    }

    private func load(_ value: String) {
        lastEmitted = value
        rows = JournalEventInputRow.rows(for: value)
        focus = focused ? .topic(rows[0].id) : nil
    }
}

private struct EventTopicField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let placeholder: String
    let label: String
    let onAdvance: (String) -> Void
    let onNext: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> TopicNSTextField {
        let field = TopicNSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 13, weight: .medium)
        field.textColor = NSColor(Theme.accent)
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: TopicNSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text, !((field.currentEditor() as? NSTextView)?.hasMarkedText() ?? false) {
            field.stringValue = text
        }
        field.placeholderString = placeholder
        field.setAccessibilityLabel(label)
        field.wantsFocus = focused
        field.focusIfRequested()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: EventTopicField
        init(_ parent: EventTopicField) { self.parent = parent }

        func controlTextDidBeginEditing(_ notification: Notification) { parent.focused = true }
        func controlTextDidEndEditing(_ notification: Notification) {
            if let field = notification.object as? NSTextField { commit(field.stringValue) }
            parent.focused = false
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  !((field.currentEditor() as? NSTextView)?.hasMarkedText() ?? false) else { return }
            commit(field.stringValue)
        }

        private func commit(_ value: String) {
            guard let separator = value.firstIndex(where: \.isWhitespace) else {
                parent.text = value
                return
            }
            parent.text = String(value[..<separator])
            let suffix = String(value[value.index(after: separator)...])
            DispatchQueue.main.async { [weak self] in self?.parent.onAdvance(suffix) }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard !textView.hasMarkedText(), !(NSApp.currentEvent?.modifierFlags.contains(.command) ?? false) else { return false }
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                parent.onAdvance("")
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onNext()
                return true
            }
            return false
        }
    }
}

private final class TopicNSTextField: NSTextField {
    var wantsFocus = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusIfRequested()
    }

    func focusIfRequested() {
        guard wantsFocus, let window, window.firstResponder !== currentEditor() else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.wantsFocus else { return }
            self.window?.makeFirstResponder(self)
        }
    }
}
