import SwiftUI
import SwiftData

/// Add a payment the automation missed. Default: paste a bank SMS or receipt.
/// Second tab: by hand, with the amount on a built-in keypad and one tap for who (and, optionally, a tag).
struct AddView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Txn.date, order: .reverse) private var all: [Txn]

    @State private var byHand = false
    @State private var message = ""
    @FocusState private var messageFocused: Bool
    @State private var digits = ""              // as typed, e.g. "240.5"
    @State private var payee = ""               // the chosen place ("" = none yet)
    @State private var newPayee = ""
    @State private var typingPayee = false
    @State private var tags: [String] = []
    @State private var newTag = ""
    @State private var typingTag = false
    @State private var date = Date()
    @State private var pickingDate = false
    @State private var pasteMessage: String?    // a pasted message that couldn't be logged
    @State private var logged: Txn?
    @State private var editing: Txn?
    @State private var detent: PresentationDetent = .large
    @FocusState private var field: Field?
    enum Field { case payee, tag }

    private var amount: Double? { Double(digits).flatMap { $0 > 0 ? $0 : nil } }

    /// Places to offer: the one picked or typed first, then recent places (newest first).
    /// While a new name is being typed, they narrow down to matches, in place.
    private var placeOptions: [String] {
        let typed = typingPayee ? newPayee.trimmingCharacters(in: .whitespaces).lowercased() : ""
        var seen = Set<String>(), out: [String] = []
        if !payee.isEmpty { seen.insert(payee); out.append(payee) }
        for t in all where !t.isCredit && !t.vendor.isEmpty && seen.insert(t.vendor).inserted {
            if typed.isEmpty || t.vendor.lowercased().contains(typed) { out.append(t.vendor) }
            if out.count == 8 { break }
        }
        return out
    }

    /// Tags to offer: ones already picked (including new ones), then your most used.
    private var tagOptions: [String] {
        var counts: [String: Int] = [:]
        for t in all { for tag in t.tags { counts[tag, default: 0] += 1 } }
        let recent = counts.sorted { $0.value > $1.value }.prefix(8).map(\.key)
        return tags.filter { !recent.contains($0) } + recent
    }

    var body: some View {
        NavigationStack {
            Group {
                if let logged {
                    TuckedAway(txn: logged, edit: { editing = logged }, done: { dismiss() })
                        .transition(.opacity.combined(with: .scale(0.97)))
                } else {
                    entry
                }
            }
            .animation(.snappy, value: logged)
            .onChange(of: logged) { detent = logged == nil ? .large : .medium }
            .navigationDestination(item: $editing) { TxnDetailView(txn: $0, startEditing: true) }
        }
        .tint(Theme.accent)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.radius + 10)
        .sheet(isPresented: $pickingDate) { DateSheet(date: $date) }
    }

    // MARK: Entry

    private var entry: some View {
        VStack(spacing: 0) {
            topBar
            SegmentedPill(left: "Paste message", right: "By hand", isRight: $byHand)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            if byHand {
                // A non-scrolling scroll view: the keyboard just covers the keypad instead of
                // shifting the whole drawer up while a name or tag is typed.
                GeometryReader { g in
                    ScrollView {
                        manualEntry.frame(minHeight: g.size.height)
                    }
                    .scrollDisabled(true)
                    .scrollBounceBehavior(.basedOnSize)
                }
            } else {
                messageEntry
            }
        }
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Theme.card
                DrawerGlow()
            }
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
        .animation(.snappy, value: byHand)
        .onChange(of: byHand) { pasteMessage = nil; messageFocused = false; field = nil }
    }

    // MARK: Paste a message

    private var messageEntry: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Copy a bank SMS or receipt email, then tap Paste. The same message twice is never counted twice.")
                .font(.subheadline).foregroundStyle(Theme.muted)
                .padding(.top, 22)

            TextField("Or paste / type the message here", text: $message, axis: .vertical)
                .font(.callout.monospaced())
                .foregroundStyle(Theme.ink)
                .lineLimit(7...12)
                .focused($messageFocused)
                .padding(14)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.top, 16)

            if let pasteMessage {
                Label(pasteMessage, systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(Theme.muted)
                    .padding(.top, 12)
            }

            Spacer(minLength: 16)

            if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: pasteAndAdd) {
                    Text("Paste & add").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pill)
            } else {
                HStack(spacing: 10) {
                    Button("Clear") { message = ""; pasteMessage = nil }
                        .buttonStyle(.pillLight)
                    Button { addMessage(message) } label: {
                        Text("Add from message").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pill)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func pasteAndAdd() {
        guard let text = UIPasteboard.general.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            pasteMessage = "Nothing to paste. Copy a bank SMS or receipt first."
            return
        }
        message = text
        addMessage(text)
    }

    private func addMessage(_ text: String) {
        messageFocused = false
        let r = Ingestor.ingest(text, context: context)
        if let t = r.txn {
            message = ""
            pasteMessage = nil
            logged = t
        } else {
            pasteMessage = r.status == .unrecognized ? "That doesn’t look like a bank SMS or receipt." : r.summary
        }
    }

    // MARK: By hand

    private var manualEntry: some View {
        VStack(spacing: 0) {
            amountDisplay.padding(.top, 26)
            Button { pickingDate = true } label: {
                HStack(spacing: 5) {
                    Text(dateLabel)
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12).frame(height: 32)
                .background(Theme.fill, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
            .accessibilityLabel("When: \(dateLabel)")

            VStack(alignment: .leading, spacing: 10) {
                label("Paid to")
                chipRow {
                    if typingPayee {
                        TextField("Name", text: $newPayee)
                            .font(.subheadline)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .focused($field, equals: .payee)
                            .onSubmit(commitPayee)
                            .padding(.horizontal, 15).frame(width: 150, height: 38)
                            .background(Capsule().strokeBorder(Theme.ink, lineWidth: 1.5))
                    } else {
                        ChoiceChip(title: "+ New", dashed: true) {
                            typingPayee = true
                            field = .payee
                        }
                    }
                    ForEach(placeOptions, id: \.self) { p in
                        ChoiceChip(title: p, selected: payee == p) {
                            if typingPayee { newPayee = ""; typingPayee = false; field = nil }
                            payee = payee == p ? "" : p
                        }
                    }
                }

                HStack(spacing: 4) {
                    label("Tags")
                    Text("· optional").font(.footnote).foregroundStyle(Theme.faint)
                }
                chipRow {
                    if typingTag {
                        TextField("New tag", text: $newTag)
                            .font(.subheadline)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($field, equals: .tag)
                            .onSubmit(commitTag)
                            .padding(.horizontal, 15).frame(width: 130, height: 38)
                            .background(Capsule().strokeBorder(Theme.ink, lineWidth: 1.5))
                    } else {
                        ChoiceChip(title: "+ New", dashed: true) {
                            typingTag = true
                            field = .tag
                        }
                    }
                    ForEach(tagOptions, id: \.self) { t in
                        ChoiceChip(title: t, selected: tags.contains(t)) {
                            if tags.contains(t) { tags.removeAll { $0 == t } } else { tags.append(t) }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)

            Spacer(minLength: 12)

            AmountKeypad(digits: $digits)
                .padding(.horizontal, 28)

            Button(action: add) {
                Text(amount.map { "Add \(Fmt.money($0))" } ?? "Add payment").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill)
            .disabled(amount == nil)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .onChange(of: field) { old, new in
            // Leaving a field keeps what was typed, like pressing return.
            if old == .tag && new != .tag { commitTag() }
            if old == .payee && new != .payee { commitPayee() }
        }
    }

    private var topBar: some View {
        ZStack {
            Text("New payment").font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Theme.muted)
                    .frame(minHeight: 44)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var amountDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("₹").font(.system(size: 32, weight: .light)).foregroundStyle(Theme.faint)
            Text(displayAmount)
                .font(.system(size: 76, weight: .medium))
                .tracking(-3.5)
                .monospacedDigit()
                .foregroundStyle(digits.isEmpty ? Theme.faint.opacity(0.45) : Theme.ink)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            BlinkingCaret().frame(width: 2, height: 58).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
        }
        .padding(.horizontal, 24)
        .animation(.snappy(duration: 0.18), value: digits)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Amount")
        .accessibilityValue(digits.isEmpty ? "zero" : Fmt.money(Double(digits) ?? 0))
    }

    /// "1240.5" -> "1,240.5" (Indian grouping), keeping what was typed after the point.
    private var displayAmount: String {
        guard !digits.isEmpty else { return "0" }
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        let whole = Int(parts[0]).map { $0.formatted(.number.locale(Locale(identifier: "en_IN"))) } ?? "0"
        return parts.count > 1 ? "\(whole).\(parts[1])" : whole
    }

    private var dateLabel: String {
        "\(Fmt.dayTitle(date)), \(date.formatted(date: .omitted, time: .shortened))"
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.footnote.weight(.medium)).foregroundStyle(Theme.muted)
    }

    private func chipRow<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content() }.padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
    }

    // MARK: Actions

    private func commitPayee() {
        let name = newPayee.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { payee = name }
        newPayee = ""
        typingPayee = false
    }

    private func commitTag() {
        let t = newTag.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "#", with: "")
        if !t.isEmpty, !tags.contains(t) { tags.append(t) }
        newTag = ""
        typingTag = false
    }

    private func add() {
        guard let a = amount else { return }
        if typingTag { commitTag() }
        if typingPayee { commitPayee() }
        let name = payee.trimmingCharacters(in: .whitespaces).ifEmpty("Cash")
        let t = Txn(date: date, amount: a, vendor: name, method: "Manual")
        t.tags = tags
        context.insert(t)
        try? context.save()
        field = nil
        logged = t
    }
}

/// Calm 3×4 number pad. Long-press ⌫ to clear.
struct AmountKeypad: View {
    @Binding var digits: String
    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: 2) {
            ForEach(keys, id: \.self) { k in
                Button { press(k) } label: {
                    Group {
                        if k == "⌫" { Image(systemName: "delete.left").font(.system(size: 22)) }
                        else { Text(k).font(.system(size: 28)) }
                    }
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .contentShape(Rectangle())
                }
                .buttonStyle(KeyStyle())
                .accessibilityLabel(k == "⌫" ? "Delete" : k == "." ? "Point" : k)
                .simultaneousGesture(LongPressGesture().onEnded { _ in if k == "⌫" { digits = "" } })
            }
        }
        .sensoryFeedback(.selection, trigger: digits)
    }

    private func press(_ k: String) {
        switch k {
        case "⌫":
            if !digits.isEmpty { digits.removeLast() }
        case ".":
            if !digits.contains(".") { digits = (digits.isEmpty ? "0" : digits) + "." }
        default:
            if let dot = digits.firstIndex(of: ".") {
                guard digits[dot...].count <= 2 else { return }      // two decimals at most
            } else {
                guard digits.count < 7 else { return }               // up to ₹99,99,999
                if digits == "0" { digits = "" }
            }
            digits += k
        }
    }
}

