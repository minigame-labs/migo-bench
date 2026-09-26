import UIKit

/// What both iOS bench apps share: the launch arguments, the lines the harness
/// reads from the console, and the check that the screen is drawing.
///
/// The harness (scripts/ios-ab.sh) launches an app with
/// `-BenchGame <asset> -BenchLandscape YES|NO -BenchSettle <s> -BenchSeconds <s>`,
/// waits for `[bench] measuring`, records the device for the measurement window
/// and reads the `[bench] ... fps=N` lines the game's own telemetry produced.
enum Bench {
    static let asset = UserDefaults.standard.string(forKey: "BenchGame") ?? "game"
    static let landscape = UserDefaults.standard.bool(forKey: "BenchLandscape")
    static let settle = UserDefaults.standard.double(forKey: "BenchSettle")
    static let seconds = UserDefaults.standard.double(forKey: "BenchSeconds")

    static func report(_ line: String) {
        print("[bench] \(line)")
        fflush(stdout)
    }

    /// A line the game wrote to `console`. Only the fps telemetry and errors are
    /// the harness's business; both arms forward every line to here, so what is
    /// filtered is the same on both.
    static func console(level: Int, message: String) {
        if message.contains("fps=") || level >= 3 {
            report(message)
        }
    }

    /// After the settle, prove the screen is drawing, then mark the start of the
    /// measurement window; exit once the run is over, failing if `progress` --
    /// frames delivered, or console lines received -- never moved.
    ///
    /// A runtime whose content failed to start can keep its frame loop -- and
    /// with it the fps telemetry -- running over a blank screen; the Android C
    /// host did exactly that. So a flat screen that stays flat for 1.5 s ends the
    /// run as a failure before anything is measured. Content that paints a
    /// single colour on purpose passes because the colour changes; the looks are
    /// 0.3 s apart because a single look one period later can see the same phase.
    static func run(watching view: UIView, progress: @escaping () -> Int) {
        guard seconds > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) {
            look(view, first: nil, remaining: 5) { drawing, detail in
                report("screen \(detail)")
                guard drawing else {
                    report("not rendering; nothing to measure")
                    exit(1)
                }
                report("measuring")
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                    let delivered = progress()
                    report("done progress=\(delivered)")
                    exit(delivered > 0 ? 0 : 1)
                }
            }
        }
    }

    private static func look(
        _ view: UIView, first: [UInt32]?, remaining: Int,
        done: @escaping (Bool, String) -> Void
    ) {
        let colours = sample(view)
        let distinct = Set(colours)
        if distinct.count > 1 {
            return done(true, "colours=\(distinct.count)")
        }
        let flat = String(format: "flat=%06x", colours.first ?? 0)
        if let first, first != colours {
            return done(true, "\(flat) changed")
        }
        guard remaining > 0 else { return done(false, "\(flat) unchanged for 1.5 s") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            look(view, first: first ?? colours, remaining: remaining - 1, done: done)
        }
    }

    /// A 32x32 grid of the view's on-screen pixels, as 0xRRGGBB.
    private static func sample(_ view: UIView) -> [UInt32] {
        let side = 32
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
        var pixels = [UInt32](repeating: 0, count: side * side)
        guard let cgImage = image.cgImage else { return pixels }
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return }
            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        // Stored R,G,B,x in memory order: drop the padding byte.
        return pixels.map { UInt32(bigEndian: $0) >> 8 }
    }
}

/// Full screen, no status bar or home indicator, locked to the game's
/// orientation -- the same frame for both arms.
class BenchViewController: UIViewController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        Bench.landscape ? .landscape : .portrait
    }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}
