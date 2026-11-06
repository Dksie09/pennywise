import SwiftUI
import SwiftData

struct AddView: View {
    @Environment(\.modelContext) private var context
    @State private var text = ""
    @State private var result: String?
    @State private var amount = ""
    @State private var vendor = ""
    @State private var date = Date()
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                        .font(.callout)
                        .focused($focused)
                    Button("Add from message") {
                        result = Ingestor.ingest(text, context: context).summary
                        text = ""
                        focused = false
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let result { Text(result).font(.callout).foregroundStyle(.secondary) }
                } header: {
                    Text("Paste a bank SMS or receipt")
                } footer: {
                    Text("Use this for anything the automation missed. Pasting the same message twice won't double count.")
                }

                Section("Or add by hand (cash etc.)") {
                    TextField("Amount (₹)", text: $amount).keyboardType(.decimalPad)
                    TextField("Paid to", text: $vendor)
                    DatePicker("When", selection: $date)
                    Button("Add") {
                        guard let a = Double(amount.replacingOccurrences(of: ",", with: "")), a > 0 else { return }
                        let name = vendor.trimmingCharacters(in: .whitespaces).ifEmpty("Cash")
                        context.insert(Txn(date: date, amount: a, vendor: name, method: "Manual"))
                        try? context.save()
                        result = "Logged \(Fmt.money(a)) · \(name)"
                        amount = ""; vendor = ""; date = Date()
                        focused = false
                    }
                    .disabled(Double(amount) == nil)
                }

                Section("Try it with a sample") {
                    ForEach(Samples.all, id: \.0) { name, body in
                        Button(name) { text = body }
                    }
                }
            }
            .navigationTitle("Add")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

enum Samples {
    static let all: [(String, String)] = [
        ("UPI · Zepto", """
        Dr INR 139.00 - AU A/c X6977 06-NOV-2026
        UPI/DR/617601834096/ZEPTO MARKETPLACE
        Bal INR 49,774.79
        Fraud? Call 180012001200/SMS BLOCK UPI to 5676767
        """),
        ("Card · Anthropic", """
        Dr INR 2,399.00 - AU A/c X6977 06-NOV-2026
        VIE-6754-356/239900-ANTHROPIC* CLAUDE SU
        Bal INR 47,375.79
        Fraud? Call 180012001200/SMS BLOCK <CUSTID> to 5676767
        """),
        ("Receipt email · HeyGen", """
        Your receipt from HeyGen Technology Inc. #2663-1049
        Receipt from HeyGen Technology Inc.
        $29.00
        Paid June 15, 2026
        """),
    ]
}
