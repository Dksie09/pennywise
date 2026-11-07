import SwiftUI
import SwiftData

enum Fmt {
    static func money(_ v: Double, _ currency: String = "INR") -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.locale = Locale(identifier: currency == "INR" ? "en_IN" : "en_US")
        f.maximumFractionDigits = v.rounded() == v ? 0 : 2
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }

    /// "₹12,392.50" -> ("₹", "12,392", ".50")
    static func parts(_ s: String) -> (symbol: String, whole: String, fraction: String) {
        guard let i = s.firstIndex(where: \.isNumber) else { return ("", s, "") }
        let symbol = s[..<i].trimmingCharacters(in: .whitespaces)
        let rest = s[i...]
        guard let dot = rest.lastIndex(of: ".") else { return (symbol, String(rest), "") }
        return (symbol, String(rest[..<dot]), String(rest[dot...]))
    }

    /// Compact for calendar cells: 850, 1.2k, 12k
    static func short(_ v: Double) -> String {
        if v >= 10_000 { return "\(Int((v / 1000).rounded()))k" }
        if v >= 1_000 { return String(format: "%.1fk", v / 1000) }
        return "\(Int(v.rounded()))"
    }

    static func monthTitle(_ d: Date) -> String { d.formatted(.dateTime.month(.wide).year()) }

    /// "November", or "November 2025" when it isn't this year.
    static func monthName(_ d: Date) -> String {
        Calendar.current.isDate(d, equalTo: Date(), toGranularity: .year)
            ? d.formatted(.dateTime.month(.wide)) : monthTitle(d)
    }

    static func dayTitle(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func payments(_ n: Int) -> String { "\(n) payment\(n == 1 ? "" : "s")" }
}

/// ‹ › buttons that move a month back or forward. Can't go past this month.
struct MonthStepper: View {
    @Binding var month: Date

    var body: some View {
        HStack(spacing: 6) {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous month")
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next month")
                .disabled(Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month))
        }
        .buttonStyle(CircleButtonStyle(size: 32, background: Theme.fill))
        .sensoryFeedback(.selection, trigger: month)
    }

    private func shift(_ n: Int) {
        withAnimation(.snappy) {
            month = Calendar.current.date(byAdding: .month, value: n, to: month) ?? month
        }
    }
}

struct TxnRow: View {
    let txn: Txn

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(txn.vendor).font(.body.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(1)
                .layoutPriority(1)
            if let subtitle {
                Text(subtitle).font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(value: txn.amount, currency: txn.currency, size: 16,
                           sign: txn.isCredit ? "+" : "",
                           color: txn.isCredit ? Theme.positive : (txn.excluded ? Theme.muted : Theme.ink))
                    .strikethrough(txn.excluded)
                if let f = txn.foreignAmount, let c = txn.foreignCurrency {
                    Text(Fmt.money(f, c)).font(.footnote).foregroundStyle(Theme.muted)
                } else if txn.excluded {
                    Text("Not counted").font(.footnote).foregroundStyle(Theme.muted)
                }
            }
        }
        .contentShape(Rectangle())
    }

    /// Tags and note, e.g. "grocery, home · weekly shop". Nothing when there are neither.
    private var subtitle: String? {
        let parts = [txn.tags.joined(separator: ", "), txn.note].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Payment rows with hairlines between them. Tap opens the payment; long-press to delete.
struct TxnRows: View {
    let txns: [Txn]
    @Environment(\.modelContext) private var context

    var body: some View {
        ForEach(Array(txns.enumerated()), id: \.element.id) { i, t in
            if i > 0 { Divider().overlay(Theme.line) }
            NavigationLink(value: t) {
                TxnRow(txn: t).padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Delete payment", systemImage: "trash", role: .destructive) {
                    withAnimation { context.delete(t) }
                }
            }
        }
    }
}

struct TxnListCard: View {
    let txns: [Txn]

    var body: some View {
        VStack(spacing: 0) { TxnRows(txns: txns) }
            .card(padding: 16)
            .padding(.vertical, -4)
    }
}

struct TagChip: View {
    let text: String
    var selected = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(text)
                Image(systemName: selected ? "xmark" : "plus").font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(selected ? Theme.card : Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(selected ? Theme.ink : Theme.fill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selected ? "Remove tag \(text)" : "Add tag \(text)")
    }
}
