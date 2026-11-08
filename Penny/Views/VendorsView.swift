import SwiftUI
import SwiftData

/// Where the month's money went, by place or by tag.
struct VendorsView: View {
    @Binding var month: Date
    @Query(sort: \Txn.date, order: .reverse) private var all: [Txn]
    @AppStorage("usdRate") private var usdRate = 88.0
    @State private var byTag = false

    struct Bucket: Identifiable {
        let name: String
        let total: Double
        let txns: [Txn]
        var id: String { name }
    }

    private var monthTxns: [Txn] {
        all.filter { $0.countsAsSpend && Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    private var buckets: [Bucket] {
        var map: [String: [Txn]] = [:]
        for t in monthTxns {
            if byTag {
                for tag in t.tags.isEmpty ? ["untagged"] : t.tags { map[tag, default: []].append(t) }
            } else {
                map[t.vendor, default: []].append(t)
            }
        }
        return map.map { Bucket(name: $0.key, total: $0.value.reduce(0) { $0 + $1.spend(usdRate: usdRate) }, txns: $0.value) }
            .sorted { $0.total > $1.total }
    }

    var body: some View {
        let b = buckets
        let monthTotal = monthTxns.reduce(0) { $0 + $1.spend(usdRate: usdRate) }
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Spent in \(Fmt.monthName(month))").font(.subheadline.weight(.medium)).foregroundStyle(Theme.muted)
                        Spacer()
                        MonthStepper(month: $month)
                    }
                    AmountText(value: monthTotal.rounded(), size: 44)
                        .contentTransition(.numericText(value: monthTotal))
                        .padding(.top, 8)
                    SegmentedPill(left: "Places", right: "Tags", isRight: $byTag)
                        .padding(.top, 20)
                }
                .card()

                if b.isEmpty {
                    Text("No spending in \(Fmt.monthName(month))")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity).card()
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(b.enumerated()), id: \.element.id) { i, bucket in
                            if i > 0 { Divider().overlay(Theme.line) }
                            NavigationLink {
                                BucketView(title: bucket.name, total: bucket.total, txns: bucket.txns)
                            } label: {
                                BucketRow(name: bucket.name, total: bucket.total,
                                          count: bucket.txns.count, share: monthTotal > 0 ? bucket.total / monthTotal : 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .card(padding: 16)

                    if byTag {
                        Text("A payment with several tags counts under each one.")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .animation(.snappy, value: byTag)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Breakdown")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BucketRow: View {
    let name: String
    let total: Double
    let count: Int
    let share: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(name).font(.body.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer()
                    AmountText(value: total.rounded(), size: 16)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.fill)
                        Capsule().fill(Theme.accent).frame(width: max(6, g.size.width * share))
                    }
                }
                .frame(height: 6)
                HStack {
                    Text(Fmt.payments(count))
                    Spacer()
                    Text(share.formatted(.percent.precision(.fractionLength(0))))
                }
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// All payments for one place or tag.
private struct BucketView: View {
    let title: String
    let total: Double
    let txns: [Txn]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Fmt.payments(txns.count)).font(.subheadline.weight(.medium)).foregroundStyle(Theme.muted)
                    AmountText(value: total.rounded(), size: 40)
                }
                .card()
                TxnListCard(txns: txns)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Two-option pill switch, e.g. Places | Tags.
struct SegmentedPill: View {
    let left: String
    let right: String
    @Binding var isRight: Bool
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            option(left, selected: !isRight) { isRight = false }
            option(right, selected: isRight) { isRight = true }
        }
        .padding(4)
        .background(Theme.fill, in: Capsule())
        .sensoryFeedback(.selection, trigger: isRight)
    }

    private func option(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(selected ? Theme.ink : Theme.muted)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background {
                    if selected {
                        Capsule().fill(Theme.card)
                            .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
                            .matchedGeometryEffect(id: "pill", in: ns)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
