import Foundation

/// Turns a bank SMS or a receipt email into structured data. Pure functions, no I/O.
struct Parsed: Equatable {
    enum Kind { case bank, receipt }
    var kind: Kind
    var amount: Double
    var currency: String
    var isCredit: Bool
    var date: Date
    var rawPayee: String
    var vendor: String
    var method: String
    var ref: String?
    var balance: Double?
    var account: String?
    var items: [LineItem] = []
}

enum Parser {
    static func parse(_ text: String, now: Date = Date()) -> Parsed? {
        parseBank(text, now: now) ?? parseReceipt(text, now: now)
    }

    // MARK: - Bank SMS

    static func parseBank(_ text: String, now: Date) -> Parsed? {
        // AU Bank style:
        // "Dr INR 139.00 - AU A/c X6977 06-NOV-2026 UPI/DR/617601834096/ZEPTO MARKETPLACE Bal INR 49,774.79"
        let au = #"\b(Dr|Cr)\.?\s+(?:INR|Rs\.?|₹)\s*([\d,]*\d(?:\.\d+)?)\s*-\s*(.*?)\s*A/c\s+([Xx*]*\d+)\s+(\d{1,2}-[A-Za-z]{3}-\d{2,4})"#
        if let m = RX.matchWithRange(au, text) {
            let (g, range) = m
            let rest = (text as NSString).substring(from: range.location + range.length)
            let descEnd = RX.matchWithRange(#"\bBal\b|Avl|Fraud\?"#, rest)?.1.location ?? (rest as NSString).length
            let desc = (rest as NSString).substring(to: descEnd)
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let d = describe(desc)
            let date = dashedDate(g[5]).map { dayDate($0, now: now) } ?? now
            return Parsed(
                kind: .bank,
                amount: num(g[2]) ?? 0,
                currency: "INR",
                isCredit: g[1].lowercased() == "cr",
                date: date,
                rawPayee: d.payee,
                vendor: normalizeVendor(d.payee),
                method: d.method,
                ref: d.ref,
                balance: balance(in: text),
                account: "\(g[3]) A/c \(g[4])".trimmingCharacters(in: .whitespaces)
            )
        }

        // Generic Indian bank SMS: "Rs.500.00 debited from A/c XX1234 on 06-11-26 to VPA abc@okaxis. UPI Ref 1234567"
        let lower = text.lowercased()
        let debit = lower.contains("debited") || lower.contains("spent") || lower.contains("sent")
        let credit = lower.contains("credited") || lower.contains("received")
        let looksBank = lower.contains("a/c") || lower.contains("acct") || lower.contains("account") || lower.contains("card")
        let isReceipt = lower.contains("receipt") || lower.contains("invoice")
        guard looksBank, debit || credit, !isReceipt, text.count < 600,
              let a = RX.match(#"(?:INR|Rs\.?|₹)\s*([\d,]*\d(?:\.\d+)?)"#, text),
              let amount = num(a[1]) else { return nil }

        var payee = ""
        if let v = RX.match(#"([\w.\-]+@[A-Za-z]+)"#, text) {
            payee = v[1]
        } else if let t = RX.match(#"\b(?:to|at|towards|info:?)\s+([A-Za-z0-9 .&*'\-]{2,40}?)(?:\s+on\b|\s+ref\b|\.\s|,|\s+UPI|\s+Avl|\s+via|$)"#, text, [.caseInsensitive, .anchorsMatchLines]) {
            payee = t[1].trimmingCharacters(in: .whitespaces)
        }
        if payee.isEmpty { payee = "Unknown" }
        let ref = RX.match(#"(?:UPI\s*Ref(?:\s*No)?|Ref(?:\s*No)?|RRN|Txn\s*ID)[:.\s#]*([0-9]{6,})"#, text)?[1]
        let method = lower.contains("upi") ? "UPI" : (lower.contains("card") ? "Card" : "Bank")

        return Parsed(
            kind: .bank,
            amount: amount,
            currency: "INR",
            isCredit: credit && !debit,
            date: now,
            rawPayee: payee,
            vendor: normalizeVendor(payee),
            method: method,
            ref: ref,
            balance: balance(in: text),
            account: RX.match(#"A/c\s*(?:no\.?)?\s*([Xx*]*\d{3,})"#, text).map { "A/c \($0[1])" }
        )
    }

    /// "UPI/DR/617601834096/ZEPTO MARKETPLACE" or "VIE-6754-356/239900-ANTHROPIC* CLAUDE SU"
    static func describe(_ desc: String) -> (method: String, ref: String?, payee: String) {
        let parts = desc.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = parts.first else { return ("Bank", nil, "Unknown") }
        let head = first.uppercased()

        if head == "UPI" || head == "IMPS" || head == "NEFT" || head == "RTGS" {
            let ref = parts.first { $0.count >= 6 && $0.allSatisfy(\.isNumber) }
            let skip: Set<String> = ["UPI", "IMPS", "NEFT", "RTGS", "DR", "CR", "P2P", "P2M"]
            let rest = parts.dropFirst().filter { !skip.contains($0.uppercased()) && $0 != ref && !$0.isEmpty }
            let name = rest.first { !$0.contains("@") } ?? rest.first ?? "Unknown"
            return (head == "UPI" ? "UPI" : head, ref, name)
        }
        if parts.count > 1 {
            // Card: "<ref>/<amount>-<MERCHANT>"
            var last = parts.last ?? ""
            if let r = last.range(of: #"^\d+-"#, options: .regularExpression) { last.removeSubrange(r) }
            return ("Card", parts[0], last.isEmpty ? "Unknown" : last)
        }
        return ("Bank", nil, desc.isEmpty ? "Unknown" : desc)
    }

    static func balance(in text: String) -> Double? {
        RX.match(#"(?:Avl\.?\s*Bal|Bal(?:ance)?)\s*[:.]?\s*(?:INR|Rs\.?|₹)?\s*([\d,]*\d(?:\.\d+)?)"#, text).flatMap { num($0[1]) }
    }

    // MARK: - Receipt email

    static func parseReceipt(_ text: String, now: Date) -> Parsed? {
        let lower = text.lowercased()
        let signals = ["receipt", "invoice", "order confirmation", "your order", "payment confirmation", "payment successful"]
        guard signals.contains(where: { lower.contains($0) }) else { return nil }

        // Amount: prefer the largest "Total"-like line, else first currency amount.
        let money = #"(₹|\$|€|£|INR|USD|EUR|GBP|Rs\.?)\s?([\d,]*\d(?:\.\d{1,2})?)"#
        let totals = RX.matches(#"\b(?:grand total|order total|total amount|total|amount paid|amount charged|you paid)\b\s*[:\-]?\s*"# + money, text)
        let best = totals.compactMap { g -> (String, Double)? in num(g[2]).map { (g[1], $0) } }.max { $0.1 < $1.1 }
        let any = RX.match(money, text).flatMap { g in num(g[2]).map { (g[1], $0) } }
        guard let picked = best ?? any, picked.1 > 0 else { return nil }
        let (sym, amount) = picked

        var vendorRaw = RX.match(#"receipt from\s+(.+?)(?:\s*#|\.(?:\s|$)|$)"#, text, [.caseInsensitive, .anchorsMatchLines])?[1]
        if vendorRaw == nil, lower.contains("apple") && (lower.contains("apple account") || lower.contains("apple id") || lower.contains("apple.com")) {
            vendorRaw = "Apple"
        }
        if vendorRaw == nil {
            vendorRaw = RX.match(#"(?:order|invoice|payment)\s+(?:from|with|to)\s+([A-Z][\w&.' ]{1,40}?)(?:\.|,|\n|$| for| has| is)"#, text, [.anchorsMatchLines])?[1]
        }
        let raw = (vendorRaw ?? "Receipt").trimmingCharacters(in: .whitespacesAndNewlines)

        let ref = RX.match(#"(?:receipt|invoice|order)\s*(?:id|no\.?|number)?\s*[:#]\s*([A-Z0-9][\w-]{3,})"#, text)?[1]
            ?? RX.match(#"#\s?([A-Z0-9][\w-]{3,})"#, text)?[1]

        return Parsed(
            kind: .receipt,
            amount: amount,
            currency: currency(sym),
            isCredit: ["your refund", "refund of", "refund receipt", "has been refunded"].contains(where: { lower.contains($0) }),
            date: textDate(text).map { dayDate($0, now: now) } ?? now,
            rawPayee: raw,
            vendor: normalizeVendor(raw),
            method: "Email",
            ref: ref,
            items: items(in: text)
        )
    }

    /// Best-effort line items: "AirPods Case   ₹1,499.00"
    static func items(in text: String) -> [LineItem] {
        let skip = ["total", "tax", "gst", "discount", "paid", "amount", "balance", "billed", "refund", "fee", "charge"]
        return text.components(separatedBy: .newlines).compactMap { line in
            let l = line.trimmingCharacters(in: .whitespaces)
            let ll = l.lowercased()
            guard !skip.contains(where: { ll.contains($0) }),
                  let g = RX.match(#"^(.{2,80}?)\s+(?:₹|\$|€|£|INR|USD|Rs\.?)\s?([\d,]*\d\.\d{2})$"#, l),
                  let p = num(g[2]) else { return nil }
            return LineItem(name: g[1].trimmingCharacters(in: .whitespaces), price: p)
        }
    }

    // MARK: - Vendor names

    static let known: [(String, String)] = [
        ("INSTAMART", "Swiggy Instamart"), ("SWIGGY", "Swiggy"), ("ZOMATO", "Zomato"), ("ZEPTO", "Zepto"),
        ("BLINKIT", "Blinkit"), ("GROFERS", "Blinkit"), ("BIGBASKET", "BigBasket"),
        ("ANTHROPIC", "Anthropic"), ("CLAUDE", "Anthropic"), ("OPENAI", "OpenAI"), ("CHATGPT", "OpenAI"),
        ("APPLE", "Apple"), ("ITUNES", "Apple"), ("HEYGEN", "HeyGen"), ("GOOGLE", "Google"), ("YOUTUBE", "YouTube"),
        ("NETFLIX", "Netflix"), ("SPOTIFY", "Spotify"), ("HOTSTAR", "Hotstar"), ("NOTION", "Notion"),
        ("AMAZON", "Amazon"), ("AMZN", "Amazon"), ("FLIPKART", "Flipkart"), ("MYNTRA", "Myntra"), ("NYKAA", "Nykaa"),
        ("UBER", "Uber"), ("OLA", "Ola"), ("RAPIDO", "Rapido"), ("IRCTC", "IRCTC"),
        ("JIO", "Jio"), ("AIRTEL", "Airtel"), ("STARBUCKS", "Starbucks"),
    ]

    static func normalizeVendor(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown" }
        if trimmed.contains("@") || trimmed.allSatisfy(\.isNumber) { return trimmed.lowercased() }
        let tokens = trimmed.uppercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        for (key, name) in known where tokens.contains(where: { $0 == key || (key.count >= 5 && $0.hasPrefix(key)) }) {
            return name
        }
        let legal: Set<String> = ["PVT", "PRIVATE", "LTD", "LIMITED", "INC", "LLC", "LLP"]
        let words = trimmed.replacingOccurrences(of: "*", with: " ")
            .split(separator: " ")
            .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && !legal.contains($0.uppercased()) }
        let name = words.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
        return name.isEmpty ? "Unknown" : name
    }

    static func vendorKey(_ s: String) -> String {
        String(s.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    static func vendorsMatch(_ a: String, _ b: String) -> Bool {
        let ka = vendorKey(a), kb = vendorKey(b)
        guard !ka.isEmpty, !kb.isEmpty else { return false }
        if ka == kb { return true }
        if min(ka.count, kb.count) >= 4, ka.contains(kb) || kb.contains(ka) { return true }
        let ta = Set(a.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 4 })
        let tb = Set(b.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 4 })
        return !ta.isDisjoint(with: tb)
    }

    // MARK: - Helpers

    static func num(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: "")) }

    static func currency(_ sym: String) -> String {
        switch sym.uppercased() {
        case "$", "USD": return "USD"
        case "€", "EUR": return "EUR"
        case "£", "GBP": return "GBP"
        default: return "INR"
        }
    }

    static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    static func month(_ name: String) -> Int? {
        guard name.count >= 3 else { return nil }
        let p = String(name.lowercased().prefix(3))
        return months.firstIndex(of: p).map { $0 + 1 }
    }

    /// "06-NOV-2026"
    static func dashedDate(_ s: String) -> DateComponents? {
        let p = s.split(separator: "-").map(String.init)
        guard p.count == 3, let d = Int(p[0]), let m = month(p[1]), var y = Int(p[2]) else { return nil }
        if y < 100 { y += 2000 }
        return DateComponents(year: y, month: m, day: d)
    }

    /// "June 15, 2026" or "15 Jun 2026"
    static func textDate(_ text: String) -> DateComponents? {
        for g in RX.matches(#"\b([A-Za-z]{3,9})\.?\s+(\d{1,2}),?\s+(\d{4})\b"#, text) {
            if let m = month(g[1]), let d = Int(g[2]), let y = Int(g[3]) { return DateComponents(year: y, month: m, day: d) }
        }
        for g in RX.matches(#"\b(\d{1,2})\s+([A-Za-z]{3,9})\.?,?\s+(\d{4})\b"#, text) {
            if let m = month(g[2]), let d = Int(g[1]), let y = Int(g[3]) { return DateComponents(year: y, month: m, day: d) }
        }
        return nil
    }

    /// Use the exact current time if the message is from today, otherwise noon on that day.
    static func dayDate(_ c: DateComponents, now: Date) -> Date {
        let cal = Calendar.current
        var c = c
        c.hour = 12
        guard let d = cal.date(from: c) else { return now }
        return cal.isDate(d, inSameDayAs: now) ? now : d
    }
}

enum RX {
    static func matchWithRange(_ pattern: String, _ s: String, _ opts: NSRegularExpression.Options = [.caseInsensitive]) -> ([String], NSRange)? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (groups(m, ns), m.range)
    }

    static func match(_ pattern: String, _ s: String, _ opts: NSRegularExpression.Options = [.caseInsensitive]) -> [String]? {
        matchWithRange(pattern, s, opts)?.0
    }

    static func matches(_ pattern: String, _ s: String, _ opts: NSRegularExpression.Options = [.caseInsensitive]) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { groups($0, ns) }
    }

    private static func groups(_ m: NSTextCheckingResult, _ ns: NSString) -> [String] {
        (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }
}
