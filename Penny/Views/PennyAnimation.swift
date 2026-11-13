import SwiftUI
import UIKit
import ImageIO

/// Penny's animated moments. Each is an animated WebP with a transparent background,
/// stored as a data asset ("Penny-<name>-anim") in Assets.xcassets, 24 fps.
enum PennyClip: String {
    case eat, sleep, wave, bag

    var assetName: String { "Penny-\(rawValue)-anim" }

    /// Width / height of the clip, so layout is right before the first frame is decoded.
    var aspect: CGFloat {
        switch self {
        case .eat: 405.0 / 420.0
        case .sleep: 485.0 / 300.0
        case .wave: 273.0 / 240.0
        case .bag: 388.0 / 360.0
        }
    }
}

/// Plays a Penny clip once (holding the last frame) or on a loop.
/// Frames are decoded one at a time, so memory stays small.
/// With Reduce Motion it shows a single frame: the first for loops, the last for one-shots.
struct PennyAnimation: View {
    let clip: PennyClip
    let height: CGFloat
    var loops = false
    /// Called when a one-shot clip finishes (immediately with Reduce Motion).
    var onFinish: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frame: CGImage?

    private static let frameTime = Duration.milliseconds(42)   // 24 fps, matches the files

    var body: some View {
        Group {
            if let frame {
                Image(decorative: frame, scale: 1).resizable().interpolation(.high)
            } else {
                Color.clear
            }
        }
        .aspectRatio(clip.aspect, contentMode: .fit)
        .frame(height: height)
        .accessibilityHidden(true)
        .task(id: clip) { await play() }
    }

    @MainActor
    private func play() async {
        guard let data = NSDataAsset(name: clip.assetName)?.data,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            onFinish?()
            return
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else {
            onFinish?()
            return
        }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        func image(at index: Int) -> CGImage? { CGImageSourceCreateImageAtIndex(source, index, options) }

        if reduceMotion {
            frame = image(at: loops ? 0 : count - 1)
            onFinish?()
            return
        }

        let clock = ContinuousClock()
        var deadline = clock.now
        repeat {
            for index in 0..<count {
                frame = image(at: index)
                deadline = deadline.advanced(by: Self.frameTime)
                do {
                    try await Task.sleep(until: deadline, clock: clock)
                } catch {
                    return   // view went away
                }
            }
        } while loops
        onFinish?()
    }
}
