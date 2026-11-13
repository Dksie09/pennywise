import SwiftUI

/// Shown at launch: Penny eats her coin (plays once), then the app fades in. Tap to skip.
struct SplashView: View {
    let finished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.card
            StarryTop().frame(maxHeight: .infinity, alignment: .top)
            Ellipse().fill(Color(hex: 0xC9C3F5)).frame(width: 240, height: 120)
                .blur(radius: 50).opacity(0.55)
                .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 120)

            VStack(spacing: 0) {
                PennyAnimation(clip: .eat, height: 150) {
                    // A short beat on her happy face (or a moment to read, with Reduce Motion), then in.
                    Task {
                        try? await Task.sleep(for: .milliseconds(reduceMotion ? 700 : 250))
                        finished()
                    }
                }
                Text("Pennywise").font(Theme.serif(40)).foregroundStyle(Theme.ink).padding(.top, 22)
                Text("See where your money goes.").font(.subheadline).foregroundStyle(Theme.muted).padding(.top, 6)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: finished)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pennywise")
    }
}
