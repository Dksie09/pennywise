import SwiftUI
import UIKit
import ImageIO

/// Penny's animated moments, stored as data assets ("Penny-<name>-anim") in Assets.xcassets.
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

/// A clip's frames. Each frame is its own small still WebP (with transparency), packed into one file:
/// "PNY1", u16 width, u16 height, u16 fps, u16 count, count × u32 byte lengths, then the frames.
/// Because frames don't depend on each other, decoding frame 80 costs the same as frame 1.
final class PennyFrames: @unchecked Sendable {
    let fps: Int
    let count: Int
    private let data: Data
    private let offsets: [Int]   // count + 1 boundaries into `data`

    init?(_ clip: PennyClip) {
        guard let data = NSDataAsset(name: clip.assetName)?.data, data.count > 12,
              data.prefix(4) == Data("PNY1".utf8) else { return nil }
        let bytes = [UInt8](data)
        func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        let fps = u16(8), count = u16(10)
        let headerEnd = 12 + 4 * count
        guard fps > 0, count > 0, bytes.count >= headerEnd else { return nil }
        var offsets = [headerEnd]
        for i in 0..<count { offsets.append(offsets[i] + u32(12 + 4 * i)) }
        guard offsets[count] <= bytes.count else { return nil }
        self.fps = fps
        self.count = count
        self.data = data
        self.offsets = offsets
    }

    /// Decodes one frame fully (call off the main thread).
    func image(_ index: Int) -> CGImage? {
        let slice = data.subdata(in: offsets[index]..<offsets[index + 1])
        guard let source = CGImageSourceCreateWithData(slice as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}

/// Plays a Penny clip once (holding the last frame) or on a loop.
/// Frames are decoded in the background one ahead of time; playback follows the clock,
/// so if a frame is ever late it is skipped rather than slowing the animation down.
/// With Reduce Motion it shows a single frame: the first for loops, the last for one-shots.
struct PennyAnimation: View {
    let clip: PennyClip
    let height: CGFloat
    var loops = false
    /// Called when a one-shot clip finishes (immediately with Reduce Motion).
    var onFinish: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frame: CGImage?

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
        let clip = clip
        guard let frames = await Task.detached(priority: .userInitiated, operation: { PennyFrames(clip) }).value else {
            onFinish?()
            return
        }
        func decode(_ index: Int) -> Task<CGImage?, Never> {
            Task.detached(priority: .userInitiated) { frames.image(index) }
        }
        let last = frames.count - 1

        if reduceMotion {
            frame = await decode(loops ? 0 : last).value
            onFinish?()
            return
        }

        let clock = ContinuousClock()
        let start = clock.now
        let frameTime = Duration.seconds(1) / frames.fps
        var tick = 0                       // frames since start (keeps counting across loops)
        var pending = decode(0)

        while true {
            let image = await pending.value
            do {
                try await Task.sleep(until: start.advanced(by: frameTime * tick), clock: clock)
            } catch {
                return   // view went away
            }
            frame = image
            if !loops && tick >= last {
                onFinish?()
                return
            }
            // Next frame: normally tick + 1, but jump ahead if we've fallen behind the clock.
            let onClock = Int((clock.now - start) / frameTime)
            tick = max(tick + 1, onClock + 1)
            if !loops { tick = min(tick, last) }
            pending = decode(tick % frames.count)
        }
    }
}
