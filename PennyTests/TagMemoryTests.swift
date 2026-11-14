import XCTest
import SwiftData
@testable import Penny

/// "Remember tags for each place": a place's new payments get the tags you last gave it.
final class TagMemoryTests: XCTestCase {
    let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 15))!

    func sms(_ amount: Int, ref: String, day: Int = 6) -> String {
        """
        Dr INR \(amount).00 - AU A/c X6977 \(String(format: "%02d", day))-NOV-2026
        UPI/DR/\(ref)/ZEPTO MARKETPLACE
        Bal INR 40,000.00
        """
    }

    @MainActor
    func makeContext() throws -> ModelContext {
        UserDefaults.standard.removeObject(forKey: TagMemory.settingKey)
        let container = try ModelContainer(for: Txn.self, Payee.self, PlaceTags.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    @MainActor
    func payments(_ ctx: ModelContext) throws -> [Txn] {
        try ctx.fetch(FetchDescriptor<Txn>(sortBy: [SortDescriptor(\.amount)]))
    }

    @MainActor
    func testNewPaymentGetsPlaceTags() throws {
        let ctx = try makeContext()
        let first = try XCTUnwrap(Ingestor.ingest(sms(139, ref: "600000000001"), context: ctx, now: now).txn)
        XCTAssertEqual(first.tags, [])
        first.tags = ["grocery", "food"]
        TagMemory.remember(first, context: ctx)

        let second = try XCTUnwrap(Ingestor.ingest(sms(250, ref: "600000000002"), context: ctx, now: now).txn)
        XCTAssertEqual(second.tags, ["grocery", "food"])
    }

    @MainActor
    func testLatestTagsWin() throws {
        let ctx = try makeContext()
        let a = try XCTUnwrap(Ingestor.ingest(sms(139, ref: "600000000001"), context: ctx, now: now).txn)
        a.tags = ["grocery"]
        TagMemory.remember(a, context: ctx)
        let b = try XCTUnwrap(Ingestor.ingest(sms(250, ref: "600000000002"), context: ctx, now: now).txn)
        b.tags = ["snacks"]                       // you change your mind on a later one
        TagMemory.remember(b, context: ctx)

        let c = try XCTUnwrap(Ingestor.ingest(sms(310, ref: "600000000003"), context: ctx, now: now).txn)
        XCTAssertEqual(c.tags, ["snacks"])
        XCTAssertEqual(a.tags, ["grocery"])       // earlier payments keep what you gave them
    }

    @MainActor
    func testOffMeansNoAutoTags() throws {
        let ctx = try makeContext()
        let a = try XCTUnwrap(Ingestor.ingest(sms(139, ref: "600000000001"), context: ctx, now: now).txn)
        a.tags = ["grocery"]
        TagMemory.remember(a, context: ctx)
        UserDefaults.standard.set(false, forKey: TagMemory.settingKey)
        defer { UserDefaults.standard.removeObject(forKey: TagMemory.settingKey) }

        let b = try XCTUnwrap(Ingestor.ingest(sms(250, ref: "600000000002"), context: ctx, now: now).txn)
        XCTAssertEqual(b.tags, [])
    }

    @MainActor
    func testTagPastOnlyFillsUntagged() throws {
        let ctx = try makeContext()
        let untagged = try XCTUnwrap(Ingestor.ingest(sms(100, ref: "600000000001", day: 1), context: ctx, now: now).txn)
        let tagged = try XCTUnwrap(Ingestor.ingest(sms(200, ref: "600000000002", day: 2), context: ctx, now: now).txn)
        tagged.tags = ["treat"]
        let latest = try XCTUnwrap(Ingestor.ingest(sms(300, ref: "600000000003", day: 3), context: ctx, now: now).txn)
        latest.tags = ["grocery"]
        TagMemory.remember(latest, context: ctx)

        XCTAssertEqual(TagMemory.applyToPast(context: ctx), 1)
        XCTAssertEqual(untagged.tags, ["grocery"])
        XCTAssertEqual(tagged.tags, ["treat"])     // what you tagged stays as it is
    }

    @MainActor
    func testOlderPayeeAutoTagStillWorks() throws {
        let ctx = try makeContext()
        ctx.insert(Payee(key: "ZEPTO MARKETPLACE", name: "Zepto", defaultTag: "grocery"))
        let t = try XCTUnwrap(Ingestor.ingest(sms(139, ref: "600000000001"), context: ctx, now: now).txn)
        XCTAssertEqual(t.tags, ["grocery"])
    }
}
