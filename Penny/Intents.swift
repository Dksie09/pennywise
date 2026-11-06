import AppIntents

/// The action your iPhone Shortcuts automation calls with the SMS / email text.
/// Runs in the background; the app does not open.
struct LogMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Expense Message"
    static var description = IntentDescription("Reads a bank SMS or receipt email and logs the payment in Penny. Duplicates are ignored automatically.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Message", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$text) in Penny")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let result = Ingestor.ingest(text, context: Store.container.mainContext)
        return .result(value: result.summary)
    }
}

struct PennyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogMessageIntent(),
            phrases: ["Log expense in \(.applicationName)"],
            shortTitle: "Log Expense",
            systemImageName: "indianrupeesign.circle"
        )
    }
}
