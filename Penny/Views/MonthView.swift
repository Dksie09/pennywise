import SwiftUI
import SwiftData

struct MonthView: View {
    @Binding var month: Date
    @Query(sort: \Txn.date, order: .reverse) private var all: [Txn]
    @AppStorage("usdRate") private var usdRate = 88.0
    @State private var selectedDay: Date?
    @Environment(PageRouter.self) private var router
    @AppStorage("greetingDismissedDay") private var greetingDismissedDay = ""
    @State private var greetingReplays = 0

    private var cal: Calendar { .current }
    private var isThisMonth: Bool { cal.isDate(month, equalTo: Date(), toGranularity: .month) }
    private var monthTxns: [Txn] { all.filter { cal.isDate($0.date, equalTo: month, toGranularity: .month) } }
    private var shown: [Txn] {
        guard let d = selectedDay else { return monthTxns }
        return monthTxns.filter { cal.isDate($0.date, inSameDayAs: d) }
    }
    private func total(_ txns: [Txn]) -> Double { txns.reduce(0) { $0 + $1.spend(usdRate: usdRate) } }
    private var spent: Double { total(shown.filter(\.countsAsSpend)) }
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

    /// "↑ ₹8,724 vs last month". Only shown when both months are fully tracked: logging had started
    /// by the 3rd of last month, last month has a few payments, and this month is at least a week old.
    /// For the current month it compares against the same days of last month, so a half-done month isn't flattered.
    private var comparison: (text: String, up: Bool)? {
        guard selectedDay == nil, spent > 0,
              let prev = cal.date(byAdding: .month, value: -1, to: month),
              let prevStart = cal.dateInterval(of: .month, for: prev)?.start,
              let firstLogged = all.last?.date,
              let cutoffForStart = cal.date(byAdding: .day, value: 3, to: prevStart),
              firstLogged < cutoffForStart else { return nil }
        let today = cal.component(.day, from: Date())
        if isThisMonth && today < 7 { return nil }
        let prevTxns = all.filter { $0.countsAsSpend && cal.isDate($0.date, equalTo: prev, toGranularity: .month) }
        guard prevTxns.count >= 5 else { return nil }
        let cutoff = isThisMonth ? today : 31
        let diff = spent - total(prevTxns.filter { cal.component(.day, from: $0.date) <= cutoff })
        if abs(diff) < 1 { return ("Same as last month", false) }
        return ("\(Fmt.money(abs(diff).rounded())) vs last month", diff > 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    AppHeader()
                    if showGreeting { greeting.transition(.move(edge: .top).combined(with: .opacity)) }
                    hero
                    payments
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .animation(.snappy, value: showGreeting)
            }
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    Theme.bg
                    CornerGlow()
                    StarryTop()
                }
                .ignoresSafeArea()
            }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: month) { selectedDay = nil }
        }
        .tint(Theme.accent)
    }

    // MARK: Greeting

    private var todayKey: String { Date().formatted(.iso8601.year().month().day()) }

    /// A small hello from Penny, once a day, until dismissed.
    private var showGreeting: Bool { isThisMonth && !all.isEmpty && greetingDismissedDay != todayKey }

    private var greeting: some View {
        let hour = cal.component(.hour, from: Date())
        let hello = hour < 12 ? "Good morning!" : hour < 17 ? "Good afternoon!" : "Good evening!"
        let n = all.filter { $0.countsAsSpend && cal.isDateInToday($0.date) }.count
        return HStack(spacing: 10) {
            PennyAnimation(clip: .wave, height: 42, replay: greetingReplays).frame(width: 48)
            VStack(alignment: .leading, spacing: 1) {
                Text(hello).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(n == 0 ? "Nothing spent yet today." : "\(Fmt.payments(n)) tucked away today.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Button { greetingDismissedDay = todayKey } label: {
                Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundStyle(Theme.faint)
                    .frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss greeting")
        }
        .padding(.leading, 6).padding(.trailing, 8).padding(.vertical, 8)
        .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        // Tap the banner (anywhere but ✕) and Penny waves again.
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture { greetingReplays += 1 }
        .accessibilityAction(named: "Wave again") { greetingReplays += 1 }
    }

    // MARK: Total

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

            AmountText(value: spent.rounded(), size: 54, weight: .medium)
                .contentTransition(.numericText(value: spent))
                .padding(.top, 4)

            if let c = comparison {
                Chip(text: c.text, icon: c.up ? "arrow.up" : "arrow.down")
                    .padding(.top, 6)
                    .accessibilityLabel("\(c.text.replacingOccurrences(of: " vs", with: c.up ? " more than" : " less than"))")
            }

            if all.isEmpty {
                // Nothing logged ever: a quiet row of dots instead of an empty chart.
                HStack(spacing: 4) {
                    ForEach(0..<30, id: \.self) { _ in Capsule().fill(Theme.ink.opacity(0.08)).frame(height: 6) }
                }
                .padding(.top, 18)
                .accessibilityHidden(true)
            } else {
                DayBars(month: month, totals: byDay, selected: $selectedDay)
                    .frame(height: 100)
                    .padding(.top, 20)
            }
        }
        .fadingGlassCard()
        .monthSwipe($month)
        .animation(.snappy, value: selectedDay)
    }

    @ViewBuilder private var payments: some View {
        if all.isEmpty {
            firstLaunch
        } else if monthTxns.isEmpty {
            NappingPenny(title: "Nothing logged in \(Fmt.monthName(month))")
        } else if shown.isEmpty {
            NappingPenny(title: "Nothing spent this day")
        } else {
            ForEach(groups) { g in
                VStack(spacing: 8) {
                    SectionLabel(title: Fmt.dayTitle(g.day)) {
                        if let v = byDay[g.day], v > 0 { Text(Fmt.money(v.rounded())).monospacedDigit() }
                    }
                    TxnListCard(txns: g.txns)
                }
                .padding(.top, 8)
            }
        }
    }
}

extension MonthView {
    /// Before anything has been logged: Penny naps, and the way forward is one button.
    var firstLaunch: some View {
        VStack(spacing: 0) {
            SleepyPenny(height: 88)
            Text("Nothing logged yet")
                .font(Theme.serif(28)).foregroundStyle(Theme.ink)
                .padding(.top, 12)
            Text("Penny’s napping until your first payment. Set up automatic logging once and bank SMS land here on their own.")
                .font(.subheadline).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center).lineSpacing(2)
                .padding(.top, 6)
            NavigationLink { SetupGuideView() } label: {
                Text("Set up automatic logging").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill)
            .padding(.top, 18)
            Button("Add a payment by hand") { router.adding = true }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 44)
                .padding(.top, 6)
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity)
        .card(padding: 22)
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

    /// Ink bars, faint dots for days with nothing spent. A selected day turns purple; the rest go a softer grey.
    private func color(_ d: Date, _ v: Double) -> Color {
        if d > Date() { return Theme.ink.opacity(0.06) }
        if v == 0 { return Theme.ink.opacity(0.12) }
        guard selected != nil else { return Theme.ink }
        return isSelected(d) ? Theme.selected : Theme.ink.opacity(0.32)
    }
}
