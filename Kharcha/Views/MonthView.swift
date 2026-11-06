import SwiftUI
import SwiftData

struct MonthView: View {
    @Binding var month: Date
    @Query(sort: \Txn.date, order: .reverse) private var all: [Txn]
    @Environment(\.modelContext) private var context
    @AppStorage("usdRate") private var usdRate = 88.0
    @State private var selectedDay: Date?

    private var cal: Calendar { .current }
    private var monthTxns: [Txn] { all.filter { cal.isDate($0.date, equalTo: month, toGranularity: .month) } }
    private var shown: [Txn] {
        guard let d = selectedDay else { return monthTxns }
        return monthTxns.filter { cal.isDate($0.date, inSameDayAs: d) }
    }
    private var spent: Double { monthTxns.filter(\.countsAsSpend).reduce(0) { $0 + $1.inr(usdRate: usdRate) } }
    private var received: Double { monthTxns.filter { $0.isCredit && !$0.excluded }.reduce(0) { $0 + $1.inr(usdRate: usdRate) } }
    private var byDay: [Date: Double] {
        Dictionary(grouping: monthTxns.filter(\.countsAsSpend)) { cal.startOfDay(for: $0.date) }
            .mapValues { $0.reduce(0) { $0 + $1.inr(usdRate: usdRate) } }
    }
    struct DayGroup: Identifiable {
        let day: Date
        let txns: [Txn]
        var id: Date { day }
    }
    private var groups: [DayGroup] {
        Dictionary(grouping: shown) { cal.startOfDay(for: $0.date) }
            .map { DayGroup(day: $0.key, txns: $0.value) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        MonthSwitcher(month: $month)
                        VStack(spacing: 2) {
                            Text("Spent").font(.subheadline).foregroundStyle(.secondary)
                            Text(Fmt.money(spent.rounded())).font(.system(size: 40, weight: .bold, design: .rounded))
                            Text("\(monthTxns.filter(\.countsAsSpend).count) payments" + (received > 0 ? " · \(Fmt.money(received.rounded())) received" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        CalendarGrid(month: month, totals: byDay, selected: $selectedDay)
                    }
                    .padding(.vertical, 6)
                }

                if monthTxns.isEmpty {
                    ContentUnavailableView("Nothing this month", systemImage: "tray",
                        description: Text("Set up automatic logging in Settings, or paste a message in Add."))
                } else {
                    ForEach(groups) { g in
                        let day = g.day, txns = g.txns
                        Section {
                            ForEach(txns) { t in
                                NavigationLink(value: t) { TxnRow(txn: t) }
                            }
                            .onDelete { idx in idx.forEach { context.delete(txns[$0]) } }
                        } header: {
                            HStack {
                                Text(day.formatted(.dateTime.weekday(.abbreviated).day().month()))
                                Spacer()
                                Text(Fmt.money((byDay[day] ?? 0).rounded()))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Kharcha")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Txn.self) { TxnDetailView(txn: $0) }
            .onChange(of: month) { selectedDay = nil }
        }
    }
}

struct CalendarGrid: View {
    let month: Date
    let totals: [Date: Double]
    @Binding var selected: Date?

    private let cal = Calendar.current
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var days: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month),
              let count = cal.range(of: .day, in: .month, for: month)?.count else { return [] }
        let first = interval.start
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        return Array(repeating: nil, count: lead) + (0..<count).map { cal.date(byAdding: .day, value: $0, to: first) }
    }

    var body: some View {
        let maxV = max(totals.values.max() ?? 1, 1)
        VStack(spacing: 4) {
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(Array(cal.veryShortWeekdaySymbols.rotated(by: cal.firstWeekday - 1).enumerated()), id: \.offset) { _, s in
                    Text(s).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let v = totals[cal.startOfDay(for: day)] ?? 0
                        let isSel = selected.map { cal.isDate($0, inSameDayAs: day) } ?? false
                        Button {
                            selected = isSel ? nil : day
                        } label: {
                            VStack(spacing: 0) {
                                Text("\(cal.component(.day, from: day))").font(.caption.weight(cal.isDateInToday(day) ? .bold : .regular))
                                Text(v > 0 ? Fmt.short(v) : " ").font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.accentColor.opacity(v > 0 ? 0.08 + 0.4 * (v / maxV) : 0))
                            )
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: isSel ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
            if selected != nil {
                Button("Show whole month") { selected = nil }.font(.caption).buttonStyle(.borderless)
            }
        }
    }
}

extension Array {
    func rotated(by n: Int) -> [Element] {
        guard !isEmpty else { return self }
        let k = ((n % count) + count) % count
        return Array(self[k...] + self[..<k])
    }
}
