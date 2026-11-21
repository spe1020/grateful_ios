import Foundation

/// Daily Wisdom, shared with web via `Resources/wisdom.json` (exported from
/// gratefulday @ a33f42c). Port of `getWisdomForDate` in `src/lib/wisdom.ts`.
public struct WisdomItem: Codable, Equatable, Sendable {
    public struct Provenance: Codable, Equatable, Sendable {
        public let wording: String
        public let url: String
        public let location: String
        public let credit: String?
    }
    public let id: String
    public let text: String
    public let author: String
    public let source: String?
    public let era: String?
    public let interpretation: String?
    public let prompt: String?
    public let themes: [String]?
    public let provenance: Provenance?
}

public struct WisdomLibrary: Sendable {
    struct Schedule: Codable, Sendable { let from: String; let itemIds: [String] }
    struct File: Codable { let version: Int; let schedules: [Schedule]; let items: [WisdomItem] }

    let schedules: [Schedule]
    public let items: [String: WisdomItem]

    public init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        schedules = file.schedules.sorted { $0.from < $1.from }
        items = Dictionary(file.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// The bundled library.
    public static func bundled() throws -> WisdomLibrary {
        guard let url = Bundle.module.url(forResource: "wisdom", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try WisdomLibrary(data: Data(contentsOf: url))
    }

    /// Wisdom for a local calendar date (`YYYY-MM-DD`). nil before the first schedule.
    public func item(forDate dateString: String) -> WisdomItem? {
        guard let schedule = schedules.last(where: { $0.from <= dateString }),
              let elapsed = Self.daysBetween(schedule.from, dateString), !schedule.itemIds.isEmpty
        else { return nil }
        return items[schedule.itemIds[elapsed % schedule.itemIds.count]]
    }

    static func daysBetween(_ a: String, _ b: String) -> Int? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        func date(_ s: String) -> Date? {
            let p = s.split(separator: "-").compactMap { Int($0) }
            guard p.count == 3 else { return nil }
            return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
        }
        guard let da = date(a), let db = date(b) else { return nil }
        return cal.dateComponents([.day], from: da, to: db).day
    }
}
