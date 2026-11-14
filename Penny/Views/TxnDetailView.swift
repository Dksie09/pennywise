import SwiftUI
import SwiftData

/// One payment, in a drawer. Reads like a receipt: who, how much, when; then tags, note and type.
/// "Edit" turns the same layout editable in place; nothing changes until Save.
struct TxnDetailView: View {
    @Bindable var txn: Txn
    /// Open straight into editing (from "Tucked away → Edit"); Save or Cancel then closes.
    var startEditing = false

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var all: [Txn]
    @Query private var payees: [Payee]

    @State private var editing = false
    @State private var draft = Draft()
    @State private var newTag = ""
    @State private var confirmDelete = false
    @State private var showDetails = false
    @State private var showRaw = false
    @State private var payeeSaved = false
    @FocusState private var focus: Field?

    enum Field { case name, amount, tag, note }

    struct Draft {
        var name = ""
        var amount = ""
        var date = Date()
        var tags: [String] = []
        var note = ""
        var type: TxnType = .expense
        var renameAll = false
    }

    private var savedPayee: Payee? {
        let key = Payee.key(for: txn.rawPayee)
        return payees.first { $0.key == key }
    }
    private var canRenamePayee: Bool { txn.hasSMS && !txn.rawPayee.isEmpty }
    private var draftAmount: Double? {
        Double(draft.amount.replacingOccurrences(of: ",", with: "")).flatMap { $0 > 0 ? $0 : nil }
    }
    private var canSave: Bool { !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && draftAmount != nil }

