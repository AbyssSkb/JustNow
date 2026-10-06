import Foundation

public enum JournalExport {
    public static func csv(entries: [JournalEntry]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let rows = entries.sorted { $0.start < $1.start }.map { entry in
            [formatter.string(from: entry.start), formatter.string(from: entry.end),
             String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), entry.duration / 60),
             entry.status.rawValue, entry.text].map(csvCell).joined(separator: ",")
        }
        return (["Start,End,Duration (minutes),Status,Note"] + rows).joined(separator: "\r\n") + "\r\n"
    }

    public static func json(entries: [JournalEntry]) throws -> Data {
        let encoder = JSONEncoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return try encoder.encode(entries.sorted { $0.start < $1.start })
    }

    private static func csvCell(_ value: String) -> String {
        let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first
        let safe = first.map { "=+-@".contains($0) } == true ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
