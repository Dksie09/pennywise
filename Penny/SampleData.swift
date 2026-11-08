import Foundation
import SwiftData

/// Realistic made-up payments for trying the app out. Added and removed from Settings.
/// Each sample carries a marker in `hashes`, so removing them never touches real payments.
enum SampleData {
    static let marker = "penny-sample"

    static func isSample(_ t: Txn) -> Bool { t.hashes == [marker] }

    private struct Shop {
        let name: String
        let payee: String
        let range: ClosedRange<Int>
        let tag: String
        let weight: Int
    }

    private static let shops: [Shop] = [
        Shop(name: "Zepto", payee: "ZEPTO MARKETPLACE", range: 90...850, tag: "grocery", weight: 6),
        Shop(name: "Blinkit", payee: "BLINKIT COMMERCE", range: 60...600, tag: "grocery", weight: 4),
        Shop(name: "Swiggy", payee: "SWIGGY LIMITED", range: 180...720, tag: "food", weight: 6),
        Shop(name: "Zomato", payee: "ZOMATO LTD", range: 200...650, tag: "food", weight: 4),
        Shop(name: "Blue Tokai", payee: "BLUE TOKAI COFFEE", range: 220...480, tag: "coffee", weight: 3),
        Shop(name: "Uber", payee: "UBER INDIA SYSTEMS", range: 110...520, tag: "travel", weight: 5),
        Shop(name: "Rapido", payee: "RAPIDO BIKE TAXI", range: 40...160, tag: "travel", weight: 3),
        Shop(name: "Amazon", payee: "AMAZON PAY INDIA", range: 299...3499, tag: "shopping", weight: 2),
        Shop(name: "Chai stall", payee: "9876543210@YBL", range: 20...60, tag: "", weight: 4),
        Shop(name: "Apollo Pharmacy", payee: "APOLLO PHARMACY", range: 120...900, tag: "health", weight: 1),
    ]

    @MainActor static func add(to context: ModelContext, now: Date = Date()) {
        let cal = Calendar.current
        var rng = SeededRNG(seed: 42)
        let pool = shops.flatMap { Array(repeating: $0, count: $0.weight) }
        var balance = 84_250.0

        // ~2.5 months of everyday spending, oldest first so the running balance reads naturally.
        for back in stride(from: 75, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -back, to: cal.startOfDay(for: now)) else { continue }
            for _ in 0..<Int.random(in: 0...3, using: &rng) {
                let s = pool.randomElement(using: &rng)!
                let hour = Int.random(in: 8...22, using: &rng), minute = Int.random(in: 0...59, using: &rng)
                guard let date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day), date <= now else { continue }
                let amount = Double(Int.random(in: s.range, using: &rng))
                balance -= amount
                insert(context, date: date, amount: amount, shop: s.name, payee: s.payee, tag: s.tag, balance: balance, rng: &rng)
            }
        }

        // Monthly regulars on fixed days.
        for monthsBack in 0...2 {
            guard let month = cal.date(byAdding: .month, value: -monthsBack, to: now),
                  let start = cal.dateInterval(of: .month, for: month)?.start else { continue }
            func on(_ day: Int, _ hour: Int) -> Date? {
                cal.date(byAdding: DateComponents(day: day - 1, hour: hour), to: start).flatMap { $0 <= now ? $0 : nil }
            }
            if let d = on(3, 10) {
                insert(context, date: d, amount: 2_500, shop: "Therapist", payee: "DR MEERA NAIR", tag: "health", balance: nil, rng: &rng)
            }
            if let d = on(5, 9) {
                insert(context, date: d, amount: 1_999, shop: "Anthropic", payee: "ANTHROPIC* CLAUDE SU", tag: "work", balance: nil, rng: &rng, method: "Card")
            }
            if let d = on(7, 19) {
                insert(context, date: d, amount: 649, shop: "Netflix", payee: "NETFLIX COM", tag: "subscriptions", balance: nil, rng: &rng, method: "Card")
            }
            if let d = on(1, 11) {
                let t = insert(context, date: d, amount: 15_000, shop: "Savings account", payee: "SELF TRANSFER", tag: "", balance: nil, rng: &rng)
                t.type = .transfer
                t.note = "Moved to savings"
            }
        }

        // A refund and a gift with a note, a few days ago.
        if let d = cal.date(byAdding: .day, value: -2, to: now) {
            let t = insert(context, date: d, amount: 1_299, shop: "Amazon", payee: "AMAZON PAY INDIA", tag: "shopping", balance: nil, rng: &rng)
            t.type = .refund
            t.note = "Returned the shoes"
        }
        if let d = cal.date(byAdding: .day, value: -4, to: now) {
            let t = insert(context, date: d, amount: 1_850, shop: "Nykaa", payee: "NYKAA E RETAIL", tag: "gifts", balance: nil, rng: &rng)
            t.note = "Birthday gift for mum"
        }

        try? context.save()
    }

    @MainActor static func remove(from context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        for t in all where isSample(t) { context.delete(t) }
        try? context.save()
    }

    @discardableResult
    private static func insert(_ context: ModelContext, date: Date, amount: Double, shop: String, payee: String,
                               tag: String, balance: Double?, rng: inout SeededRNG, method: String = "UPI") -> Txn {
        let t = Txn(date: date, amount: amount, vendor: shop, rawPayee: payee, method: method)
        let ref = String(UInt64.random(in: 100_000_000_000...999_999_999_999, using: &rng))
        t.ref = ref
        t.account = "X6977"
        t.balance = balance
        t.hasSMS = true
        t.tags = tag.isEmpty ? [] : [tag]
        t.hashes = [marker]
        let when = date.formatted(.dateTime.day(.twoDigits).month(.abbreviated).year()).uppercased().replacingOccurrences(of: " ", with: "-")
        let money = amount.formatted(.number.precision(.fractionLength(2)))
        t.rawMessages = ["Dr INR \(money) - AU A/c X6977 \(when)\n\(method == "UPI" ? "UPI/DR/\(ref)/" : "")\(payee)"]
        context.insert(t)
        return t
    }
}

/// Small deterministic generator so the sample month looks the same every time.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
