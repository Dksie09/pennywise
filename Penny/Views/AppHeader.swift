import SwiftUI
import Observation

/// The three sibling pages. You move between them from the title at the top ("Penny ⌄").
enum AppPage: String, CaseIterable, Identifiable {
    case home, calendar, breakdown

    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "Penny"
        case .calendar: "Calendar"
        case .breakdown: "Breakdown"
        }
    }
    var icon: String {
        switch self {
        case .home: "house"
        case .calendar: "calendar"
        case .breakdown: "chart.bar.xaxis"
        }
    }
}

/// Which page is showing, whether the page menu is open, and whether the Add sheet is up.
/// The Add sheet lives at the root so a page changing underneath (e.g. the first payment
/// replacing the empty state) can never close it.
@Observable final class PageRouter {
    var page: AppPage = .home
    var menuOpen = false
    var adding = false
    /// The payment open in the drawer. Kept here (not on its row) so editing its date, which can
    /// move it to another day, doesn't close the drawer.
    var openTxn: Txn?

    /// Close the menu first, so the new page's header starts with it closed.
    func go(_ p: AppPage) {
        menuOpen = false
        withAnimation(.easeInOut(duration: 0.22)) { page = p }
    }
}

/// Same on every page: "Title ⌄" on the left (opens the page menu), add and settings on the right.
struct AppHeader: View {
    @Environment(PageRouter.self) private var router

    var body: some View {
        HStack {
            Button { withAnimation(.snappy(duration: 0.22)) { router.menuOpen.toggle() } } label: {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(router.page.title).font(Theme.serif(34)).foregroundStyle(Theme.ink)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.faint)
                        .rotationEffect(.degrees(router.menuOpen ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(router.page.title). Switch page")
            .accessibilityHint("Shows Penny, Calendar and Breakdown")
            Spacer()
            Button { router.adding = true } label: { Image(systemName: "plus") }
                .buttonStyle(CircleButtonStyle())
                .accessibilityLabel("Add payment by hand")
            NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                .buttonStyle(CircleButtonStyle())
                .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
    }
}

/// The page menu: a small frosted card that grows out of the title.
struct PageMenu: View {
    @Environment(PageRouter.self) private var router

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(AppPage.allCases.enumerated()), id: \.element) { i, p in
                if i > 0 { Divider().overlay(Theme.line).padding(.leading, 46) }
                let on = router.page == p
                Button { router.go(p) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: p.icon)
                            .font(.system(size: 15, weight: on ? .semibold : .regular))
                            .frame(width: 22)
                        Text(p.title).font(.body.weight(on ? .semibold : .regular))
                        Spacer(minLength: 16)
                        if on { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                    }
                    .foregroundStyle(on ? Theme.ink : Theme.muted)
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .frame(width: 220)
        .padding(.vertical, 4)
        .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Theme.shadow.opacity(0.08), radius: 24, y: 12)
    }
}
