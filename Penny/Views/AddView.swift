import SwiftUI
import SwiftData

struct AddView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var result: String?
    @State private var amount = ""
    @State private var vendor = ""
    @State private var date = Date()
    @FocusState private var focus: Field?

    enum Field { case amount, vendor, message }

    private var parsedAmount: Double? {
        Double(amount.replacingOccurrences(of: ",", with: "")).flatMap { $0 > 0 ? $0 : nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    manualCard
                    Button { addManual() } label: { Text("Add payment").frame(maxWidth: .infinity) }
                        .buttonStyle(.pill)
                        .disabled(parsedAmount == nil)

                    if let result {
                        Label(result, systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.ink)
                            .transition(.opacity.combined(with: .scale(0.95)))
                    }

                    pasteCard
                        .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .animation(.snappy, value: result)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Add payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .onAppear { focus = .amount }
        }
        .tint(Theme.accent)
        .presentationCornerRadius(Theme.radius)
    }

    private var manualCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Amount").font(.subheadline.weight(.medium)).foregroundStyle(Theme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("₹").font(.system(size: 30, weight: .medium)).foregroundStyle(Theme.muted)
                TextField("0", text: $amount)
                    .font(.system(size: 52, weight: .medium))
                    .monospacedDigit()
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .amount)
            }
            .padding(.top, 4)

            Divider().overlay(Theme.line).padding(.vertical, 14)
            TextField("Paid to (optional, e.g. chai stall)", text: $vendor)
                .focused($focus, equals: .vendor)
                .submitLabel(.done)
            Divider().overlay(Theme.line).padding(.vertical, 14)
            DatePicker("When", selection: $date, in: ...Date())
                .foregroundStyle(Theme.muted)
        }
        .card()
    }

    private var pasteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Or paste a bank SMS or receipt").font(.headline).foregroundStyle(Theme.ink)
            Text("For anything the automation missed. Pasting the same message twice won’t count it twice.")
                .font(.footnote).foregroundStyle(Theme.muted)

            TextField("Paste message here", text: $text, axis: .vertical)
                .lineLimit(4...8)
                .font(.callout)
                .focused($focus, equals: .message)
                .padding(14)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 10) {
                if text.isEmpty, UIPasteboard.general.hasStrings {
                    Button("Paste") { text = UIPasteboard.general.string ?? "" }
                        .buttonStyle(.pillLight)
                }
                Button {
                    result = Ingestor.ingest(text, context: context).summary
                    text = ""
                    focus = nil
                } label: { Text("Add from message").frame(maxWidth: .infinity) }
                .buttonStyle(.pill)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .card()
    }

    private func addManual() {
        guard let a = parsedAmount else { return }
        let name = vendor.trimmingCharacters(in: .whitespaces).ifEmpty("Cash")
        context.insert(Txn(date: date, amount: a, vendor: name, method: "Manual"))
        try? context.save()
        result = "Logged \(Fmt.money(a)) · \(name)"
        amount = ""; vendor = ""; date = Date()
        focus = nil
    }
}
