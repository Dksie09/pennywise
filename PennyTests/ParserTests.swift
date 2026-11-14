import XCTest
import SwiftData
@testable import Penny

final class ParserTests: XCTestCase {
    let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 15))!

    let upi = """
    Dr INR 139.00 - AU A/c X6977 06-NOV-2026
    UPI/DR/617601834096/ZEPTO MARKETPLACE
    Bal INR 49,774.79
    Fraud? Call 180012001200/SMS BLOCK UPI to 5676767
    """

    let card = """
    Dr INR 2,399.00 - AU A/c X6977 06-NOV-2026
    VIE-6754-356/239900-ANTHROPIC* CLAUDE SU
    Bal INR 47,375.79
    Fraud? Call 180012001200/SMS BLOCK <CUSTID> to 5676767
    """

    let heygen = """
    Your receipt from HeyGen Technology Inc. #2663-1049
    Receipt from HeyGen Technology Inc.
    $29.00
    Paid November 5, 2026
    """

    func testUPI() throws {
        let p = try XCTUnwrap(Parser.parse(upi, now: now))
        XCTAssertEqual(p.kind, .bank)
        XCTAssertEqual(p.amount, 139)
        XCTAssertEqual(p.vendor, "Zepto")
        XCTAssertEqual(p.rawPayee, "ZEPTO MARKETPLACE")
        XCTAssertEqual(p.method, "UPI")
        XCTAssertEqual(p.ref, "617601834096")
        XCTAssertEqual(p.balance, 49774.79)
        XCTAssertFalse(p.isCredit)
    }

    func testCard() throws {
        let p = try XCTUnwrap(Parser.parse(card, now: now))
        XCTAssertEqual(p.amount, 2399)
        XCTAssertEqual(p.vendor, "Anthropic")
        XCTAssertEqual(p.method, "Card")
    }

    func testSingleLineSMS() throws {
        let p = try XCTUnwrap(Parser.parse(upi.replacingOccurrences(of: "\n", with: " "), now: now))
        XCTAssertEqual(p.vendor, "Zepto")
    }

    func testReceipt() throws {
        let p = try XCTUnwrap(Parser.parse(heygen, now: now))
        XCTAssertEqual(p.kind, .receipt)
        XCTAssertEqual(p.amount, 29)
        XCTAssertEqual(p.currency, "USD")
        XCTAssertEqual(p.vendor, "HeyGen")
        XCTAssertEqual(p.ref, "2663-1049")
    }

    func testAppleReceiptItems() throws {
        let apple = """
        Your receipt from Apple.
        Tax Invoice
        Apple Account: someone@icloud.com
        iCloud+ 50GB   ₹75.00
        Subtotal ₹63.56
        GST ₹11.44
        TOTAL ₹75.00
        """
        let p = try XCTUnwrap(Parser.parse(apple, now: now))
        XCTAssertEqual(p.vendor, "Apple")
        XCTAssertEqual(p.amount, 75)
        XCTAssertEqual(p.items, [LineItem(name: "iCloud+ 50GB", price: 75)])
    }

    @MainActor
    func testDedupeAndMerge() throws {
        let container = try ModelContainer(for: Txn.self, Payee.self, PlaceTags.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext

        XCTAssertEqual(Ingestor.ingest(upi, context: ctx, now: now).status, .added)
        XCTAssertEqual(Ingestor.ingest(upi, context: ctx, now: now).status, .duplicate)
        // Same debit, slightly different SMS wording -> still a duplicate (same ref).
        XCTAssertEqual(Ingestor.ingest(upi.replacingOccurrences(of: "Fraud?", with: "Not you?"), context: ctx, now: now).status, .duplicate)

        // Receipt first, then bank SMS for it -> one entry.
        XCTAssertEqual(Ingestor.ingest(heygen, context: ctx, now: now).status, .added)
        let heygenSMS = """
        Dr INR 2,560.00 - AU A/c X6977 06-NOV-2026
        VIE-1111-222/256000-HEYGEN TECHNOLOGY
        Bal INR 44,815.79
        """
        XCTAssertEqual(Ingestor.ingest(heygenSMS, context: ctx, now: now).status, .merged)

        let all = try ctx.fetch(FetchDescriptor<Txn>())
        XCTAssertEqual(all.count, 2)
        let h = try XCTUnwrap(all.first { $0.vendor == "HeyGen" })
        XCTAssertEqual(h.amount, 2560)
        XCTAssertEqual(h.currency, "INR")
        XCTAssertEqual(h.foreignAmount, 29)
        XCTAssertTrue(h.hasSMS && h.hasEmail)
    }

    @MainActor
    func testSavedPayee() throws {
        let container = try ModelContainer(for: Txn.self, Payee.self, PlaceTags.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        ctx.insert(Payee(key: "RAHUL KUMAR", name: "Therapist", defaultTag: "health"))
        try ctx.save()
        let sms = """
        Dr INR 2,000.00 - AU A/c X6977 06-NOV-2026
        UPI/DR/617601830000/RAHUL KUMAR/YESB/9876543210@ybl
        Bal INR 40,000.00
        """
        Ingestor.ingest(sms, context: ctx, now: now)
        let t = try XCTUnwrap(ctx.fetch(FetchDescriptor<Txn>()).first)
        XCTAssertEqual(t.vendor, "Therapist")
        XCTAssertEqual(t.tags, ["health"])
    }
}
