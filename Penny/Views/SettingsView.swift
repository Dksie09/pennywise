import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Payee.name) private var payees: [Payee]
    @Query(sort: \Txn.date) private var all: [Txn]
    @AppStorage("usdRate") private var usdRate = 88.0
    @State private var confirmWipe = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Automatic logging") {
                    NavigationLink("Set up SMS & email automation") { SetupGuideView() }
                }

                Section {
                    if payees.isEmpty {
                        Text("None yet. Open a payment and tap “Always call this payee…”").foregroundStyle(.secondary)
                    }
                    ForEach(payees) { p in
                        NavigationLink { PayeeEditView(payee: p) } label: {
                            VStack(alignment: .leading) {
                                Text(p.name)
                                Text(p.key).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { idx in idx.forEach { context.delete(payees[$0]) } }
                } header: { Text("Saved payees") }

                Section {
                    HStack {
                        Text("1 USD =")
                        TextField("Rate", value: $usdRate, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        Text("₹")
                    }
                } header: { Text("Currency") } footer: {
                    Text("Only used for foreign receipts that haven't matched a bank SMS yet.")
                }

                Section("Your data") {
                    ShareLink(item: CSVExport(txns: all), preview: SharePreview("penny.csv")) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                    Button("Delete everything", role: .destructive) { confirmWipe = true }
                }

                Section("Privacy") {
                    Text("Everything stays on this iPhone. Penny has no server, no login, no analytics and never connects to the internet. Messages only reach it through the Shortcuts automation you set up.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete all payments and saved payees?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) {
                    try? context.delete(model: Txn.self)
                    try? context.delete(model: Payee.self)
                    try? context.save()
                }
            }
        }
    }
}

struct PayeeEditView: View {
    @Bindable var payee: Payee
    @Query private var all: [Txn]

    var body: some View {
        Form {
            Section("Bank shows") { Text(payee.key).foregroundStyle(.secondary) }
            Section("Call it") { TextField("Name", text: $payee.name) }
            Section("Auto-tag new payments") { TextField("Tag (optional)", text: $payee.defaultTag).textInputAutocapitalization(.never) }
        }
        .navigationTitle(payee.name)
        .onDisappear {
            for t in all where Payee.key(for: t.rawPayee) == payee.key { t.vendor = payee.name }
        }
    }
}

struct CSVExport: Transferable {
    let text: String

    @MainActor init(txns: [Txn]) { text = Self.csv(txns) }

    @MainActor static func csv(_ txns: [Txn]) -> String {
        func esc(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        let iso = ISO8601DateFormatter()
        let rows = txns.map { t in
            [iso.string(from: t.date), esc(t.vendor), String(format: "%.2f", t.amount), t.currency,
             t.isCredit ? "in" : "out", t.excluded ? "yes" : "no", esc(t.tags.joined(separator: " ")), esc(t.note), t.method]
                .joined(separator: ",")
        }
        return (["date,vendor,amount,currency,direction,excluded,tags,note,method"] + rows).joined(separator: "\n")
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { Data($0.text.utf8) }
            .suggestedFileName("penny.csv")
    }
}

struct SetupGuideView: View {
    var body: some View {
        List {
            Section {
                Text("iPhone apps can't read your SMS or Mail directly. Instead, a Shortcuts automation hands each bank SMS / receipt to Penny in the background. Set it up once.")
                    .font(.callout)
            }
            Section("1 · Bank SMS") {
                step("Open Shortcuts → Automation → + → Message.")
                step("Message Contains: “Dr INR”  (add another automation with “Cr INR” for money received).")
                step("Choose “Run Immediately” and turn off “Notify When Run”.")
                step("Next → New Blank Automation → add action “Log Expense Message” (Penny).")
                step("Tap the Message field → choose “Shortcut Input”, then tap it again and pick “Content”.")
            }
            Section("2 · Receipt emails (Apple Mail app)") {
                step("Automation → + → Email. Subject Contains: “receipt” (make more for “invoice”, “order”).")
                step("Run Immediately. New Blank Automation.")
                step("Add “Text” action containing: Shortcut Input › Subject, a new line, then Shortcut Input › Body.")
                step("Add “Log Expense Message” with the Text from the previous step.")
                Text("Gmail users: add your Gmail account in Settings → Apps → Mail so the Mail app receives it.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Duplicates") {
                Text("The same SMS twice, or a receipt plus the bank SMS for the same payment, are merged into one entry automatically (matched by reference, balance, amount, vendor and date).")
                    .font(.callout)
            }
        }
        .navigationTitle("Automation setup")
    }

    private func step(_ s: String) -> some View { Text(s).font(.callout) }
}
