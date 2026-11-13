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

    /// Decodes one frame fully (call off the main thread). About a millisecond per frame;
    /// resizing while decoding measured slower, so frames are decoded at their natural size.
    func image(_ index: Int) -> CGImage? {
        let slice = data.subdata(in: offsets[index]..<offsets[index + 1])
        guard let source = CGImageSourceCreateWithData(slice as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}

/// Keeps a few decoded frames just ahead of the playhead, decoding on a background queue.
/// The view asks for whatever frame the screen's clock says is due; if that one isn't ready yet,
/// it gets the latest ready frame before it, so playback never waits on a decode.
final class PennyPlayer: @unchecked Sendable {
    let frames: PennyFrames
    let rate: Double                 // frames per second: always the clip's own speed
    let loops: Bool
    let count: Int                   // frames actually played (a clip can be cut short)
    private(set) var start: Date?

    private let lock = NSLock()
    private var cache: [Int: CGImage] = [:]
    private var inFlight: Set<Int> = []
    private var lastShown: CGImage?
    private let queue = DispatchQueue(label: "penny.frames", qos: .userInitiated)

    init(frames: PennyFrames, cut: Double?, loops: Bool) {
        self.frames = frames
        self.rate = Double(frames.fps)
        self.loops = loops
        self.count = cut.map { min(frames.count, max(1, Int(($0 * Double(frames.fps)).rounded()))) } ?? frames.count
    }

    var duration: Double { Double(count) / rate }

    /// Decode the first frames, then start the clock.
    func prepare() async {
        for i in 0..<min(3, count) {
            let image = frames.image(i)
            lock.withLock { if let image { cache[i] = image } }
        }
        lock.withLock { start = Date() }
    }

    /// Frame index due at `date` (clamped to the last frame for one-shots).
    func index(at date: Date) -> Int {
        guard let start else { return 0 }
        let i = Int(date.timeIntervalSince(start) * rate)
        return loops ? i % count : min(i, count - 1)
    }

    func image(at date: Date) -> CGImage? {
        let i = index(at: date)
        prefetch(after: i)
        return lock.withLock {
            if let ready = cache[i] { lastShown = ready }
            // Keep only the frames from the one on screen to the ones being prepared (wrapping
            // around for loops), so nothing gets decoded twice.
            for key in cache.keys where distance(from: i, to: key) > lookahead { cache[key] = nil }
            return lastShown
        }
    }

    /// About a tenth of a second of frames, at least 2.
    private var lookahead: Int { max(2, Int(rate / 10)) }

    /// How many frames after `i` frame `j` comes, counting around the loop.
    private func distance(from i: Int, to j: Int) -> Int {
        loops ? (j - i + count) % count : (j >= i ? j - i : Int.max)
    }

    /// One fixed frame (Reduce Motion).
    func still(_ index: Int) -> CGImage? { frames.image(index) }

    private func prefetch(after i: Int) {
        for step in 0...lookahead {
            var j = i + step
            if j >= count { if loops { j %= count } else { break } }
            let needs = lock.withLock { cache[j] == nil && !inFlight.contains(j) }
            guard needs else { continue }
            lock.withLock { _ = inFlight.insert(j) }
            queue.async { [self] in
                let image = frames.image(j)
                lock.withLock {
                    if let image { cache[j] = image }
                    inFlight.remove(j)
                }
            }
        }
    }
}

/// Plays a Penny clip once (holding the last frame) or on a loop.
/// Frames are picked by the screen's own clock (TimelineView), so they land in step with the display;
/// decoding happens in the background just ahead of the playhead. A late frame is skipped, never waited for.
/// Clips always play at their natural speed; `cut` stops a one-shot after that many seconds.
/// With Reduce Motion it shows a single frame: the first for loops, the last for one-shots.
struct PennyAnimation: View {
    let clip: PennyClip
    let height: CGFloat
    var loops = false
    var cut: Double? = nil
    /// Called when a one-shot clip finishes (immediately with Reduce Motion).
    var onFinish: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var player: PennyPlayer?
    @State private var still: CGImage?
    @State private var finished = false

    var body: some View {
        Group {
            if let still {
                frameView(still)
            } else if let player, player.start != nil {
                TimelineView(.animation(minimumInterval: 1 / player.rate, paused: finished)) { context in
                    frameView(player.image(at: context.date))
                }
            } else {
                Color.clear
            }
        }
        .aspectRatio(clip.aspect, contentMode: .fit)
        .frame(height: height)
        .accessibilityHidden(true)
        .task(id: clip) { await load() }
    }

    private func frameView(_ image: CGImage?) -> some View { FrameLayer(image: image) }

    @MainActor
    private func load() async {
        let clip = clip
        guard let frames = await Task.detached(priority: .userInitiated, operation: { PennyFrames(clip) }).value else {
            onFinish?()
            return
        }
        let player = PennyPlayer(frames: frames, cut: cut, loops: loops)

        if reduceMotion {
            still = await Task.detached(priority: .userInitiated) { player.still(loops ? 0 : player.count - 1) }.value
            onFinish?()
            return
        }

        await Task.detached(priority: .userInitiated) { await player.prepare() }.value
        self.player = player
        guard !loops else { return }
        // One-shots: stop the timeline on the last frame and report.
        try? await Task.sleep(for: .seconds(player.duration))
        guard !Task.isCancelled else { return }
        still = player.image(at: .distantFuture)   // hold exactly on the last frame
        finished = true
        onFinish?()
    }
}

/// Shows a frame by handing it straight to a Core Animation layer: far lighter than building a new
/// SwiftUI Image for every frame of a clip.
private struct FrameLayer: UIViewRepresentable {
    let image: CGImage?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.layer.contentsGravity = .resizeAspect
        view.layer.minificationFilter = .trilinear
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard view.layer.contents as! CGImage? !== image else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)        // no implicit cross-fade between frames
        view.layer.contents = image
        CATransaction.commit()
    }
}
