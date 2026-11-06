import Foundation
import SwiftData
import CryptoKit

/// Takes raw message text, parses it, and either adds a new payment, merges it
/// into an existing one (SMS <-> receipt), or ignores it as a duplicate.
@MainActor
enum Ingestor {
    struct Result {
        enum Status { case added, merged, duplicate, unrecognized }
        var status: Status
        var summary: String
    }

    static let matchWindow: TimeInterval = 4 * 86_400

    @discardableResult
    static func ingest(_ text: String, context: ModelContext, now: Date = Date()) -> Result {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return Result(status: .unrecognized, summary: "Empty message") }
        let hash = fingerprint(text)
        let all = (try? context.fetch(FetchDescriptor<Txn>())) ?? []

        // 1. Exact same message seen before (e.g. automation fired twice).
        if all.contains(where: { $0.hashes.contains(hash) }) {
            return Result(status: .duplicate, summary: "Already logged")
        }
        guard let p = Parser.parse(text, now: now) else {
            return Result(status: .unrecognized, summary: "Not an expense message")
        }
        let near = all.filter { abs($0.date.timeIntervalSince(p.date)) <= matchWindow }

        switch p.kind {
        case .bank:
            // 2. Same debit reported twice (two SMS, different wording).
            if let dup = near.first(where: { t in
                t.hasSMS && t.isCredit == p.isCredit && abs(t.amount - p.amount) < 0.01 &&
                ((p.ref != nil && t.ref == p.ref) || (p.balance != nil && t.balance == p.balance))
            }) {
                dup.hashes.append(hash)
                save(context)
                return Result(status: .duplicate, summary: "Duplicate SMS for \(dup.vendor)")
            }
            // 3. A receipt email for this payment already arrived -> merge.
            if !p.isCredit, let r = bestMatch(near.filter { $0.hasEmail && !$0.hasSMS && !$0.isCredit }, parsed: p) {
                if r.currency != "INR" {
                    r.foreignAmount = r.amount
                    r.foreignCurrency = r.currency
                }
                r.amount = p.amount
                r.currency = "INR"
                r.date = p.date
                applyBankFields(r, p)
                applyPayee(r, context: context)
                r.rawMessages.append(text)
                r.hashes.append(hash)
                save(context)
                return Result(status: .merged, summary: "Matched SMS to \(r.vendor) receipt")
            }
            let t = Txn(date: p.date, amount: p.amount, vendor: p.vendor, rawPayee: p.rawPayee, method: p.method)
            t.isCredit = p.isCredit
            applyBankFields(t, p)
            applyPayee(t, context: context)
            t.rawMessages = [text]
            t.hashes = [hash]
            context.insert(t)
            save(context)
            return Result(status: .added, summary: "\(p.isCredit ? "Received" : "Logged") \(Fmt.money(p.amount)) · \(t.vendor)")

        case .receipt:
            // 2. Same receipt twice.
            if let dup = near.first(where: { t in
                t.hasEmail && ((p.ref != nil && t.receiptRef == p.ref) ||
                    (Parser.vendorsMatch(t.vendor, p.vendor) && Calendar.current.isDate(t.date, inSameDayAs: p.date) &&
                     (abs(t.amount - p.amount) < 0.01 || abs((t.foreignAmount ?? -1) - p.amount) < 0.01)))
            }) {
                dup.hashes.append(hash)
                save(context)
                return Result(status: .duplicate, summary: "Duplicate receipt for \(dup.vendor)")
            }
            // 3. Bank SMS for this payment already logged -> attach receipt details.
            if !p.isCredit, let b = bestMatch(near.filter { $0.hasSMS && !$0.hasEmail && !$0.isCredit }, parsed: p) {
                b.hasEmail = true
                b.receiptRef = p.ref
                if !p.items.isEmpty { b.items = p.items }
                if p.currency != "INR" {
                    b.foreignAmount = p.amount
                    b.foreignCurrency = p.currency
                }
                if b.vendor == Parser.normalizeVendor(b.rawPayee), Parser.known.contains(where: { $0.1 == p.vendor }) {
                    b.vendor = p.vendor
                }
                b.rawMessages.append(text)
                b.hashes.append(hash)
                save(context)
                return Result(status: .merged, summary: "Attached receipt to \(b.vendor) payment")
            }
            let t = Txn(date: p.date, amount: p.amount, currency: p.currency, vendor: p.vendor, rawPayee: p.rawPayee, method: "Email")
            t.isCredit = p.isCredit
            t.hasEmail = true
            t.receiptRef = p.ref
            t.items = p.items
            t.rawMessages = [text]
            t.hashes = [hash]
            context.insert(t)
            save(context)
            return Result(status: .added, summary: "Logged \(Fmt.money(p.amount, p.currency)) · \(t.vendor) (receipt)")
        }
    }

    /// Pick the candidate that best matches: same vendor and amount > same vendor > same INR amount; then closest in time.
    static func bestMatch(_ candidates: [Txn], parsed p: Parsed) -> Txn? {
        func score(_ t: Txn) -> Int {
            let vendor = Parser.vendorsMatch(t.vendor, p.vendor) || Parser.vendorsMatch(t.rawPayee, p.rawPayee)
                || Parser.vendorsMatch(t.rawPayee, p.vendor) || Parser.vendorsMatch(t.vendor, p.rawPayee)
            let sameCurrency = t.currency == p.currency
            let amount = sameCurrency && abs(t.amount - p.amount) < 1
            if vendor && amount { return 3 }
            if vendor { return 2 }
            if amount { return 1 }
            return 0
        }
        return candidates
            .map { ($0, score($0)) }
            .filter { $0.1 > 0 }
            .max { a, b in
                a.1 != b.1 ? a.1 < b.1 : abs(a.0.date.timeIntervalSince(p.date)) > abs(b.0.date.timeIntervalSince(p.date))
            }?.0
    }

    private static func applyBankFields(_ t: Txn, _ p: Parsed) {
        t.hasSMS = true
        t.method = p.method
        t.ref = p.ref
        t.balance = p.balance
        t.account = p.account
        t.rawPayee = p.rawPayee   // the bank's payee string is what saved names are keyed on
    }

    private static func applyPayee(_ t: Txn, context: ModelContext) {
        let key = Payee.key(for: t.rawPayee)
        let d = FetchDescriptor<Payee>(predicate: #Predicate { $0.key == key })
        guard let payee = try? context.fetch(d).first else { return }
        t.vendor = payee.name
        if !payee.defaultTag.isEmpty, !t.tags.contains(payee.defaultTag) { t.tags.append(payee.defaultTag) }
    }

    static func fingerprint(_ text: String) -> String {
        let normalized = text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func save(_ context: ModelContext) { try? context.save() }
}
