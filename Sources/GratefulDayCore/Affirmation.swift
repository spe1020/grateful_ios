import Foundation

/// Daily Affirmations, shared with web via `Resources/affirmations.json`
/// (exported from gratefulday; the commit is in the file). Port of `getAffirmationForDay` in
/// `src/lib/gratitudeUtils.ts`; the lines are Grateful Day's own writing.
public struct AffirmationLibrary: Sendable {
    struct Rotation: Codable, Sendable { let stride: Int; let yearStride: Int }
    struct File: Codable {
        let version: Int; let rotation: Rotation; let items: [String]
        let sourceCommit: String?; let itemsSha256: String?
    }

    public let items: [String]
    let rotation: Rotation
    /// The gratefulday commit the items were exported from, and the export's
    /// SHA-256 of the items joined with "\n" (text parity, spec AC 6).
    public let sourceCommit: String?
    public let itemsSha256: String?

    public init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        items = file.items
        rotation = file.rotation
        sourceCommit = file.sourceCommit
        itemsSha256 = file.itemsSha256
    }

    /// GratefulDayCore's resource bundle.
    static var resourceBundle: Bundle { .module }

    /// The bundled library.
    public static func bundled() throws -> AffirmationLibrary {
        guard let url = Bundle.module.url(forResource: "affirmations", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try AffirmationLibrary(data: Data(contentsOf: url))
    }

    /// Affirmation for a local calendar date (`YYYY-MM-DD`), as web shows it.
    public func affirmation(forDate dateString: String) -> String? {
        index(forDate: dateString).map { items[$0] }
    }

    /// Web `dailyPoolIndex(dayOfYear, year, n, stride, yearStride)`.
    func index(forDate dateString: String) -> Int? {
        guard !items.isEmpty, let (year, dayOfYear) = Self.yearAndDayOfYear(dateString) else { return nil }
        let n = items.count
        let raw = (dayOfYear - 1) * rotation.stride + year * rotation.yearStride
        return ((raw % n) + n) % n
    }

    /// Year and day of year (1–366) of a `YYYY-MM-DD` string, always on the
    /// Gregorian calendar (web `getDayOfYear` on the local y/m/d), never
    /// `Calendar.current`.
    static func yearAndDayOfYear(_ dateString: String) -> (Int, Int)? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let p = dateString.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3,
              let date = cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2])),
              cal.component(.month, from: date) == p[1], cal.component(.day, from: date) == p[2],
              let doy = cal.ordinality(of: .day, in: .year, for: date)
        else { return nil }
        return (p[0], doy)
    }
}
