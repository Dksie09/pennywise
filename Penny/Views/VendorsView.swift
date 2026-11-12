import SwiftUI
import SwiftData

/// Where the month's money went, by place or by tag. Two layouts to choose from (switch at the top right):
/// a list with a split bar, or tiles under a "most went to" card.
struct VendorsView: View {
    @Binding var month: Date
    @Query(sort: \Txn.date, order: .reverse) private var all: [Txn]
    @AppStorage("usdRate") private var usdRate = 88.0
    @AppStorage("breakdownTiles") private var tiles = false
    @State private var byTag = false
    @State private var selected: String?        // a place/tag picked on the bar or ring

    struct Bucket: Identifiable {
        let name: String
        let total: Double
        let txns: [Txn]
        var id: String { name }
    }

    private var monthTxns: [Txn] {
        all.filter { $0.countsAsSpend && Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    /// Biggest first; past the top five, the rest are grouped as "Everything else".
    private var buckets: [Bucket] {
        var map: [String: [Txn]] = [:]
        for t in monthTxns {
            if byTag {
                for tag in t.tags.isEmpty ? ["untagged"] : t.tags { map[tag, default: []].append(t) }
            } else {
                map[t.vendor, default: []].append(t)
            }
        }
        let sorted = map.map { Bucket(name: $0.key, total: $0.value.reduce(0) { $0 + $1.spend(usdRate: usdRate) }, txns: $0.value) }
            .sorted { $0.total > $1.total }
        guard sorted.count > 6 else { return sorted }
        let rest = sorted.dropFirst(5)
        return Array(sorted.prefix(5)) + [Bucket(name: "Everything else", total: rest.reduce(0) { $0 + $1.total },
                                               txns: rest.flatMap(\.txns).sorted { $0.date > $1.date })]
    }

    static let shades: [Double] = [1, 0.72, 0.5, 0.34, 0.2, 0.1]

    var body: some View {
        let b = buckets
        let total = monthTxns.reduce(0) { $0 + $1.spend(usdRate: usdRate) }
        ScrollView {
            VStack(spacing: 14) {
                AppHeader()
                if tiles { tilesLayout(b, total: total) } else { listLayout(b, total: total) }
                if byTag && !b.isEmpty {
                    Text("A payment with several tags counts under each one.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .animation(.snappy, value: byTag)
            .animation(.snappy, value: tiles)
            .animation(.snappy, value: selected)
        }
        .starryPage()
        .onChange(of: byTag) { selected = nil }
        .onChange(of: month) { selected = nil }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private var layoutSwitch: some View {
        HStack(spacing: 2) {
            ForEach([false, true], id: \.self) { t in
                Button { tiles = t } label: {
                    Image(systemName: t ? "square.grid.2x2" : "list.bullet")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tiles == t ? Theme.card : Theme.ink)
                        .frame(width: 34, height: 30)
                        .background(Capsule().fill(tiles == t ? Theme.ink : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t ? "Tiles" : "List")
                .accessibilityAddTraits(tiles == t ? .isSelected : [])
            }
        }
        .padding(3)
        .glass(Capsule())
    }

    // MARK: Summary card

    /// Small label, big serif line, one line of detail; a visual on the right. (Callers wrap it in glass.)
    /// Shows the month's total, or the place/tag picked on the bar or ring.
    private func summaryCard<V: View>(_ b: [Bucket], total: Double, count: Int, visualAlignment: VerticalAlignment = .center,
                                      @ViewBuilder visual: () -> V) -> some View {
        let pick = b.first { $0.name == selected }
        return HStack(alignment: visualAlignment, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(pick?.name ?? "Spent in \(Fmt.monthName(month))")
                    .font(.footnote.weight(.medium)).foregroundStyle(Theme.muted).lineLimit(1)
                Text(Fmt.money((pick?.total ?? total).rounded()))
                    .font(Theme.serif(34)).foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Group {
                    if let pick {
                        Text("\(percent(total > 0 ? pick.total / total : 0)) of the month · \(Fmt.payments(pick.txns.count))")
                    } else {
                        Text(Fmt.payments(count))
                    }
                }
                .font(.subheadline).foregroundStyle(Theme.muted)
                .lineLimit(1).minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
            visual()
        }
    }

    // MARK: A · list with a split bar

    @ViewBuilder private func listLayout(_ b: [Bucket], total: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryCard(b, total: total, count: monthTxns.count, visualAlignment: .top) {
                MonthStepper(month: $month)
            }
            if !b.isEmpty {
                SplitBar(slices: b.map { ($0.name, total > 0 ? max($0.total, 0) / total : 0) }, selected: $selected)
            }
        }
        .glassCard()

        HStack(spacing: 10) {
            SegmentedPill(left: "Places", right: "Tags", isRight: $byTag)
            layoutSwitch
        }

        if b.isEmpty {
            NappingPenny(title: "Nothing spent in \(Fmt.monthName(month))")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(b.enumerated()), id: \.element.id) { i, bucket in
                    if i > 0 { Divider().overlay(Theme.line).padding(.horizontal, 18) }
                    NavigationLink { BucketView(bucket: bucket, monthTotal: total, month: month) } label: {
                        HStack(spacing: 12) {
                            Circle().fill(Theme.ink.opacity(selected == bucket.name ? 1 : Self.shades[min(i, 5)])).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bucket.name).font(.body.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(1)
                                Text(meta(bucket, total)).font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 8)
                            AmountText(value: bucket.total.rounded(), size: 16)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.faint)
                        }
                        .padding(.vertical, 12).padding(.horizontal, 18)
                        .background(Theme.ink.opacity(selected == bucket.name ? 0.06 : 0))
                        .opacity(selected == nil || selected == bucket.name ? 1 : 0.45)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Theme.shadow.opacity(0.05), radius: 14, y: 6)
        }
    }

    // MARK: B · tiles

    @ViewBuilder private func tilesLayout(_ b: [Bucket], total: Double) -> some View {
        HStack(spacing: 10) {
            SegmentedPill(left: "Places", right: "Tags", isRight: $byTag)
            MonthStepper(month: $month)
            layoutSwitch
        }

        if b.isEmpty {
            NappingPenny(title: "Nothing spent in \(Fmt.monthName(month))")
        } else {
            summaryCard(b, total: total, count: monthTxns.count) {
                DonutChart(slices: b.map { ($0.name, max($0.total, 0)) }, selected: $selected)
                    .frame(width: 104, height: 104)
            }
            .glassCard()

            // One quiet card, split into a 2-column grid by hairlines.
            let rows = stride(from: 0, to: b.count, by: 2).map { Array(b[$0..<min($0 + 2, b.count)]) }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                    if r > 0 { Divider().overlay(Theme.line) }
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.element.id) { c, bucket in
                            if c > 0 { Rectangle().fill(Theme.line).frame(width: 1) }
                            tile(bucket, index: r * 2 + c, total: total)
                        }
                        if row.count == 1 {
                            Rectangle().fill(Theme.line).frame(width: 1)
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Theme.shadow.opacity(0.05), radius: 14, y: 6)
        }
    }

    private func tile(_ bucket: Bucket, index i: Int, total: Double) -> some View {
        let on = selected == bucket.name
        return NavigationLink { BucketView(bucket: bucket, monthTotal: total, month: month) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(Theme.ink.opacity(on ? 1 : Self.shades[min(i, 5)])).frame(width: 8, height: 8)
                    Text(bucket.name).font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
                }
                AmountText(value: bucket.total.rounded(), size: 19)
                Text(percent(total > 0 ? bucket.total / total : 0)).font(.caption).foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.ink.opacity(on ? 0.05 : 0))
            .opacity(selected == nil || on ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func meta(_ b: Bucket, _ total: Double) -> String {
        "\(percent(total > 0 ? b.total / total : 0)) · \(Fmt.payments(b.txns.count))"
    }

    private func percent(_ v: Double) -> String { v.formatted(.percent.precision(.fractionLength(0))) }
}

/// One rounded bar split into each bucket's share, darkest first. Tap a piece to pick it.
private struct SplitBar: View {
    let slices: [(name: String, share: Double)]
    @Binding var selected: String?

    var body: some View {
        GeometryReader { g in
            let gap: CGFloat = 3
            let usable = g.size.width - gap * CGFloat(max(slices.count - 1, 0))
            HStack(alignment: .center, spacing: gap) {
                ForEach(Array(slices.enumerated()), id: \.offset) { i, s in
                    let on = selected == s.name
                    Capsule()
                        .fill(Theme.ink.opacity(on ? 1 : VendorsView.shades[min(i, 5)] * (selected == nil ? 1 : 0.3)))
                        .frame(width: max(6, usable * s.share), height: on ? 16 : 10)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                        .onTapGesture { selected = on ? nil : s.name }
                        .accessibilityElement()
                        .accessibilityLabel(s.name)
                        .accessibilityValue(s.share.formatted(.percent.precision(.fractionLength(0))))
                        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .frame(height: 32)
    }
}

/// Rounded ring chart of every place/tag. Tap a piece to pick it; tap the middle to go back to the total.
private struct DonutChart: View {
    let slices: [(name: String, value: Double)]
    @Binding var selected: String?

    private var total: Double { max(slices.reduce(0) { $0 + $1.value }, 1) }

    /// Start and end of each slice as fractions of the circle.
    private var spans: [(start: Double, end: Double)] {
        var at = 0.0
        return slices.map { s in
            let start = at
            at += s.value / total
            return (start, at)
        }
    }

    var body: some View {
        GeometryReader { g in
            let side = min(g.size.width, g.size.height)
            let line: CGFloat = 13
            let gap = slices.count > 1 ? 0.006 : 0
            ZStack {
                ForEach(Array(spans.enumerated()), id: \.offset) { i, span in
                    let on = selected == slices[i].name
                    Circle()
                        .trim(from: span.start + gap, to: max(span.start + gap, span.end - gap))
                        .stroke(Theme.ink.opacity(on ? 1 : VendorsView.shades[min(i, 5)] * (selected == nil ? 1 : 0.28)),
                                style: StrokeStyle(lineWidth: on ? line + 5 : line, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                        .padding(line / 2 + 3)
                }
                if let s = selected, let v = slices.first(where: { $0.name == s })?.value {
                    Text((v / total).formatted(.percent.precision(.fractionLength(0))))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                } else {
                    Text("\(slices.count)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        + Text("\n" + (slices.count == 1 ? "place" : "places")).font(.caption2).foregroundStyle(Theme.muted)
                }
            }
            .multilineTextAlignment(.center)
            .frame(width: side, height: side)
            .contentShape(Circle())
            .onTapGesture { loc in pick(at: loc, side: side) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Share of the month")
        .accessibilityValue(selected ?? "All")
        .accessibilityAdjustableAction { dir in
            let names = slices.map(\.name)
            let i = selected.flatMap { names.firstIndex(of: $0) }
            switch dir {
            case .increment: selected = names[i.map { min($0 + 1, names.count - 1) } ?? 0]
            case .decrement: selected = i.flatMap { $0 > 0 ? names[$0 - 1] : nil }
            @unknown default: break
            }
        }
    }

    private func pick(at loc: CGPoint, side: CGFloat) {
        let dx = loc.x - side / 2, dy = loc.y - side / 2
        let r = (dx * dx + dy * dy).squareRoot()
        guard r > side * 0.28 else { selected = nil; return }          // the middle: back to the total
        var angle = atan2(dy, dx) + .pi / 2                               // 0 at the top, clockwise
        if angle < 0 { angle += 2 * .pi }
        let f = angle / (2 * .pi)
        if let i = spans.firstIndex(where: { f >= $0.start && f < $0.end }) {
            selected = selected == slices[i].name ? nil : slices[i].name
        }
    }
}

/// One place or tag: its total, then every payment grouped by date.
private struct BucketView: View {
    let bucket: VendorsView.Bucket
    let monthTotal: Double
    let month: Date
    @AppStorage("usdRate") private var usdRate = 88.0

    private var days: [(day: Date, txns: [Txn])] {
        Dictionary(grouping: bucket.txns) { Calendar.current.startOfDay(for: $0.date) }
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        let share = monthTotal > 0 ? bucket.total / monthTotal : 0
        ScrollView {
            VStack(spacing: 14) {
                PageHeader(bucket.name)
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Spent in \(Fmt.monthName(month))").font(.footnote.weight(.medium)).foregroundStyle(Theme.muted)
                        Text(Fmt.money(bucket.total.rounded())).font(Theme.serif(34)).foregroundStyle(Theme.ink)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text("\(Fmt.payments(bucket.txns.count)) · \(share.formatted(.percent.precision(.fractionLength(0)))) of the month")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    ShareRing(share: share).frame(width: 76, height: 76)
                }
                .glassCard()

                ForEach(days, id: \.day) { d in
                    VStack(spacing: 8) {
                        SectionLabel(title: d.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) {
                            let spent = d.txns.reduce(0) { $0 + $1.spend(usdRate: usdRate) }
                            if spent > 0 { Text(Fmt.money(spent.rounded())).monospacedDigit() }
                        }
                        TxnListCard(txns: d.txns)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .starryPage()
    }
}

/// A thin ring showing one share, with the percentage in the middle.
private struct ShareRing: View {
    let share: Double

    var body: some View {
        ZStack {
            Circle().stroke(Theme.ink.opacity(0.08), lineWidth: 9)
            Circle().trim(from: 0, to: share).stroke(Theme.ink, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(share.formatted(.percent.precision(.fractionLength(0)))).font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
        }
        .padding(4.5)
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
