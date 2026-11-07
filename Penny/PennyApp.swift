import SwiftUI
import SwiftData

@main
struct PennyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(Store.container)
    }
}

struct RootView: View {
    @State private var month = Date()

    var body: some View {
        MonthView(month: $month)
    }
}
