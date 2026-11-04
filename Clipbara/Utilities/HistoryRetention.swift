import Foundation

/// How long unpinned clips stay in history (Settings > General > Keep History For).
/// Works alongside the History Limit: a clip is removed when it falls outside either.
/// The raw value is the number of days; 0 keeps clips forever.
enum HistoryRetention: Int, CaseIterable, Identifiable, Sendable {
    case forever = 0
    case day = 1
    case week = 7
    case month = 30
    case threeMonths = 90
    case year = 365

    /// UserDefaults key holding the raw value (days).
    nonisolated static let defaultsKey = "historyRetentionDays"
    /// Used when nothing is stored, so existing installs keep every clip as before.
    nonisolated static let defaultValue: HistoryRetention = .forever

    var id: Int { rawValue }

    /// The stored setting; an unknown stored value falls back to the default.
    static var current: HistoryRetention {
        HistoryRetention(rawValue: UserDefaults.standard.integer(forKey: defaultsKey)) ?? defaultValue
    }

    /// Clips copied before this moment are expired.
    /// - Parameters:
    ///   - now: The moment to measure from.
    ///   - calendar: The calendar used to step back by whole days.
    /// - Returns: The cutoff date, or nil when clips are kept forever.
    func cutoff(from now: Date, calendar: Calendar = .current) -> Date? {
        guard self != .forever else { return nil }
        return calendar.date(byAdding: .day, value: -rawValue, to: now)
    }

    /// The name shown in the Settings picker.
    var displayName: String {
        switch self {
        case .forever: String(localized: "Forever")
        case .day: String(localized: "1 Day")
        case .week: String(localized: "1 Week")
        case .month: String(localized: "1 Month")
        case .threeMonths: String(localized: "3 Months")
        case .year: String(localized: "1 Year")
        }
    }
}
