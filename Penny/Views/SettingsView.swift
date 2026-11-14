import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Payee.name) private var payees: [Payee]
    @Query(sort: \Txn.date) private var all: [Txn]
    @AppStorage("usdRate") private var usdRate = 88.0
    @State private var confirmWipe = false
    @AppStorage(TagMemory.settingKey) private var rememberTags = true
    @State private var confirmPast = false
    @State private var pastResult: Int?

    var body: some View {
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

            Section {
                Toggle("Remember tags for each place", isOn: $rememberTags)
                    .tint(Theme.accent)
                Button("Tag past payments too") { confirmPast = true }
                    .disabled(!rememberTags)
            } header: { Text("Tags") } footer: {
                Text("When you tag a payment, its place's new payments get the same tags. The latest tags you choose for a place are the ones used. “Tag past payments too” gives untagged past payments their place's tags; anything you've tagged stays as it is.")
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
        .pennyBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Tag past payments?", isPresented: $confirmPast, titleVisibility: .visible) {
            Button("Tag past payments") { pastResult = TagMemory.applyToPast(context: context) }
        } message: {
            Text("Untagged past payments get the tags remembered for their place. Payments you've tagged stay as they are.")
        }
        .alert(pastResult == 0 ? "Nothing to tag" : "Done", isPresented: Binding(get: { pastResult != nil }, set: { if !$0 { pastResult = nil } })) {
            Button("OK") { pastResult = nil }
        } message: {
            Text(pastResult.map { $0 == 0 ? "Every past payment with a remembered place already has tags." : "Tagged \($0) past payment\($0 == 1 ? "" : "s")." } ?? "")
        }
        .confirmationDialog("Delete all payments and saved payees?", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                try? context.delete(model: Txn.self)
                try? context.delete(model: Payee.self)
                try? context.save()
            }
        }
    }
}

struct PayeeEditView: View {
    @Bindable var payee: Payee
    @Query private var all: [Txn]
    @Environment(\.modelContext) private var context
    @State private var tagsText = ""

    var body: some View {
        Form {
            Section("Bank shows") { Text(payee.key).foregroundStyle(.secondary) }
            Section("Call it") { TextField("Name", text: $payee.name) }
            Section {
                TextField("e.g. grocery, food", text: $tagsText).textInputAutocapitalization(.never)
            } header: { Text("Tags for new payments") } footer: {
                Text("Separate tags with commas. Tagging one of its payments also updates this.")
            }
        }
        .pennyBackground()
        .navigationTitle(payee.name)
        .onAppear {
            let remembered = TagMemory.tags(for: payee.name, context: context)
            tagsText = (remembered ?? (payee.defaultTag.isEmpty ? [] : [payee.defaultTag])).joined(separator: ", ")
        }
        .onDisappear {
            for t in all where Payee.key(for: t.rawPayee) == payee.key { t.vendor = payee.name }
            let tags = tagsText.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "#", with: "") }
                .filter { !$0.isEmpty }
            let key = PlaceTags.key(for: payee.name)
            let d = FetchDescriptor<PlaceTags>(predicate: #Predicate { $0.key == key })
            if let memory = try? context.fetch(d).first { memory.tags = tags }
            else if !tags.isEmpty { context.insert(PlaceTags(key: key, tags: tags)) }
            try? context.save()
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
             t.isCredit ? "in" : "out", t.excluded ? "yes" : "no", t.type.rawValue, esc(t.tags.joined(separator: " ")), esc(t.note), t.method]
                .joined(separator: ",")
        }
        return (["date,vendor,amount,currency,direction,excluded,type,tags,note,method"] + rows).joined(separator: "\n")
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
                step("Next → New Blank Automation → add action “Log Expense Message” (Pennywise).")
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
        .pennyBackground()
        .navigationTitle("Automation setup")
    }

    private func step(_ s: String) -> some View { Text(s).font(.callout) }
}
