import SwiftUI
import JustNowCore

struct TopicSummary: Identifiable {
    let id: String
    let name: String?
    var eventCount = 0
    var entryIDs: Set<UUID> = []

    static func key(_ topic: String?) -> String {
        (topic ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func aggregate(_ entries: [JournalEntry]) -> [TopicSummary] {
        var topics: [String: TopicSummary] = [:]
        for entry in entries.filter({ !$0.isPending }).sorted(by: { $0.start > $1.start }) {
            for event in entry.events ?? [] where !event.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let key = key(event.topic)
                var summary = topics[key] ?? TopicSummary(id: key, name: event.topic)
                summary.eventCount += 1
                summary.entryIDs.insert(entry.id)
                topics[key] = summary
            }
        }
        return topics.values.sorted {
            $0.eventCount == $1.eventCount ? ($0.name ?? "").localizedStandardCompare($1.name ?? "") == .orderedAscending : $0.eventCount > $1.eventCount
        }
    }
}

struct TopicsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedTopic: String?

    private var summaries: [TopicSummary] { TopicSummary.aggregate(model.entries) }
    private var eventCount: Int { summaries.reduce(0) { $0 + $1.eventCount } }
    private var intervalCount: Int { summaries.reduce(into: Set<UUID>()) { $0.formUnion($1.entryIDs) }.count }
    private var legacyCount: Int { model.entries.filter { !$0.isPending && $0.events == nil }.count }
    private var selectedName: String {
        selectedTopic.flatMap { key in summaries.first { $0.id == key }.map { topicName($0.name) } }
            ?? model.text("全部事件", "All events")
    }
    private var matchingEntries: [(entry: JournalEntry, events: [JournalEvent])] {
        model.entries.filter { !$0.isPending }.sorted { $0.start > $1.start }.compactMap { entry in
            let events = (entry.events ?? []).filter {
                !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && (selectedTopic == nil || TopicSummary.key($0.topic) == selectedTopic)
            }
            return events.isEmpty ? nil : (entry, events)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !summaries.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.text("\(summaries.count) 个主题 · \(eventCount) 件事", "\(summaries.count) topics · \(eventCount) events"))
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(model.text("覆盖 \(intervalCount) 个时段", "Across \(intervalCount) intervals"))
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
                    topicButton(id: nil, name: model.text("全部", "All"), events: eventCount, intervals: intervalCount)
                    ForEach(summaries) { summary in
                        topicButton(id: summary.id, name: topicName(summary.name), events: summary.eventCount, intervals: summary.entryIDs.count)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(selectedName).font(.system(size: 14, weight: .semibold))
                    ForEach(matchingEntries, id: \.entry.id) { group in
                        entryCard(group.entry, events: group.events)
                    }
                }
            } else {
                VStack(spacing: 13) {
                    Image(systemName: "square.grid.2x2").font(.system(size: 30, weight: .ultraLight))
                        .foregroundStyle(Theme.accent)
                    Text(model.text("做过的事，慢慢归成主题", "Your events, gathered into topics"))
                        .font(.system(size: 15, weight: .medium))
                    Text(model.text("记录时写下主题和内容，保存后就会出现在这里。", "Write a topic and its details when recording. Saved events appear here."))
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 32).journalCard()
            }
            if legacyCount > 0 {
                Text(model.text("\(legacyCount) 段旧记录保留原文；编辑并保存后，可按主题归类。", "\(legacyCount) older intervals retain their original text. Edit and save them to classify by topic."))
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(3)
            }
        }
        .onChange(of: summaries.map(\.id)) { _, keys in
            if let selectedTopic, !keys.contains(selectedTopic) { self.selectedTopic = nil }
        }
    }

    private func topicButton(id: String?, name: String, events: Int, intervals: Int) -> some View {
        let selected = selectedTopic == id
        return Button { selectedTopic = id } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Text(name).font(.system(size: 13, weight: .semibold)).lineLimit(1).help(name)
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)) }
                }
                Text(model.text("\(events) 件事 · \(intervals) 个时段", "\(events) events · \(intervals) intervals"))
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            .foregroundStyle(selected ? Theme.accent : Theme.ink)
            .padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.accent.opacity(0.06) : Theme.card, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(selected ? Theme.accent.opacity(0.55) : Theme.line))
            .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func entryCard(_ entry: JournalEntry, events: [JournalEvent]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(entry.start.formatted(.dateTime.year().month().day().locale(Locale(identifier: model.text("zh_CN", "en_US")))))
                Text(entry.start.formatted(.dateTime.hour().minute()) + " – " + entry.end.formatted(.dateTime.hour().minute()))
                    .monospacedDigit()
            }
            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            JournalEventList(model: model, events: events).textSelection(.enabled)
        }
        .journalCard(padding: 20)
    }

    private func topicName(_ topic: String?) -> String { topic ?? model.text("其他", "Other") }
}