private struct KeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(Theme.fill).frame(width: 64, height: 64).opacity(configuration.isPressed ? 1 : 0))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct BlinkingCaret: View {
    @State private var on = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Theme.accent)
            .opacity(on ? 1 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.55).repeatForever()) { on = false }
            }
            .accessibilityHidden(true)
    }
}

/// Pick a date and time for the payment.
private struct DateSheet: View {
    @Binding var date: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("When").font(.body.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.fontWeight(.semibold)
            }
            .padding(.horizontal, 20).padding(.top, 20)
            DatePicker("When", selection: $date, in: ...Date())
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(.horizontal, 12)
        }
        .tint(Theme.accent)
        .presentationDetents([.height(560)])
        .presentationCornerRadius(Theme.radius + 10)
    }
}

/// Shown after a payment is added: Penny drops the coin into her bag and ties it shut (plays once).
private struct TuckedAway: View {
    let txn: Txn
    let edit: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            ZStack {
                PennyAnimation(clip: .bag, height: 120)
                Image(systemName: "sparkle").font(.system(size: 12)).foregroundStyle(Theme.starGold).offset(x: -70, y: -40)
                Image(systemName: "sparkle").font(.system(size: 9)).foregroundStyle(Theme.glowBlue).offset(x: 66, y: -52)
            }
            Text("Tucked away")
                .font(Theme.serif(30)).foregroundStyle(Theme.ink)
                .padding(.top, 14)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                AmountText(value: txn.amount, currency: txn.currency, size: 18, sign: txn.isCredit ? "+" : "")
                Text(detail).font(.subheadline).foregroundStyle(Theme.muted).lineLimit(1)
            }
            .padding(.top, 4)
            Spacer(minLength: 24)
            HStack(spacing: 10) {
                Button(action: edit) { Text("Edit").frame(maxWidth: .infinity) }
                    .buttonStyle(.pillLight)
                    .frame(maxWidth: .infinity)
                Button(action: done) { Text("Done").frame(maxWidth: .infinity) }
                    .buttonStyle(.pill)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.card.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: txn.id)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var detail: String {
        let to = txn.isCredit ? "from" : "to"
        return (["\(to) \(txn.vendor)"] + txn.tags.prefix(1)).joined(separator: " · ")
    }
}
