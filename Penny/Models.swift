import Foundation
import SwiftData

struct LineItem: Codable, Hashable {
    var name: String
    var price: Double
}

/// One real-world payment. A bank SMS and a receipt email for the same payment
/// are merged into a single Txn (hasSMS + hasEmail), so nothing is counted twice.
@Model
final class Txn {
    var id: UUID = UUID()
    var date: Date = Date()
    var amount: Double = 0
    var currency: String = "INR"
    var isCredit: Bool = false          // money in (refund, received)
    var excluded: Bool = false          // e.g. transfer to your own account
    var kind: String = ""               // TxnType raw value; empty for payments logged before types existed
    var rawPayee: String = ""           // exactly as the bank shows it, e.g. "ZEPTO MARKETPLACE"
    var vendor: String = ""             // friendly name shown in the app
    var method: String = ""             // UPI / Card / Email / Manual
    var ref: String?
    var balance: Double?
    var account: String?
    var hasSMS: Bool = false
    var hasEmail: Bool = false
    var receiptRef: String?
    var foreignAmount: Double?          // e.g. $29 when the bank charged ₹2,560
    var foreignCurrency: String?
    var note: String = ""
    var tags: [String] = []
    var items: [LineItem] = []
    var rawMessages: [String] = []
    var hashes: [String] = []

    init(date: Date, amount: Double, currency: String = "INR", vendor: String, rawPayee: String = "", method: String) {
        self.date = date
        self.amount = amount
        self.currency = currency
        self.vendor = vendor
        self.rawPayee = rawPayee
        self.method = method
    }
}

/// A name you saved for a payee, e.g. "9876543210@ybl" -> "Therapist".
@Model
final class Payee {
    @Attribute(.unique) var key: String
    var name: String
    /// Older single auto-tag. Superseded by `PlaceTags`; still used as a fallback for a place
    /// with no remembered tags yet, so nothing set up before keeps working.
    var defaultTag: String

    init(key: String, name: String, defaultTag: String = "") {
        self.key = key
        self.name = name
        self.defaultTag = defaultTag
    }

    static func key(for rawPayee: String) -> String {
        rawPayee.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The tags last given to a place ("Zepto" → grocery, food), applied to its new payments.
@Model
final class PlaceTags {
    @Attribute(.unique) var key: String
    var tags: [String] = []

    init(key: String, tags: [String]) {
        self.key = key
        self.tags = tags
    }

    /// Places are matched by the name Penny shows, so bank SMS, receipts and hand-added
    /// payments to the same place share one memory.
    static func key(for vendor: String) -> String {
        vendor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Remembers each place's tags and puts them on its new payments ("Remember tags for each place",
/// on by default). The latest tags you choose for a place are the ones remembered.
enum TagMemory {
    static let settingKey = "rememberPlaceTags"

    static var isOn: Bool { UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true }

    static func tags(for vendor: String, context: ModelContext) -> [String]? {
        let key = PlaceTags.key(for: vendor)
        guard !key.isEmpty else { return nil }
        let d = FetchDescriptor<PlaceTags>(predicate: #Predicate { $0.key == key })
        return (try? context.fetch(d).first)?.tags
    }

    /// Call when you choose a payment's tags (adding by hand, or saving an edit).
    static func remember(_ t: Txn, context: ModelContext) {
        guard isOn else { return }
        let key = PlaceTags.key(for: t.vendor)
        guard !key.isEmpty else { return }
        let d = FetchDescriptor<PlaceTags>(predicate: #Predicate { $0.key == key })
        if let memory = try? context.fetch(d).first {
            memory.tags = t.tags
        } else {
            context.insert(PlaceTags(key: key, tags: t.tags))
        }
    }

    /// For a new payment that arrived on its own (bank SMS, receipt): give it its place's tags.
    static func apply(to t: Txn, context: ModelContext) {
        guard isOn, t.tags.isEmpty, let tags = tags(for: t.vendor, context: context), !tags.isEmpty else { return }
        t.tags = tags
    }

    /// One-off: give past payments with no tags their place's remembered tags.
    /// Payments you've already tagged are left as they are. Returns how many were tagged.
    @discardableResult
    static func applyToPast(context: ModelContext) -> Int {
        let memories = (try? context.fetch(FetchDescriptor<PlaceTags>())) ?? []
        let byKey = Dictionary(memories.map { ($0.key, $0.tags) }, uniquingKeysWith: { a, _ in a })
        let txns = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
        var n = 0
        for t in txns where t.tags.isEmpty {
            if let tags = byKey[PlaceTags.key(for: t.vendor)], !tags.isEmpty {
                t.tags = tags
                n += 1
            }
        }
        try? context.save()
        return n
    }
}

enum Store {
    @MainActor static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Txn.self, Payee.self, PlaceTags.self)
        } catch {
            fatalError("Could not open database: \(error)")
        }
    }()
}

enum Rates {
    /// Rough conversion for receipts in foreign currency that never matched a bank debit.
    static func toINR(_ amount: Double, _ currency: String, usdRate: Double) -> Double {
        switch currency {
        case "INR": return amount
        case "USD": return amount * usdRate
        case "EUR": return amount * usdRate * 1.08
        case "GBP": return amount * usdRate * 1.27
        default: return amount * usdRate
        }
    }
}

/// What kind of payment this is. Decides whether and how it counts toward "spent".
enum TxnType: String, CaseIterable, Identifiable {
    case expense, refund, received, transfer, excluded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: "Expense"
        case .refund: "Refund"
        case .received: "Money received"
        case .transfer: "Transfer"
        case .excluded: "Excluded"
        }
    }

    var hint: String {
        switch self {
        case .expense: "Counts toward what you spent"
        case .refund: "Money back for something you bought. Lowers what you spent"
        case .received: "Salary, or money someone sent you. Not part of spending"
        case .transfer: "Between your own accounts, or into savings. Not counted"
        case .excluded: "Leave this out of all totals"
        }
    }
}

extension Txn {
    func inr(usdRate: Double) -> Double { Rates.toINR(amount, currency, usdRate: usdRate) }

    /// Stored in `kind`, and mirrored into `isCredit` / `excluded` so older code and CSV export stay correct.
    var type: TxnType {
        get {
            if let t = TxnType(rawValue: kind) { return t }
            return excluded ? .excluded : (isCredit ? .received : .expense)
        }
        set {
            kind = newValue.rawValue
            switch newValue {
            case .expense: isCredit = false; excluded = false
            case .refund, .received: isCredit = true; excluded = false
            case .transfer, .excluded: excluded = true
            }
        }
    }

    /// Expenses and refunds both affect what you spent.
    var countsAsSpend: Bool { type == .expense || type == .refund }

    /// What this payment adds to "spent": expenses add, refunds take away, everything else is ignored.
    func spend(usdRate: Double) -> Double {
        switch type {
        case .expense: inr(usdRate: usdRate)
        case .refund: -inr(usdRate: usdRate)
        default: 0
        }
    }
}
