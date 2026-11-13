import Foundation

// MARK: - Units

/// Temperatures are stored in °C and shown in the user's unit (°F by default).
public enum TemperatureUnit: String, Codable, Hashable, Sendable, CaseIterable {
    case fahrenheit, celsius

    public static let `default` = TemperatureUnit.fahrenheit

    public var symbol: String { self == .celsius ? "°C" : "°F" }

    /// "Fahrenheit (°F)"
    public var name: String { self == .celsius ? "Celsius (°C)" : "Fahrenheit (°F)" }

    public func fromCelsius(_ celsius: Double) -> Double {
        self == .celsius ? celsius : celsius * 9 / 5 + 32
    }

    public func toCelsius(_ value: Double) -> Double {
        self == .celsius ? value : (value - 32) * 5 / 9
    }

    /// "75°F"
    public func format(celsius: Double) -> String {
        "\(Int(fromCelsius(celsius).rounded()))\(symbol)"
    }
}

// MARK: - Formatting

public enum Format {
    /// 0.725 → "72.5%", 0.72 → "72%".
    public static func percent(_ fraction: Double) -> String {
        number((fraction * 1000).rounded() / 10) + "%"
    }

    /// 2700 → "45 min", 5400 → "1 h 30 min", 43200 → "12 h".
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        let (h, m) = (minutes / 60, minutes % 60)
        switch (h, m) {
        case (0, _): return "\(m) min"
        case (_, 0): return "\(h) h"
        default: return "\(h) h \(m) min"
        }
    }

    /// Drops a trailing ".0".
    public static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

// MARK: - Timers (SPEC §4.1)

public enum BakeTimer: String, Codable, Hashable, Sendable, CaseIterable {
    case autolyse, fold, bulk, proof, cold, covered, uncovered

    public var step: BakeStep {
        switch self {
        case .autolyse: .mix
        case .fold, .bulk: .bulk
        case .proof: .proof
        case .cold: .cold
        case .covered, .uncovered: .bake
        }
    }
}

public enum TimerSchedule {
    /// Every notification for a bake starts with this, so they can all be cancelled together.
    public static func notificationPrefix(bakeID: UUID) -> String {
        "bake-\(bakeID.uuidString)-"
    }

    /// "bake-<id>-fold-2"
    public static func notificationID(bakeID: UUID, timer: BakeTimer, index: Int? = nil) -> String {
        notificationPrefix(bakeID: bakeID) + timer.rawValue + (index.map { "-\($0)" } ?? "")
    }

    /// Time left, computed from the stored start so it survives the app being closed. Never negative.
    public static func remaining(start: Date, duration: TimeInterval, now: Date = Date()) -> TimeInterval {
        max(0, start.addingTimeInterval(duration).timeIntervalSince(now))
    }

    /// When each set of folds is due: one interval after bulk starts, then every interval.
    public static func foldTimes(bulkStart: Date, sets: Int, interval: TimeInterval) -> [Date] {
        guard sets > 0, interval > 0 else { return [] }
        return (1...sets).map { bulkStart.addingTimeInterval(interval * Double($0)) }
    }
}

// MARK: - Storage

/// JSON coding for the Codable values stored inside SwiftData models.
public enum StoredJSON {
    public static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)) ?? Data()
    }

    /// nil for empty or unreadable data.
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
