import SwiftUI
import SwiftData

struct TxnDetailView: View {
    @Bindable var txn: Txn
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var all: [Txn]
    @Query private var payees: [Payee]
    @State private var newTag = ""
    @State private var saved = false
    @State private var confirmDelete = false
    @State private var showRaw = false
    @State private var showMore = false

    /// Your most used tags. Shown while typing (matching what you type), or when the payment has no tags yet.
    private var suggestions: [String] {
        let typed = newTag.trimmingCharacters(in: .whitespaces).lowercased()
        guard !typed.isEmpty || txn.tags.isEmpty else { return [] }
        var counts: [String: Int] = [:]
        for t in all { for tag in t.tags { counts[tag, default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value }.map(\.key)
            .filter { !txn.tags.contains($0) && (typed.isEmpty || $0.hasPrefix(typed)) }
            .prefix(5).map { $0 }
    }

    private var savedPayee: Payee? {
        let key = Payee.key(for: txn.rawPayee)
        return payees.first { $0.key == key }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                hero
                tagsCard
                noteCard
                moreButton
                if showMore {
                    Group {
                        typeCard
                        nameCard
                        if !txn.items.isEmpty { itemsCard }
                        detailsCard
                        Button("Delete payment", role: .destructive) { confirmDelete = true }
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .animation(.snappy, value: txn.tags)
            .animation(.snappy, value: showRaw)
            .animation(.snappy, value: showMore)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this payment?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete payment", role: .destructive) {
                context.delete(txn)
                dismiss()
            }
        }
    }

    // MARK: Cards

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(txn.vendor.ifEmpty("Payment"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text(txn.date.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
                .font(.subheadline).foregroundStyle(Theme.muted)
                .padding(.top, 2)

            AmountText(value: txn.amount, currency: txn.currency, size: 48,
                       sign: txn.isCredit ? "+" : "",
                       color: txn.isCredit ? Theme.positive : (txn.excluded ? Theme.muted : Theme.ink))
                .strikethrough(txn.excluded)
                .padding(.top, 14)

            if txn.type != .expense || txn.foreignAmount != nil {
                FlowLayout {
                    if txn.type != .expense {
                        Chip(text: txn.type.title, tint: txn.isCredit && !txn.excluded ? Theme.positive : Theme.muted)
                    }
                    if let f = txn.foreignAmount, let c = txn.foreignCurrency {
                        Chip(text: "Charged \(Fmt.money(f, c))")
                    }
                }
                .padding(.top, 12)
            }

            if txn.currency != "INR" {
                Text("No bank SMS matched yet, so totals use an estimated rate.")
                    .font(.footnote).foregroundStyle(Theme.muted)
                    .padding(.top, 10)
            }
        }
        .card()
    }

    private var tagsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader("Tags", "Groups payments in Breakdown")
            FlowLayout {
                ForEach(txn.tags, id: \.self) { tag in
                    TagChip(text: tag) { txn.tags.removeAll { $0 == tag } }
                }
                TextField("New tag", text: $newTag)
                    .font(.subheadline.weight(.medium))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(addTag)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .frame(width: 120)
                    .overlay(Capsule().strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            if !suggestions.isEmpty {
                FlowLayout {
                    ForEach(suggestions, id: \.self) { s in
                        TagChip(text: s, selected: false) { txn.tags.append(s); newTag = "" }
                    }
                }
            }
        }
        .card()
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardHeader("Note", "Just for this payment")
            TextField("e.g. birthday gift for mum", text: $txn.note, axis: .vertical)
                .lineLimit(1...5)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .card()
    }

    /// Rename the payment; for bank SMS payments, optionally remember the name for this payee.
    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardTitle("Name")
            TextField("Who you paid", text: $txn.vendor)
                .foregroundStyle(Theme.ink)
                .submitLabel(.done)
                .padding(.horizontal, 14).frame(minHeight: 46)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if !txn.rawPayee.isEmpty && txn.hasSMS {
                Text("Bank shows \(txn.rawPayee)")
                    .font(.footnote).foregroundStyle(Theme.muted)
                    .padding(.top, 2)
                if saved {
                    Label("Past and future payments to this payee will be called “\(txn.vendor)”.", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.medium)).foregroundStyle(Theme.positive)
                        .padding(.top, 4)
                } else if savedPayee?.name != txn.vendor {
                    Button { rememberPayee() } label: {
                        Text("Always call this payee “\(txn.vendor)”")
                            .lineLimit(1)
                    }
                    .buttonStyle(SmallPillStyle())
                    .padding(.top, 4)
                }
            }
        }
        .card()
    }

