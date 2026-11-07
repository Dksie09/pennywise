import SwiftUI
import SwiftData

struct MonthView: View {
    @Binding var month: Date
    @Query(sort: \Txn.date, order: .reverse) private var all: [Txn]
    @AppStorage("usdRate") private var usdRate = 88.0
    @State private var selectedDay: Date?
    @State private var adding = false

    private var cal: Calendar { .current }
    private var isThisMonth: Bool { cal.isDate(month, equalTo: Date(), toGranularity: .month) }
    private var monthTxns: [Txn] { all.filter { cal.isDate($0.date, equalTo: month, toGranularity: .month) } }
    private var shown: [Txn] {
        guard let d = selectedDay else { return monthTxns }
        return monthTxns.filter { cal.isDate($0.date, inSameDayAs: d) }
    }
    private func total(_ txns: [Txn]) -> Double { txns.reduce(0) { $0 + $1.inr(usdRate: usdRate) } }
    private var spent: Double { total(shown.filter(\.countsAsSpend)) }
    private var received: Double { total(shown.filter { $0.isCredit && !$0.excluded }) }
    private var byDay: [Date: Double] {
        Dictionary(grouping: monthTxns.filter(\.countsAsSpend)) { cal.startOfDay(for: $0.date) }
            .mapValues(total)
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

    /// "₹2,100 less than 1–8 Oct". In the current month it compares the same days of last month.
    private var comparison: (text: String, down: Bool)? {
        guard selectedDay == nil, let prev = cal.date(byAdding: .month, value: -1, to: month) else { return nil }
        let prevTxns = all.filter { $0.countsAsSpend && cal.isDate($0.date, equalTo: prev, toGranularity: .month) }
        guard !prevTxns.isEmpty, spent > 0 else { return nil }
        let cutoff = isThisMonth ? cal.component(.day, from: Date()) : 31
        let before = total(prevTxns.filter { cal.component(.day, from: $0.date) <= cutoff })
        let diff = spent - before
        let name = isThisMonth ? "1–\(cutoff) \(prev.formatted(.dateTime.month(.abbreviated)))" : prev.formatted(.dateTime.month(.wide))
        if abs(diff) < 1 { return ("Same as \(name)", true) }
        return ("\(Fmt.money(abs(diff).rounded())) \(diff < 0 ? "less" : "more") than \(name)", diff < 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    hero
                    actions
                    payments
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Txn.self) { TxnDetailView(txn: $0) }
            .onChange(of: month) { selectedDay = nil }
            .sheet(isPresented: $adding) { AddView() }
        }
        .tint(Theme.accent)
    }

    private var header: some View {
        HStack {
            Text("Penny").font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
            Spacer()
            NavigationLink { CalendarView(month: $month) } label: { Image(systemName: "calendar") }
                .buttonStyle(CircleButtonStyle())
                .accessibilityLabel("Calendar")
            NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                .buttonStyle(CircleButtonStyle())
                .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
    }

    private var heroLabel: String {
        guard let d = selectedDay else { return "Spent in \(Fmt.monthName(month))" }
        let title = Fmt.dayTitle(d)
        return cal.isDateInToday(d) || cal.isDateInYesterday(d) ? "Spent \(title.lowercased())" : "Spent on \(title)"
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(heroLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.muted)
                    .contentTransition(.opacity)
                Spacer()
                if selectedDay != nil {
                    Button { withAnimation(.snappy) { selectedDay = nil } } label: {
                        Text("Whole month").font(.footnote.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(Theme.fill, in: Capsule())
                } else {
                    MonthStepper(month: $month)
                }
            }

            AmountText(value: spent.rounded(), size: 52, weight: .medium)
                .contentTransition(.numericText(value: spent))
                .padding(.top, 8)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { chips }
                VStack(alignment: .leading, spacing: 6) { chips }
            }
            .padding(.top, 10)

            DayBars(month: month, totals: byDay, selected: $selectedDay)
                .frame(height: 132)
                .padding(.top, 24)
        }
        .card()
        .animation(.snappy, value: selectedDay)
    }

