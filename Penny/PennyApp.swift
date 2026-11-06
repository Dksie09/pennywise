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
        TabView {
            MonthView(month: $month)
                .tabItem { Label("Month", systemImage: "calendar") }
            VendorsView(month: $month)
                .tabItem { Label("Spending", systemImage: "chart.bar.fill") }
            AddView()
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}
