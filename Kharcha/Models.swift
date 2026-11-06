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

enum Store {
    @MainActor static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Txn.self, Payee.self)
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

extension Txn {
    func inr(usdRate: Double) -> Double { Rates.toINR(amount, currency, usdRate: usdRate) }
    var countsAsSpend: Bool { !isCredit && !excluded }
}
