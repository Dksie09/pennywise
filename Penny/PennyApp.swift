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
    @State private var router = PageRouter()
    @State private var showSplash = true

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Group {
                    switch router.page {
                    case .home: MonthView(month: $month)
                    case .calendar: NavigationStack { CalendarView(month: $month) }
                    case .breakdown: NavigationStack { VendorsView(month: $month) }
                    }
                }
                .transition(.opacity)

                if router.menuOpen {
                    // Tap anywhere else to close.
                    Color.black.opacity(0.04).ignoresSafeArea()
                        .onTapGesture { withAnimation(.snappy(duration: 0.2)) { router.menuOpen = false } }
                        .transition(.opacity)
                    PageMenu()
                        .padding(.leading, 16)
                        .padding(.top, 60)           // just under the title
                        .transition(.scale(scale: 0.85, anchor: .topLeading).combined(with: .opacity))
                        .zIndex(2)
                }

                if showSplash {
                    SplashView { withAnimation(.easeOut(duration: 0.35)) { showSplash = false } }
                        .transition(.opacity)
                        .zIndex(3)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .sheet(isPresented: Bindable(router).adding) { AddView().environment(router) }
        .sheet(item: Bindable(router).openTxn) { TxnDetailView(txn: $0).environment(router) }
        .environment(router)
        .tint(Theme.accent)
        .preferredColorScheme(.light)
    }
}
