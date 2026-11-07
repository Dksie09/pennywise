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

    private var suggestions: [String] {
        var counts: [String: Int] = [:]
        for t in all { for tag in t.tags { counts[tag, default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value }.map(\.key).filter { !txn.tags.contains($0) }.prefix(10).map { $0 }
    }

    private var savedPayee: Payee? {
        let key = Payee.key(for: txn.rawPayee)
        return payees.first { $0.key == key }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text((txn.isCredit ? "+" : "") + Fmt.money(txn.amount, txn.currency))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    if let f = txn.foreignAmount, let c = txn.foreignCurrency {
                        Text("Charged \(Fmt.money(f, c))").foregroundStyle(.secondary)
                    }
                    if txn.currency != "INR" {
                        Text("No bank SMS matched yet, so totals use an estimated rate.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                DatePicker("Date", selection: $txn.date)
            }

            Section {
                TextField("Name", text: $txn.vendor)
                if !txn.rawPayee.isEmpty && txn.hasSMS {
                    Text("Bank shows: \(txn.rawPayee)").font(.caption).foregroundStyle(.secondary)
                    Button(savedPayee == nil ? "Always call this payee “\(txn.vendor)”" : "Update saved name") {
                        rememberPayee()
                    }
                    if saved { Text("Saved. Past and future payments to this payee use this name.").font(.caption).foregroundStyle(.green) }
                }
            } header: { Text("Paid to") }

            Section("Tags") {
                if !txn.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(txn.tags, id: \.self) { tag in TagChip(text: tag) { txn.tags.removeAll { $0 == tag } } } }
                    }
                }
                TextField("Add tag (e.g. grocery, shoes)", text: $newTag)
                    .textInputAutocapitalization(.never)
                    .onSubmit(addTag)
                if !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(suggestions, id: \.self) { s in TagChip(text: s, selected: false) { txn.tags.append(s) } } }
                    }
                }
            }

            Section("Note") {
                TextField("What was it for?", text: $txn.note, axis: .vertical)
            }

            if !txn.items.isEmpty {
                Section("Items (from receipt)") {
                    ForEach(txn.items, id: \.self) { item in
                        LabeledContent(item.name, value: Fmt.money(item.price, txn.foreignCurrency ?? txn.currency))
                    }
                }
            }

            Section {
                Toggle("Money received (refund / income)", isOn: $txn.isCredit)
                Toggle("Don't count in totals", isOn: $txn.excluded)
            } footer: {
                Text("Use “Don't count” for transfers to your own accounts, investments, etc.")
            }

            Section("Details") {
                LabeledContent("Method", value: txn.method)
                if let a = txn.account { LabeledContent("Account", value: a) }
                if let r = txn.ref { LabeledContent("Reference", value: r) }
                LabeledContent("Source", value: sourceText)
                ForEach(Array(txn.rawMessages.enumerated()), id: \.offset) { i, raw in
                    DisclosureGroup("Original message \(i + 1)") {
                        Text(raw).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }

            Section {
                Button("Delete payment", role: .destructive) {
                    context.delete(txn)
                    dismiss()
                }
            }
        }
        .navigationTitle(txn.vendor)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sourceText: String {
        var parts: [String] = []
        if txn.hasSMS { parts.append("SMS") }
        if txn.hasEmail { parts.append("Email") }
        return parts.isEmpty ? "Manual" : parts.joined(separator: " + ")
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

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