    /// Your most used tags not already on this payment, matching what's being typed.
    private var suggestions: [String] {
        let typed = newTag.trimmingCharacters(in: .whitespaces).lowercased()
        var counts: [String: Int] = [:]
        for t in all { for tag in t.tags { counts[tag, default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value }.map(\.key)
            .filter { !draft.tags.contains($0) && (typed.isEmpty || $0.hasPrefix(typed)) }
            .prefix(4).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                topBar
                Group { if editing { editHero } else { viewHero } }
                    .padding(.top, 4)
                detailsCard.padding(.top, 28)
                if !txn.items.isEmpty { itemsCard.padding(.top, 12) }
                if !editing {
                    if canRenamePayee { payeeCard.padding(.top, 12) }
                    moreDetails.padding(.top, 12)
                    Button("Delete payment", role: .destructive) { confirmDelete = true }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(hex: 0xD93B40))
                        .frame(minHeight: 44)
                        .padding(.top, 18)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .animation(.snappy, value: editing)
            .animation(.snappy, value: draft.tags)
            .animation(.snappy, value: showDetails)
            .animation(.snappy, value: showRaw)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Theme.bg
                DrawerGlow()
            }
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
        .interactiveDismissDisabled(editing)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.radius + 10)
        .onAppear { if startEditing && !editing { beginEditing() } }
        .confirmationDialog("Delete this payment?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete payment", role: .destructive) {
                context.delete(txn)
                try? context.save()
                dismiss()
            }
        }
    }

    // MARK: Top

    private var topBar: some View {
        HStack {
            if editing {
                Button("Cancel", action: cancel).foregroundStyle(Theme.muted)
                Spacer()
                Button("Save", action: save)
                    .buttonStyle(SaveButtonStyle())
                    .disabled(!canSave)
            } else {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(CircleButtonStyle(size: 36, background: Theme.card))
                    .accessibilityLabel("Back")
                Spacer()
                Button("Edit") { beginEditing() }
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 4)
        .padding(.top, 14)
    }

    private var viewHero: some View {
        VStack(spacing: 0) {
            Text(txn.vendor.ifEmpty("Payment"))
                .font(Theme.serif(32)).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            AmountText(value: txn.amount, currency: txn.currency, size: 64,
                       sign: txn.isCredit ? "+" : "",
                       color: txn.isCredit ? Theme.positive : (txn.excluded ? Theme.muted : Theme.ink))
                .strikethrough(txn.excluded)
                .padding(.top, 6)
            Text(subline).font(.subheadline).foregroundStyle(Theme.muted).padding(.top, 8)
            if let f = txn.foreignAmount, let c = txn.foreignCurrency {
                Chip(text: "Charged \(Fmt.money(f, c))").padding(.top, 10)
            }
            if txn.currency != "INR" {
                Text("No bank SMS matched yet, so totals use an estimated rate.")
                    .font(.footnote).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center).padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var editHero: some View {
        VStack(spacing: 0) {
            TextField("Paid to", text: $draft.name)
                .font(Theme.serif(32)).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .focused($focus, equals: .name)
                .submitLabel(.next)
                .onSubmit { focus = .amount }
                .padding(.bottom, 4)
                .overlay(alignment: .bottom) {
                    DashedLine().stroke(Color(hex: 0xCFCDD8), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])).frame(height: 1.5)
                }
                .frame(maxWidth: 260)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Fmt.parts(Fmt.money(0, txn.currency)).symbol)
                    .font(.system(size: 28, weight: .light)).foregroundStyle(Theme.faint)
                TextField("0", text: $draft.amount)
                    .font(.system(size: 64, weight: .medium)).tracking(-2.8)
                    .monospacedDigit()
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .amount)
                    .fixedSize()
            }
            .padding(.horizontal, 16).padding(.vertical, 2)
            .background(Color(hex: 0xEEF0FF), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .bottom) {
                Capsule().fill(Theme.accent).frame(height: 2).padding(.horizontal, 10)
                    .opacity(focus == .amount ? 1 : 0)
            }
            .onTapGesture { focus = .amount }
            .padding(.top, 12)

            DatePicker("When", selection: $draft.date, in: ...Date())
                .labelsHidden()
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
    }

    private var subline: String {
        let day = txn.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let time = txn.date.formatted(date: .omitted, time: .shortened)
        let via = txn.method == "Manual" || txn.method.isEmpty ? nil : txn.method
        return ([day, time] + (via.map { [$0] } ?? [])).joined(separator: " · ")
    }

    // MARK: Details

    private var detailsCard: some View {
        VStack(spacing: 0) {
            tagsRow
            Divider().overlay(Theme.line)
            noteRow
            Divider().overlay(Theme.line)
            typeRow
            if editing && canRenamePayee {
                Divider().overlay(Theme.line)
                Toggle(isOn: $draft.renameAll) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Always call it \(draft.name.ifEmpty("this"))").font(.subheadline).foregroundStyle(Theme.ink)
                        Text("Bank shows \(txn.rawPayee)").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                .tint(Theme.accent)
                .frame(minHeight: 64)
            }
        }
        .padding(.horizontal, 18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Theme.shadow.opacity(0.05), radius: 14, y: 6)
    }

    @ViewBuilder private var tagsRow: some View {
        if editing {
            VStack(alignment: .leading, spacing: 10) {
                rowLabel("Tags")
                FlowLayout(spacing: 6) {
                    ForEach(draft.tags, id: \.self) { tag in
                        TagChip(text: tag) { draft.tags.removeAll { $0 == tag } }
                    }
                    TextField("Add tag", text: $newTag)
                        .font(.subheadline)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focus, equals: .tag)
                        .onSubmit(addDraftTag)
                        .padding(.horizontal, 12).frame(width: 110, height: 32)
                        .overlay(Capsule().strokeBorder(Color(hex: 0xCFCDD8), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    ForEach(suggestions, id: \.self) { s in
                        TagChip(text: s, selected: false) { draft.tags.append(s); newTag = "" }
                    }
                }
            }
            .padding(.vertical, 14)
        } else {
            tappableRow("Tags", focusing: .tag) {
                if txn.tags.isEmpty {
                    Text("Add").foregroundStyle(Theme.faint)
                } else {
                    HStack(spacing: 6) {
                        ForEach(txn.tags.prefix(3), id: \.self) { tag in
                            Text(tag).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                                .padding(.horizontal, 12).frame(height: 30)
                                .background(Theme.ink.opacity(0.06), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var noteRow: some View {
        if editing {
            HStack(alignment: .center, spacing: 16) {
                rowLabel("Note")
                TextField("Add a note", text: $draft.note, axis: .vertical)
                    .lineLimit(1...4)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Theme.ink)
                    .focused($focus, equals: .note)
            }
            .font(.subheadline)
            .padding(.vertical, 18)
        } else {
            tappableRow("Note", focusing: .note) {
                Text(txn.note.ifEmpty("Add a note"))
                    .foregroundStyle(txn.note.isEmpty ? Theme.faint : Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    @ViewBuilder private var typeRow: some View {
        if editing {
            HStack {
                rowLabel("Counts as")
                Spacer()
                Menu {
                    ForEach(TxnType.allCases) { kind in
                        Button { draft.type = kind } label: {
                            if draft.type == kind { Label(kind.title, systemImage: "checkmark") } else { Text(kind.title) }
                            Text(kind.hint)
                        }
                    }
                } label: { typeValue(draft.type) }
            }
            .frame(minHeight: 56)
        } else {
            tappableRow("Counts as", focusing: nil) { typeValue(txn.type) }
        }
    }

    private func typeValue(_ type: TxnType) -> some View {
        HStack(spacing: 6) {
            Text(type.title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
            Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(Theme.faint)
        }
    }

    /// A read-only row; tapping it switches to editing with that field ready.
    private func tappableRow<V: View>(_ label: String, focusing field: Field?, @ViewBuilder value: () -> V) -> some View {
        Button { beginEditing(focusing: field) } label: {
            HStack(spacing: 16) {
                rowLabel(label)
                Spacer(minLength: 0)
                value().font(.subheadline)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowLabel(_ s: String) -> some View {
        Text(s).font(.subheadline).foregroundStyle(Theme.muted)
    }

    private var itemsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowLabel("On the receipt").padding(.top, 14).padding(.bottom, 2)
            ForEach(Array(txn.items.enumerated()), id: \.offset) { i, item in
                if i > 0 { Divider().overlay(Theme.line) }
                HStack(alignment: .firstTextBaseline) {
                    Text(item.name).foregroundStyle(Theme.ink)
                    Spacer(minLength: 16)
                    Text(Fmt.money(item.price, txn.foreignCurrency ?? txn.currency)).foregroundStyle(Theme.ink)
                }
                .font(.subheadline)
                .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: Payee and details

    /// The name the bank uses, and a one-tap way to always show your name for it instead.
    private var payeeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                rowLabel("Bank shows")
                Spacer(minLength: 0)
                Text(txn.rawPayee).font(.subheadline.monospaced()).foregroundStyle(Theme.ink)
                    .lineLimit(2).multilineTextAlignment(.trailing).textSelection(.enabled)
            }
            if payeeSaved || savedPayee?.name == txn.vendor {
                Label("Past and future payments to this payee are called “\(txn.vendor)”.", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.medium)).foregroundStyle(Theme.positive)
            } else {
                Button {
                    rememberPayee()
                    try? context.save()
                    payeeSaved = true
                } label: {
                    Text(savedPayee == nil ? "Always call this payee “\(txn.vendor)”" : "Update saved name to “\(txn.vendor)”")
                        .lineLimit(1)
                }
                .buttonStyle(SmallPillStyle())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Theme.shadow.opacity(0.05), radius: 14, y: 6)
    }

    /// Where the payment came from: method, account, reference, source and the original message(s).
    private var moreDetails: some View {
        VStack(spacing: 0) {
            Button { showDetails.toggle() } label: {
                HStack {
                    Text("More details").font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(Theme.faint)
                        .rotationEffect(.degrees(showDetails ? 180 : 0))
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showDetails {
                VStack(spacing: 0) {
                    Divider().overlay(Theme.line)
                    infoRow("Paid with", txn.method.ifEmpty("Manual"))
                    if let a = txn.account { Divider().overlay(Theme.line); infoRow("Account", a) }
                    if let r = txn.ref { Divider().overlay(Theme.line); infoRow("Reference", r) }
                    Divider().overlay(Theme.line)
                    infoRow("Logged from", sourceText)
                    if !txn.rawMessages.isEmpty {
                        Divider().overlay(Theme.line)
                        Button { showRaw.toggle() } label: {
                            HStack {
                                Text(txn.rawMessages.count == 1 ? "Original message" : "Original messages")
                                Spacer()
                                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(Theme.faint)
                                    .rotationEffect(.degrees(showRaw ? 180 : 0))
                            }
                            .font(.subheadline).foregroundStyle(Theme.muted)
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if showRaw {
                            ForEach(Array(txn.rawMessages.enumerated()), id: \.offset) { _, raw in
                                Text(raw)
                                    .font(.caption.monospaced()).foregroundStyle(Theme.ink)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .padding(.bottom, 10)
                            }
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Theme.shadow.opacity(0.05), radius: 14, y: 6)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            rowLabel(label)
            Spacer(minLength: 0)
            Text(value).font(.subheadline).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .frame(minHeight: 48)
    }

    private var sourceText: String {
        var parts: [String] = []
        if txn.hasSMS { parts.append("SMS") }
        if txn.hasEmail { parts.append("Email") }
        return parts.isEmpty ? "Added by hand" : parts.joined(separator: " + ")
    }

    // MARK: Editing

    private func beginEditing(focusing field: Field? = nil) {
        draft = Draft(
            name: txn.vendor,
            amount: txn.amount.rounded() == txn.amount ? String(Int(txn.amount)) : String(format: "%.2f", txn.amount),
            date: txn.date,
            tags: txn.tags,
            note: txn.note,
            type: txn.type,
            renameAll: savedPayee != nil
        )
        newTag = ""
        editing = true
        if let field {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                focus = field
            }
        }
    }

    private func cancel() {
        focus = nil
        editing = false
        if startEditing { dismiss() }
    }

    private func save() {
        guard let amount = draftAmount else { return }
        addDraftTag()
        let tagsChanged = draft.tags != txn.tags || draft.name.trimmingCharacters(in: .whitespaces) != txn.vendor
        txn.vendor = draft.name.trimmingCharacters(in: .whitespaces)
        txn.amount = amount
        txn.date = draft.date
        txn.tags = draft.tags
        txn.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if txn.type != draft.type { txn.type = draft.type }
        if draft.renameAll && canRenamePayee { rememberPayee() }
        // The latest tags you give a place are what its future payments get.
        if tagsChanged { TagMemory.remember(txn, context: context) }
        try? context.save()
        focus = nil
        editing = false
        if startEditing { dismiss() }
    }

    private func addDraftTag() {
        let t = newTag.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "#", with: "")
        if !t.isEmpty, !draft.tags.contains(t) { draft.tags.append(t) }
        newTag = ""
    }

    /// Remember this name (and first tag) for the bank's payee, and apply it to past payments too.
    /// Always show your name for this bank payee, on past payments too. Its tags become the place's
    /// remembered tags, and past payments to it that have no tags yet get them.
    private func rememberPayee() {
        let key = Payee.key(for: txn.rawPayee)
        if let p = savedPayee {
            p.name = txn.vendor
        } else {
            context.insert(Payee(key: key, name: txn.vendor))
        }
        for t in all where Payee.key(for: t.rawPayee) == key {
            t.vendor = txn.vendor
            if t.tags.isEmpty { t.tags = txn.tags }
        }
        TagMemory.remember(txn, context: context)
    }
}

/// Small dark "Save" pill.
private struct SaveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.card)
            .padding(.horizontal, 18).frame(height: 36)
            .background(Theme.ink, in: Capsule())
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.3)
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
