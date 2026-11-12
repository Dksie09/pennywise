import SwiftUI
import SwiftData

/// The month as a calendar. Each day shows what you spent; tap a day to see its payments.
struct CalendarView: View {
    @Binding var month: Date
    @Query(sort: \Txn.date, order: .reverse) private var all: [Txn]
    @AppStorage("usdRate") private var usdRate = 88.0
    @State private var selected: Date?

    private var cal: Calendar { .current }
    private var monthTxns: [Txn] { all.filter { cal.isDate($0.date, equalTo: month, toGranularity: .month) } }
    private var byDay: [Date: Double] {
        Dictionary(grouping: monthTxns.filter(\.countsAsSpend)) { cal.startOfDay(for: $0.date) }
            .mapValues { $0.reduce(0) { $0 + $1.spend(usdRate: usdRate) } }
    }

    var body: some View {
        let totals = byDay
        let spent = totals.values.reduce(0, +)
        ScrollView {
            VStack(spacing: 14) {
                AppHeader()
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(Fmt.monthTitle(month)).font(.footnote.weight(.medium)).foregroundStyle(Theme.muted)
                        Spacer()
                        MonthStepper(month: $month)
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
                    CalendarGrid(month: month, totals: totals, selected: $selected)
                    HStack {
                        Text("\(Fmt.money(spent.rounded())) spent")
                            .font(.caption.weight(.medium)).foregroundStyle(Theme.muted).monospacedDigit()
                        Spacer()
                        HeatLegend()
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 14).padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass(RoundedRectangle(cornerRadius: Theme.radius + 2, style: .continuous))
                .monthSwipe($month)

                dayPayments(totals).padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .animation(.snappy, value: selected)
        }
        .starryPage()
        .onAppear { if selected == nil { selected = defaultDay } }
        .onChange(of: month) { selected = defaultDay }
    }

    /// Today when looking at this month, otherwise nothing selected.
    private var defaultDay: Date? {
        cal.isDate(month, equalTo: Date(), toGranularity: .month) ? cal.startOfDay(for: Date()) : nil
    }

    @ViewBuilder private func dayPayments(_ totals: [Date: Double]) -> some View {
        if let day = selected {
            let txns = monthTxns.filter { cal.isDate($0.date, inSameDayAs: day) }
            VStack(spacing: 8) {
                SectionLabel(title: Fmt.dayTitle(day)) {
                    if let v = totals[day], v > 0 { Text(Fmt.money(v.rounded())).monospacedDigit() }
                }
                if txns.isEmpty {
                    NappingPenny(title: "Nothing spent this day")
                } else {
                    TxnListCard(txns: txns)
                }
            }
        } else if monthTxns.isEmpty {
            NappingPenny(title: "Nothing logged in \(Fmt.monthName(month))")
        } else {
            // No day picked: the whole month, newest day first.
            let days = Dictionary(grouping: monthTxns) { cal.startOfDay(for: $0.date) }.sorted { $0.key > $1.key }
            ForEach(days, id: \.key) { day, txns in
                VStack(spacing: 8) {
                    SectionLabel(title: Fmt.dayTitle(day)) {
                        if let v = totals[day], v > 0 { Text(Fmt.money(v.rounded())).monospacedDigit() }
                    }
                    TxnListCard(txns: txns.sorted { $0.date > $1.date })
                }
                .padding(.top, 4)
            }
        }
    }
}

struct CalendarGrid: View {
    let month: Date
    let totals: [Date: Double]
    @Binding var selected: Date?

    private let cal = Calendar.current
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    private var days: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month),
              let count = cal.range(of: .day, in: .month, for: month)?.count else { return [] }
        let first = interval.start
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        return Array(repeating: nil, count: lead) + (0..<count).map { cal.date(byAdding: .day, value: $0, to: first) }
    }

    var body: some View {
        let maxV = max(totals.values.max() ?? 1, 1)
        LazyVGrid(columns: cols, spacing: 5) {
            ForEach(Array(cal.veryShortWeekdaySymbols.rotated(by: cal.firstWeekday - 1).enumerated()), id: \.offset) { _, s in
                Text(s).font(.caption2.weight(.medium)).foregroundStyle(Theme.faint).padding(.bottom, 2)
            }
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    cell(day, value: totals[cal.startOfDay(for: day)] ?? 0, maxV: maxV)
                } else {
                    Color.clear.frame(height: 46)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func cell(_ day: Date, value v: Double, maxV: Double) -> some View {
        let isSel = selected.map { cal.isDate($0, inSameDayAs: day) } ?? false
        let future = day > Date()
        let today = cal.isDateInToday(day)
        let shade = CalendarGrid.shade(v, maxV: maxV, future: future)
        let onDark = shade > 0.4
        // Grey strength = how much you spent. Selection = a ring. Today = bold number.
        return Button {
            selected = isSel ? nil : cal.startOfDay(for: day)
        } label: {
            VStack(spacing: 1) {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 14, weight: today ? .bold : .medium))
                    .foregroundStyle(future ? Theme.faint.opacity(0.6) : onDark ? .white : Theme.ink)
                Text(v > 0 ? Fmt.short(v) : " ")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(onDark ? Color.white.opacity(0.8) : Theme.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Theme.ink.opacity(shade), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.ink, lineWidth: isSel ? 1.5 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(future)
        .accessibilityLabel(day.formatted(.dateTime.day().month(.wide)))
        .accessibilityValue(v > 0 ? Fmt.money(v.rounded()) : "Nothing spent")
        .accessibilityAddTraits(isSel ? .isSelected : [])
    }

    static func shade(_ v: Double, maxV: Double, future: Bool) -> Double {
        if future { return 0 }
        if v <= 0 { return 0.035 }
        return 0.06 + 0.5 * min(v / maxV, 1)
    }
}

/// "Less ▢▢▢▢ More"
private struct HeatLegend: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("Less")
            ForEach([0.05, 0.14, 0.3, 0.55], id: \.self) { a in
                RoundedRectangle(cornerRadius: 4).fill(Theme.ink.opacity(a)).frame(width: 12, height: 12)
            }
            Text("More")
        }
        .font(.caption2).foregroundStyle(Theme.faint)
        .accessibilityHidden(true)
    }
}

extension Array {
    func rotated(by n: Int) -> [Element] {
        guard !isEmpty else { return self }
        let k = ((n % count) + count) % count
        return Array(self[k...] + self[..<k])
    }
}
