import Foundation
import SwiftData
import Testing
@testable import TallyCore

@Suite("TallyMath Tests")
struct TallyMathTests {
    @Test("Clamps values to default and custom bounds")
    func clamping() {
        #expect(TallyMath.clamp(42) == 42)
        #expect(TallyMath.clamp(2_000_000_000) == TallyMath.maxMagnitude)
        #expect(TallyMath.clamp(-2_000_000_000) == -TallyMath.maxMagnitude)
        #expect(TallyMath.clampCount(1500) == TallyMath.maxCount)
        #expect(TallyMath.clampCount(-5) == 0)
        #expect(TallyMath.clampCount(-5, min: -12, max: 12) == -5)
        #expect(TallyMath.clampCount(-20, min: -12, max: 12) == -12)
    }

    @Test("Parses integers with trimming, sign handling, and clamping")
    func parsing() {
        #expect(TallyMath.parseInt("  -42 ") == -42)
        #expect(TallyMath.parseInt("abc") == nil)
        #expect(TallyMath.parseInt("") == nil)
        #expect(TallyMath.parseInt("999999999999") == TallyMath.maxMagnitude)

        #expect(TallyMath.parsePositiveInt("0") == nil)
        #expect(TallyMath.parsePositiveInt("-5") == nil)
        #expect(TallyMath.parsePositiveInt("5000") == 5000)

        #expect(TallyMath.parseNonNegativeInt("0") == 0)
        #expect(TallyMath.parseNonNegativeInt("-1") == nil)
        #expect(TallyMath.parseNonNegativeInt("2500", max: TallyMath.maxRulePoints) == 2500)
        #expect(TallyMath.parseNonNegativeInt("9999999", max: TallyMath.maxRulePoints) == TallyMath.maxRulePoints)

        #expect(TallyMath.parseCount("-4", min: -12, max: 12) == -4)
        #expect(TallyMath.parseCount("1500") == TallyMath.maxCount)
    }

    @Test("Overflow-safe addition, subtraction, multiplication, and summation")
    func overflowSafeArithmetic() {
        #expect(TallyMath.add(Int.max, 1) == TallyMath.maxMagnitude)
        #expect(TallyMath.add(Int.min, -1) == -TallyMath.maxMagnitude)
        #expect(TallyMath.add(900_000_000, 200_000_000) == TallyMath.maxMagnitude)

        #expect(TallyMath.subtract(Int.min, 1) == -TallyMath.maxMagnitude)
        #expect(TallyMath.subtract(Int.max, -1) == TallyMath.maxMagnitude)
        #expect(TallyMath.subtract(100, 250) == -150)

        #expect(TallyMath.multiply(Int.max, 2) == TallyMath.maxMagnitude)
        #expect(TallyMath.multiply(Int.max, -2) == -TallyMath.maxMagnitude)
        #expect(TallyMath.multiply(-4, 100) == -400)

        #expect(TallyMath.sum([10, -3, 25]) == 32)
        #expect(TallyMath.sum([TallyMath.maxMagnitude, TallyMath.maxMagnitude]) == TallyMath.maxMagnitude)
    }
}

@Suite("TallyCore SwiftData Tests")
struct TallyCorePersistenceTests {
    @Test("In-memory container inserts and persists TallyPlayer cleanly")
    @MainActor
    func playerPersistence() throws {
        let schema = Schema([TallyPlayer.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let player = TallyPlayer(name: "Alice")
        context.insert(player)
        #expect(context.saveReportingError() == nil)

        let fetched = try context.fetch(FetchDescriptor<TallyPlayer>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Alice")
    }
}
