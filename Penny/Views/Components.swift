import SwiftUI

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

    /// Compact for calendar cells: 850, 1.2k, 12k
    static func short(_ v: Double) -> String {
        if v >= 10_000 { return "\(Int((v / 1000).rounded()))k" }
        if v >= 1_000 { return String(format: "%.1fk", v / 1000) }
        return "\(Int(v.rounded()))"
    }

    static func monthTitle(_ d: Date) -> String { d.formatted(.dateTime.month(.wide).year()) }
}

struct MonthSwitcher: View {
    @Binding var month: Date

    var body: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(Fmt.monthTitle(month)).font(.headline)
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                .disabled(Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month))
        }
        .buttonStyle(.borderless)
    }

    private func shift(_ n: Int) {
        month = Calendar.current.date(byAdding: .month, value: n, to: month) ?? month
    }
}

struct VendorAvatar: View {
    let name: String

    var body: some View {
        let seed = name.lowercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let hue = Double(seed % 360) / 360
        Text(String(name.prefix(1)).uppercased())
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color(hue: hue, saturation: 0.45, brightness: 0.75)))
    }
}

struct TxnRow: View {
    let txn: Txn

    var body: some View {
        HStack(spacing: 12) {
            VendorAvatar(name: txn.vendor)
            VStack(alignment: .leading, spacing: 2) {
                Text(txn.vendor).font(.body.weight(.medium)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text((txn.isCredit ? "+" : "") + Fmt.money(txn.amount, txn.currency))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(txn.isCredit ? .green : (txn.excluded ? .secondary : .primary))
                    .strikethrough(txn.excluded)
                HStack(spacing: 4) {
                    if txn.hasSMS { Image(systemName: "message.fill") }
                    if txn.hasEmail { Image(systemName: "envelope.fill") }
                    if txn.foreignAmount != nil, let c = txn.foreignCurrency {
                        Text(Fmt.money(txn.foreignAmount ?? 0, c))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts: [String] = []
        if !txn.tags.isEmpty { parts.append(txn.tags.map { "#\($0)" }.joined(separator: " ")) }
        if !txn.note.isEmpty { parts.append(txn.note) }
        if parts.isEmpty { parts.append(txn.method) }
        return parts.joined(separator: " · ")
    }
}

struct TagChip: View {
    let text: String
    var selected = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(selected ? "#\(text) ✕" : "+ \(text)")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}
