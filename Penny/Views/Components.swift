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

/// Swipe left for the next month, right for the previous one (never past this month).
/// Only clearly sideways drags count, so scrolling up and down is unaffected.
struct MonthSwipe: ViewModifier {
    @Binding var month: Date

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { g in
                        let dx = g.translation.width, dy = g.translation.height
                        guard abs(dx) > 60, abs(dx) > abs(dy) * 1.5 else { return }
                        let step = dx < 0 ? 1 : -1
                        let cal = Calendar.current
                        if step > 0 && cal.isDate(month, equalTo: Date(), toGranularity: .month) { return }
                        withAnimation(.snappy) { month = cal.date(byAdding: .month, value: step, to: month) ?? month }
                    }
            )
    }
}

extension View {
    func monthSwipe(_ month: Binding<Date>) -> some View { modifier(MonthSwipe(month: month)) }
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(txn.vendor).font(.body.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(value: txn.amount, currency: txn.currency, size: 16,
                           sign: txn.isCredit ? "+" : "",
                           color: txn.isCredit ? Theme.positive : (txn.excluded ? Theme.muted : Theme.ink))
                    .strikethrough(txn.excluded)
                if let f = txn.foreignAmount, let c = txn.foreignCurrency {
                    Text(Fmt.money(f, c)).font(.footnote).foregroundStyle(Theme.muted)
                } else if let label = typeLabel {
                    Text(label).font(.footnote).foregroundStyle(Theme.muted)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var typeLabel: String? {
        switch txn.type {
        case .expense, .received: nil
        case .refund: "Refund"
        case .transfer: "Transfer"
        case .excluded: "Not counted"
        }
    }

    /// Tags and note, e.g. "grocery, home · weekly shop". Nothing when there are neither.
    private var subtitle: String? {
        let parts = [txn.tags.joined(separator: ", "), txn.note].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Payment rows with hairlines between them.
/// Tap or swipe right to open a payment in a drawer; swipe left for Delete (all the way to delete at once).
struct TxnRows: View {
    let txns: [Txn]
    @Environment(\.modelContext) private var context
    @Environment(PageRouter.self) private var router

    var body: some View {
        ForEach(Array(txns.enumerated()), id: \.element.id) { i, t in
            if i > 0 { Divider().overlay(Theme.line).padding(.horizontal, 18) }
            SwipeRow(onOpen: { router.openTxn = t }, onDelete: { delete(t) }) {
                TxnRow(txn: t).padding(.vertical, 12).padding(.horizontal, 18)
            }
            .contextMenu {
                Button("Open", systemImage: "arrow.up.left.and.arrow.down.right") { router.openTxn = t }
                Button("Delete payment", systemImage: "trash", role: .destructive) { delete(t) }
            }
        }
    }

    private func delete(_ t: Txn) {
        withAnimation(.snappy) { context.delete(t) }
        try? context.save()
    }
}

struct TxnListCard: View {
    let txns: [Txn]

    var body: some View {
        VStack(spacing: 0) { TxnRows(txns: txns) }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Theme.shadow.opacity(0.05), radius: 14, y: 6)
    }
}

/// A row you can swipe: right reveals "Open", left reveals "Delete".
struct SwipeRow<Content: View>: View {
    let onOpen: () -> Void
    let onDelete: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    @State private var settled: CGFloat = 0          // 0, or -reveal while Delete is showing
    @State private var horizontal: Bool?             // decided by the first movement of each drag
    @State private var armed = false                 // past a threshold; used for the haptic tick

    private let reveal: CGFloat = 88
    private let fullSwipe: CGFloat = 200

    var body: some View {
        content
            .background(Theme.card)
            .offset(x: offset)
            .contentShape(Rectangle())
            .onTapGesture {
                if settled != 0 { close() } else { onOpen() }
            }
            // Actions sit behind the row and only take the width the row has slid by,
            // so the row keeps its own height.
            .background {
                HStack(spacing: 0) {
                    if offset > 0 {
                        action("Open", "arrow.up.left.and.arrow.down.right", Theme.ink).frame(width: offset)
                    }
                    Spacer(minLength: 0)
                    if offset < 0 {
                        Button { onDelete() } label: {
                            action("Delete", "trash", Color(hex: 0xE5484D))
                        }
                        .buttonStyle(.plain)
                        .frame(width: -offset)
                    }
                }
            }
            .clipped()
        .simultaneousGesture(drag)
        .sensoryFeedback(.impact(weight: .light), trigger: armed) { _, new in new }
        .accessibilityAction(named: "Open") { onOpen() }
        .accessibilityAction(named: "Delete") { onDelete() }
    }

    private func action(_ title: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold))
            Text(title).font(.caption.weight(.medium))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { g in
                if horizontal == nil { horizontal = abs(g.translation.width) > abs(g.translation.height) * 1.2 }
                guard horizontal == true else { return }
                var x = settled + g.translation.width
                if x > reveal { x = reveal + (x - reveal) * 0.35 }   // a little resistance past "Open"
                offset = x
                armed = x > reveal * 0.9 || x < -fullSwipe
            }
            .onEnded { g in
                defer { horizontal = nil; armed = false }
                guard horizontal == true else { return }
                let x = settled + g.translation.width
                if x > reveal * 0.9 {
                    close()
                    onOpen()
                } else if x < -fullSwipe {
                    withAnimation(.snappy) { offset = -600 }
                    onDelete()
                } else if x < -reveal / 2 {
                    withAnimation(.snappy) { offset = -reveal; settled = -reveal }
                } else {
                    close()
                }
            }
    }

    private func close() {
        withAnimation(.snappy) { offset = 0; settled = 0 }
    }
}

/// Empty states: sleeping Penny with a short line, e.g. "Nothing logged in October".
struct NappingPenny: View {
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 0) {
            PennyAnimation(clip: .sleep, height: 64, loops: true)
            Text(title).font(Theme.serif(22)).foregroundStyle(Theme.ink).padding(.top, 10)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center).padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .card(padding: 22)
        .accessibilityElement(children: .combine)
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
