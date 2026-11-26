import Foundation

/// Overflow-safe, clamped integer arithmetic and parsing shared across Tally apps.
public enum TallyMath: Sendable {
    public static let maxMagnitude = 999_999_999
    public static let maxCount = 999
    public static let maxRulePoints = 1_000_000

    public static func clamp(
        _ value: Int,
        min minValue: Int = -maxMagnitude,
        max maxValue: Int = maxMagnitude
    ) -> Int {
        Swift.min(Swift.max(value, minValue), maxValue)
    }

    public static func clampCount(
        _ value: Int,
        min minValue: Int = 0,
        max maxValue: Int = maxCount
    ) -> Int {
        clamp(value, min: minValue, max: maxValue)
    }

    public static func parseInt(
        _ text: String,
        min minValue: Int = -maxMagnitude,
        max maxValue: Int = maxMagnitude
    ) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Int(trimmed) else { return nil }
        return clamp(parsed, min: minValue, max: maxValue)
    }

    public static func parsePositiveInt(
        _ text: String,
        max maxValue: Int = maxMagnitude
    ) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Int(trimmed), parsed > 0 else { return nil }
        return Swift.min(parsed, maxValue)
    }

    public static func parseNonNegativeInt(
        _ text: String,
        max maxValue: Int = maxMagnitude
    ) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Int(trimmed), parsed >= 0 else { return nil }
        return Swift.min(parsed, maxValue)
    }

    public static func parseCount(
        _ text: String,
        min minValue: Int = 0,
        max maxValue: Int = maxCount
    ) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Int(trimmed) else { return nil }
        return clampCount(parsed, min: minValue, max: maxValue)
    }

    public static func add(_ lhs: Int, _ rhs: Int) -> Int {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        if overflow {
            return rhs > 0 ? maxMagnitude : -maxMagnitude
        }
        return clamp(result)
    }

    public static func subtract(_ lhs: Int, _ rhs: Int) -> Int {
        let (result, overflow) = lhs.subtractingReportingOverflow(rhs)
        if overflow {
            return rhs > 0 ? -maxMagnitude : maxMagnitude
        }
        return clamp(result)
    }

    public static func multiply(_ lhs: Int, _ rhs: Int) -> Int {
        let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        if overflow {
            return (lhs >= 0) == (rhs >= 0) ? maxMagnitude : -maxMagnitude
        }
        return clamp(result)
    }

    public static func sum(_ values: [Int]) -> Int {
        values.reduce(0, add)
    }
}
