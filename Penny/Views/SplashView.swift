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
                // The first 2 seconds of the clip at its natural speed, then the app fades in.
                PennyAnimation(clip: .eat, height: 150, cut: 2) {
                    // (With Reduce Motion: a still frame and a moment to read.)
                    Task {
                        if reduceMotion { try? await Task.sleep(for: .milliseconds(700)) }
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