    private var itemsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("On the receipt").padding(.bottom, 4)
            ForEach(Array(txn.items.enumerated()), id: \.offset) { i, item in
                if i > 0 { Divider().overlay(Theme.line) }
                detailRow(item.name, Fmt.money(item.price, txn.foreignCurrency ?? txn.currency))
            }
        }
        .card()
    }

    private var moreButton: some View {
        Button { showMore.toggle() } label: {
            HStack {
                Text(showMore ? "Fewer details" : "More details")
                Spacer()
                Image(systemName: "chevron.down").rotationEffect(.degrees(showMore ? 180 : 0))
            }
            .font(.body.weight(.medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 20)
            .frame(minHeight: 56)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One choice instead of separate switches, so there are no confusing combinations.
    private var typeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("Type").padding(.bottom, 4)
            ForEach(Array(TxnType.allCases.enumerated()), id: \.element) { i, kind in
                if i > 0 { Divider().overlay(Theme.line) }
                Button { withAnimation(.snappy) { txn.type = kind } } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                            Text(kind.hint).font(.footnote).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: txn.type == kind ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(txn.type == kind ? Theme.accent : Theme.line)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(txn.type == kind ? .isSelected : [])
            }
        }
        .card()
        .sensoryFeedback(.selection, trigger: txn.type)
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("Details").padding(.bottom, 4)
            HStack {
                Text("When").foregroundStyle(Theme.muted)
                Spacer()
                DatePicker("When", selection: $txn.date).labelsHidden()
            }
            .font(.subheadline)
            .padding(.vertical, 6)
            Divider().overlay(Theme.line)
            detailRow("Paid with", txn.method.ifEmpty("Manual"))
            if let a = txn.account { Divider().overlay(Theme.line); detailRow("Account", a) }
            if let r = txn.ref { Divider().overlay(Theme.line); detailRow("Reference", r) }
            Divider().overlay(Theme.line)
            detailRow("Logged from", sourceText)
            if !txn.rawMessages.isEmpty {
                Divider().overlay(Theme.line)
                Button { showRaw.toggle() } label: {
                    HStack {
                        Text(txn.rawMessages.count == 1 ? "Original message" : "Original messages")
                        Spacer()
                        Image(systemName: "chevron.down").rotationEffect(.degrees(showRaw ? 180 : 0))
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if showRaw {
                    ForEach(Array(txn.rawMessages.enumerated()), id: \.offset) { _, raw in
                        Text(raw)
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.bottom, 8)
                    }
                }
            }
        }
        .card()
    }

    // MARK: Pieces

    private func cardTitle(_ s: String) -> some View {
        Text(s).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
    }

    private func cardHeader(_ title: String, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
            Text(hint).font(.footnote).foregroundStyle(Theme.muted)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Theme.muted)
            Spacer(minLength: 16)
            Text(value).foregroundStyle(Theme.ink).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.subheadline)
        .padding(.vertical, 12)
    }

    private var sourceText: String {
        var parts: [String] = []
        if txn.hasSMS { parts.append("SMS") }
        if txn.hasEmail { parts.append("Email") }
        return parts.isEmpty ? "Added by hand" : parts.joined(separator: " + ")
    }

    private func addTag() {
        let t = newTag.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "#", with: "")
        if !t.isEmpty, !txn.tags.contains(t) { txn.tags.append(t) }
        newTag = ""
    }

    private func rememberPayee() {
        let key = Payee.key(for: txn.rawPayee)
        let tag = txn.tags.first ?? ""
        if let p = savedPayee {
            p.name = txn.vendor
            if !tag.isEmpty { p.defaultTag = tag }
        } else {
            context.insert(Payee(key: key, name: txn.vendor, defaultTag: tag))
        }
        for t in all where Payee.key(for: t.rawPayee) == key {
            t.vendor = txn.vendor
            if !tag.isEmpty, !t.tags.contains(tag) { t.tags.append(tag) }
        }
        try? context.save()
        saved = true
    }
}

/// Lays children out left to right, wrapping to a new line when the row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            maxX = max(maxX, x - spacing)
            rowH = max(rowH, s.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
