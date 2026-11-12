import SwiftUI

/// Shown for a moment at launch: Penny nibbles her coin, then the app fades in. Tap to skip.
struct SplashView: View {
    let finished: () -> Void
    @State private var bite = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.card
            StarryTop().frame(maxHeight: .infinity, alignment: .top)
            Ellipse().fill(Color(hex: 0xC9C3F5)).frame(width: 240, height: 120)
                .blur(radius: 50).opacity(0.55)
                .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 120)

            VStack(spacing: 0) {
                (bite ? PennyArt.bite : PennyArt.hold).image(height: 140)
                    .scaleEffect(x: bite ? 1.02 : 1, y: bite ? 0.98 : 1, anchor: .bottom)
                Text("Pennywise").font(Theme.serif(40)).foregroundStyle(Theme.ink).padding(.top, 22)
                Text("See where your money goes.").font(.subheadline).foregroundStyle(Theme.muted).padding(.top, 6)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: finished)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pennywise")
        .task {
            if reduceMotion {
                try? await Task.sleep(for: .milliseconds(700))
            } else {
                // hold → bite → hold → bite, then in.
                try? await Task.sleep(for: .milliseconds(520))
                for _ in 0..<3 {
                    withAnimation(.snappy(duration: 0.14)) { bite.toggle() }
                    try? await Task.sleep(for: .milliseconds(380))
                }
            }
            finished()
        }
    }
}