    @ViewBuilder private var chips: some View {
        if let c = comparison {
            Chip(text: c.text, icon: c.down ? "arrow.down.right" : "arrow.up.right")
        } else {
            Chip(text: Fmt.payments(shown.filter(\.countsAsSpend).count))
        }
        if received > 0 {
            Chip(text: "\(Fmt.money(received.rounded())) received", tint: Theme.positive)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button { adding = true } label: {
                Label("Add payment", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill)
            NavigationLink { VendorsView(month: $month) } label: {
                Label("Breakdown", systemImage: "chart.bar.xaxis").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pillLight)
        }
    }

    @ViewBuilder private var payments: some View {
        if monthTxns.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "tray").font(.title2).foregroundStyle(Theme.muted)
                Text("Nothing in \(Fmt.monthName(month))").font(.headline).foregroundStyle(Theme.ink)
                Text("Payments appear here automatically once SMS logging is set up in Settings. You can also add one by hand.")
                    .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .card()
        } else if shown.isEmpty {
            Text("No payments on this day")
                .font(.subheadline).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
                .card()
        } else {
            ForEach(groups) { g in
                VStack(spacing: 8) {
                    SectionLabel(title: Fmt.dayTitle(g.day)) {
                        if let v = byDay[g.day] { Text(Fmt.money(v.rounded())).monospacedDigit() }
                    }
                    TxnListCard(txns: g.txns)
                }
                .padding(.top, 8)
            }
        }
    }
}

/// One bar per day of the month. Tap a bar to see just that day; tap it again for the whole month.
struct DayBars: View {
    let month: Date
    let totals: [Date: Double]
    @Binding var selected: Date?

    private let cal = Calendar.current
    private let gap: CGFloat = 3

    private var days: [Date] {
        guard let start = cal.dateInterval(of: .month, for: month)?.start,
              let count = cal.range(of: .day, in: .month, for: month)?.count else { return [] }
        return (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        let days = days
        let maxV = max(totals.values.max() ?? 0, 1)
        GeometryReader { geo in
            let w = max((geo.size.width - gap * CGFloat(days.count - 1)) / CGFloat(max(days.count, 1)), 2)
            let barArea = geo.size.height - 22
            VStack(spacing: 8) {
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(days, id: \.self) { d in
                        let v = totals[d] ?? 0
                        Capsule()
                            .fill(color(d, v))
                            .frame(width: w, height: v > 0 ? max(w, barArea * v / maxV) : w)
                            .accessibilityElement()
                            .accessibilityLabel(d.formatted(.dateTime.day().month(.wide)))
                            .accessibilityValue(v > 0 ? Fmt.money(v.rounded()) : "Nothing spent")
                            .accessibilityAddTraits(isSelected(d) ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction { toggle(d) }
                    }
                }
                .frame(height: barArea, alignment: .bottom)

                HStack(spacing: gap) {
                    ForEach(days, id: \.self) { d in
                        let n = cal.component(.day, from: d)
                        Color.clear.frame(width: w, height: 14).overlay {
                            if n == 1 || n % 7 == 1 && n < 29 || n == days.count {
                                Text("\(n)").font(.caption2).foregroundStyle(Theme.muted).fixedSize()
                            }
                        }
                    }
                }
                .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .onTapGesture { loc in
                let i = Int(loc.x / (w + gap))
                if days.indices.contains(i) { toggle(days[i]) }
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func isSelected(_ d: Date) -> Bool { selected.map { cal.isDate($0, inSameDayAs: d) } ?? false }

    private func toggle(_ d: Date) {
        guard d <= Date() else { return }
        withAnimation(.snappy) { selected = isSelected(d) ? nil : d }
    }

    private func color(_ d: Date, _ v: Double) -> Color {
        if d > Date() { return Theme.line.opacity(0.5) }
        if v == 0 { return Theme.line }
        guard selected != nil else { return Theme.ink }
        return isSelected(d) ? Theme.accent : Theme.ink.opacity(0.14)
    }
}
