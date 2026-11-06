import SwiftUI
import SwiftData

struct VendorsView: View {
    @Binding var month: Date
    @Query(sort: \Txn.date, order: .reverse) private var all: [Txn]
    @AppStorage("usdRate") private var usdRate = 88.0
    @State private var mode = 0

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
            if mode == 0 {
                map[t.vendor, default: []].append(t)
            } else {
                let tags = t.tags.isEmpty ? ["untagged"] : t.tags
                for tag in tags { map[tag, default: []].append(t) }
            }
        }
        return map.map { Bucket(name: $0.key, total: $0.value.reduce(0) { $0 + $1.inr(usdRate: usdRate) }, txns: $0.value) }
            .sorted { $0.total > $1.total }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MonthSwitcher(month: $month)
                    Picker("Group by", selection: $mode) {
                        Text("Vendor").tag(0)
                        Text("Tag").tag(1)
                    }
                    .pickerStyle(.segmented)
                }
                let b = buckets
                let top = b.first?.total ?? 1
                if b.isEmpty {
                    ContentUnavailableView("No spending", systemImage: "chart.bar")
                }
                ForEach(b) { bucket in
                    NavigationLink {
                        List(bucket.txns) { t in NavigationLink { TxnDetailView(txn: t) } label: { TxnRow(txn: t) } }
                            .navigationTitle(mode == 0 ? bucket.name : "#\(bucket.name)")
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(mode == 0 ? bucket.name : "#\(bucket.name)").font(.body.weight(.medium))
                                Spacer()
                                Text(Fmt.money(bucket.total.rounded())).font(.body.monospacedDigit())
                            }
                            ProgressView(value: bucket.total, total: top)
                            Text("\(bucket.txns.count) payment\(bucket.txns.count == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if mode == 1, !b.isEmpty {
                    Text("A payment with several tags counts under each tag.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Spending")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
