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
            .mapValues { $0.reduce(0) { $0 + $1.inr(usdRate: usdRate) } }
    }

    var body: some View {
        let totals = byDay
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Fmt.monthTitle(month)).font(.headline).foregroundStyle(Theme.ink)
                            Text("\(Fmt.money(totals.values.reduce(0, +).rounded())) spent")
                                .font(.subheadline).foregroundStyle(Theme.muted).monospacedDigit()
                        }
                        Spacer()
                        MonthStepper(month: $month)
                    }
                    CalendarGrid(month: month, totals: totals, selected: $selected)
                }
                .card()

                dayPayments(totals)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .animation(.snappy, value: selected)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
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
                    if let v = totals[day] { Text(Fmt.money(v.rounded())).monospacedDigit() }
                }
                if txns.isEmpty {
                    Text("Nothing spent on this day")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .card()
                } else {
                    TxnListCard(txns: txns)
                }
            }
        } else {
            Text("Tap a day to see its payments")
                .font(.subheadline).foregroundStyle(Theme.muted)
                .padding(.top, 4)
        }
    }
}

struct CalendarGrid: View {
    let month: Date
    let totals: [Date: Double]
    @Binding var selected: Date?

    private let cal = Calendar.current
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    private var days: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month),
              let count = cal.range(of: .day, in: .month, for: month)?.count else { return [] }
        let first = interval.start
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        return Array(repeating: nil, count: lead) + (0..<count).map { cal.date(byAdding: .day, value: $0, to: first) }
    }

    var body: some View {
        let maxV = max(totals.values.max() ?? 1, 1)
        LazyVGrid(columns: cols, spacing: 6) {
            ForEach(Array(cal.veryShortWeekdaySymbols.rotated(by: cal.firstWeekday - 1).enumerated()), id: \.offset) { _, s in
                Text(s).font(.caption.weight(.medium)).foregroundStyle(Theme.muted).padding(.bottom, 2)
            }
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    cell(day, value: totals[cal.startOfDay(for: day)] ?? 0, maxV: maxV)
                } else {
                    Color.clear.frame(height: 48)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func cell(_ day: Date, value v: Double, maxV: Double) -> some View {
        let isSel = selected.map { cal.isDate($0, inSameDayAs: day) } ?? false
        let future = day > Date()
        let today = cal.isDateInToday(day)
        return Button {
            selected = isSel ? nil : cal.startOfDay(for: day)
        } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: day))")
                    .font(.subheadline.weight(today || isSel ? .semibold : .regular))
                Text(v > 0 ? Fmt.short(v) : " ")
                    .font(.system(size: 10, weight: .medium))
                    .opacity(isSel ? 0.8 : 1)
                    .foregroundStyle(isSel ? Theme.card : Theme.muted)
            }
            .foregroundStyle(isSel ? Theme.card : (future ? Theme.muted.opacity(0.5) : Theme.ink))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSel ? Theme.ink : Theme.accent.opacity(v > 0 ? 0.06 + 0.3 * (v / maxV) : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.ink.opacity(today && !isSel ? 0.25 : 0), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(future)
        .accessibilityLabel(day.formatted(.dateTime.day().month(.wide)))
        .accessibilityValue(v > 0 ? Fmt.money(v.rounded()) : "Nothing spent")
        .accessibilityAddTraits(isSel ? .isSelected : [])
    }
}

extension Array {
    func rotated(by n: Int) -> [Element] {
        guard !isEmpty else { return self }
        let k = ((n % count) + count) % count
        return Array(self[k...] + self[..<k])
    }
}
