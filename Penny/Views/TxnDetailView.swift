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

    private var suggestions: [String] {
        var counts: [String: Int] = [:]
        for t in all { for tag in t.tags { counts[tag, default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value }.map(\.key).filter { !txn.tags.contains($0) }.prefix(8).map { $0 }
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
                if !txn.rawPayee.isEmpty && txn.hasSMS { payeeCard }
                if !txn.items.isEmpty { itemsCard }
                countingCard
                detailsCard
                Button("Delete payment", role: .destructive) { confirmDelete = true }
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .animation(.snappy, value: txn.tags)
            .animation(.snappy, value: showRaw)
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
            HStack(spacing: 6) {
                TextField("Name", text: $txn.vendor)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .submitLabel(.done)
                Image(systemName: "pencil").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
            }
            Text(txn.date.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
                .font(.subheadline).foregroundStyle(Theme.muted)
                .padding(.top, 2)

            AmountText(value: txn.amount, currency: txn.currency, size: 48,
                       sign: txn.isCredit ? "+" : "",
                       color: txn.isCredit ? Theme.positive : (txn.excluded ? Theme.muted : Theme.ink))
                .strikethrough(txn.excluded)
                .padding(.top, 14)

            FlowLayout {
                Chip(text: txn.method.ifEmpty("Manual"))
                if let f = txn.foreignAmount, let c = txn.foreignCurrency {
                    Chip(text: "Charged \(Fmt.money(f, c))")
                }
                if txn.isCredit { Chip(text: "Money in", tint: Theme.positive) }
                if txn.excluded { Chip(text: "Not counted", tint: Theme.muted) }
            }
            .padding(.top, 12)

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
            cardTitle("Tags")
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
                Text("Recent").font(.footnote).foregroundStyle(Theme.muted).padding(.top, 4)
                FlowLayout {
                    ForEach(suggestions, id: \.self) { s in
                        TagChip(text: s, selected: false) { txn.tags.append(s) }
                    }
                }
            }
        }
        .card()
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardTitle("Note")
            TextField("What was it for?", text: $txn.note, axis: .vertical)
                .lineLimit(1...5)
                .foregroundStyle(Theme.ink)
        }
        .card()
    }

    private var payeeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("Bank shows")
            Text(txn.rawPayee).font(.subheadline.monospaced()).foregroundStyle(Theme.ink)
            if saved {
                Label("Past and future payments to this payee will be called “\(txn.vendor)”.", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.medium)).foregroundStyle(Theme.positive)
            } else {
                Button { rememberPayee() } label: {
                    Text(savedPayee == nil ? "Always call it “\(txn.vendor)”" : "Update saved name to “\(txn.vendor)”")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.fill, in: Capsule())
                }
                .buttonStyle(.plain)
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

    private var countingCard: some View {
        VStack(spacing: 0) {
            toggleRow("Money received", "A refund, or money someone sent you", isOn: $txn.isCredit)
            Divider().overlay(Theme.line).padding(.vertical, 12)
            toggleRow("Don’t count in totals", "For transfers to your own accounts, investments, etc.", isOn: $txn.excluded)
        }
        .card()
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
        Text(s).font(.subheadline.weight(.medium)).foregroundStyle(Theme.muted)
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

    private func toggleRow(_ title: String, _ subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .tint(Theme.accent)
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
