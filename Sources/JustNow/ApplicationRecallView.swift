import AppKit
import SwiftUI
import JustNowCore

struct ApplicationRecallView: View {
    @ObservedObject var model: AppModel
    let summary: ApplicationUsageSummary
    var compact = false
    var inline = false
    @State private var showingAll = false
    @MainActor private static var icons: [String: NSImage] = [:]

    @ViewBuilder var body: some View {
        if inline { inlineRecall }
        else { expandedRecall }
    }

    private var inlineRecall: some View {
        HStack(spacing: 10) {
            Text(model.text("回忆线索", "A few clues"))
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondary)
                .fixedSize()
            if summary.applications.isEmpty {
                Text(model.text("暂无应用线索", "No app clues"))
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
            } else {
                ForEach(Array(summary.applications.prefix(3).enumerated()), id: \.offset) { _, application in
                    HStack(spacing: 4) {
                        applicationIcon(application).frame(width: 18, height: 18)
                        Text(share(application.seconds))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                    }
                    .fixedSize()
                    .help("\(application.name) · \(elapsed(application.seconds)) · \(share(application.seconds))")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(application.name), \(elapsed(application.seconds)), \(share(application.seconds))")
                }
            }
            Spacer(minLength: 0)
            Button { showingAll = true } label: {
                HStack(spacing: 4) {
                    Text(model.text("全部", "All"))
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                .frame(minWidth: 50, minHeight: 40).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.text("查看全部应用线索", "View all app clues"))
            .popover(isPresented: $showingAll) { allApplications }
        }
        .frame(minHeight: 40)
    }

    private var expandedRecall: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "rectangle.on.rectangle").foregroundStyle(Theme.accent)
                Text(model.text("回忆线索", "A few clues")).font(.system(size: 11, weight: .semibold))
                Spacer()
                Button { showingAll = true } label: {
                    Text(model.text("查看全部", "View all"))
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.accent)
                        .frame(minWidth: 74, minHeight: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingAll) { allApplications }
            }
            if summary.applications.isEmpty {
                Text(model.text("这段时间没有可用的应用线索。", "No app clues are available for this moment."))
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            } else {
                ForEach(Array(summary.applications.prefix(compact ? 2 : 3).enumerated()), id: \.offset) { _, application in
                    applicationRow(application)
                }
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 11))
    }

    private var allApplications: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.text("这段时间用过的应用", "Apps used during this moment"))
                .font(.system(size: 13, weight: .semibold))
            Text(summary.start.formatted(.dateTime.hour().minute()) + " – " + summary.end.formatted(.dateTime.hour().minute()))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.secondary)
            ScrollView {
                VStack(spacing: 11) {
                    ForEach(Array(summary.applications.enumerated()), id: \.offset) { _, application in
                        applicationRow(application)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: min(260, CGFloat(summary.applications.count) * 31))
            if summary.duration - summary.observedSeconds >= 1 {
                Text(model.text("另有 \(elapsed(summary.duration - summary.observedSeconds)) 未统计", "\(elapsed(summary.duration - summary.observedSeconds)) was not observed"))
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            Text(model.text("占比以这个时段的总时长为基准，只统计前台停留时间，帮助你回忆细节。", "Shares use the whole interval. Only foreground time is counted, to help you recall the details."))
                .font(.system(size: 10)).foregroundStyle(Theme.secondary).lineSpacing(3)
        }
        .padding(20).frame(width: 340).foregroundStyle(Theme.ink).background(Theme.background)
    }

    private func applicationRow(_ application: ApplicationUsage) -> some View {
        HStack(spacing: 8) {
            applicationIcon(application)
            .frame(width: 19, height: 19)
            Text(application.name).font(.system(size: 11, weight: .medium))
                .lineLimit(1).help(application.name)
            Spacer(minLength: 8)
            Text(elapsed(application.seconds)).font(.system(size: 10)).foregroundStyle(Theme.secondary)
            Text(share(application.seconds)).font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.accent).frame(width: 35, alignment: .trailing)
        }
    }

    private func applicationIcon(_ application: ApplicationUsage) -> some View {
        Group {
            if let icon = icon(for: application) { Image(nsImage: icon).resizable() }
            else { Image(systemName: "app").resizable().foregroundStyle(Theme.accent) }
        }
    }

    private func share(_ seconds: TimeInterval) -> String {
        let value = min(100, max(0, seconds / max(1, summary.duration) * 100))
        return value > 0 && value < 1 ? "<1%" : "\(Int(value.rounded()))%"
    }

    private func elapsed(_ seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds).rounded())
        return value < 60 ? model.text("\(value) 秒", "\(value)s") : model.text("\(value / 60) 分钟", "\(value / 60)m")
    }

    @MainActor private func icon(for application: ApplicationUsage) -> NSImage? {
        guard let identifier = application.bundleIdentifier else { return nil }
        if let cached = Self.icons[identifier] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        Self.icons[identifier] = image
        return image
    }
}
