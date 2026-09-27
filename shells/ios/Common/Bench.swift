import UIKit

/// What both iOS bench apps share: the launch arguments, the lines the harness
/// reads from the console, and the check that the screen is drawing.
///
/// The harness (scripts/ios-ab.sh) launches an app with
/// `-BenchGame <asset> -BenchLandscape YES|NO -BenchSettle <s> -BenchSeconds 0`,
/// waits for `[bench] measuring`, records the device, ends the app, and reads
/// the `[bench] ... fps=N` lines the game's own telemetry produced during the
/// recording. `-BenchSeconds N` ends the run after N seconds instead, for a
/// check by hand; without it the app just plays.
enum Bench {
    static let asset = UserDefaults.standard.string(forKey: "BenchGame") ?? "game"
    static let landscape = UserDefaults.standard.bool(forKey: "BenchLandscape")
    static let settle = UserDefaults.standard.double(forKey: "BenchSettle")
    static let seconds: Double? = UserDefaults.standard.object(forKey: "BenchSeconds") == nil
        ? nil : UserDefaults.standard.double(forKey: "BenchSeconds")

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
    /// measurement window. With `seconds` 0 the run lasts until the harness ends
    /// it: the recording, not the app, decides the window, because Instruments
    /// can take half a minute to start recording and an app that ended on its
    /// own clock cut the recording short. Otherwise exit after `seconds`,
    /// failing if `progress` -- frames delivered, or console lines received --
    /// never moved.
    ///
    /// A runtime whose content failed to start can keep its frame loop -- and
    /// with it the fps telemetry -- running over a blank screen; the Android C
    /// host did exactly that. So a flat screen that stays flat for 1.5 s ends the
    /// run as a failure before anything is measured. Content that paints a
    /// single colour on purpose passes because the colour changes; the looks are
    /// 0.3 s apart because a single look one period later can see the same phase.
    static func run(watching view: UIView, progress: @escaping () -> Int) {
        guard let seconds else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) {
            // Something over the app -- the lock screen, a system alert -- keeps
            // it inactive. Migo pauses its game then, as a game should, while
            // WebKit keeps running the page: a cell measured like that compares
            // a paused arm with a running one.
            guard UIApplication.shared.applicationState == .active else {
                report("the app is not active (lock screen or a system alert over it); nothing to measure")
                exit(1)
            }
            look(view, first: nil, remaining: 5) { drawing, detail in
                report("screen \(detail)")
                guard drawing else {
                    report("not rendering; nothing to measure")
                    exit(1)
                }
                report("measuring")
                reportMemoryLedger()
                guard seconds > 0 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                    let delivered = progress()
                    report("done progress=\(delivered)")
                    exit(delivered > 0 ? 0 : 1)
                }
            }
        }
    }

    /// This process's own memory by ledger, every 10 s while measuring: what
    /// Activity Monitor's single footprint number for the app is made of. The
    /// graphics ledger is IOSurfaces and Metal allocations -- drawables,
    /// textures, buffers -- and `internal` the anonymous memory under them, most
    /// of it the heap. Other processes (WebKit's) cannot be read from here.
    private static func reportMemoryLedger() {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if status == KERN_SUCCESS {
            var heap = malloc_statistics_t()
            malloc_zone_statistics(nil, &heap)
            let mib = { (bytes: Int64) in String(format: "%.1f", Double(bytes) / 1_048_576) }
            report(
                "memory footprint=\(mib(Int64(info.phys_footprint)))"
                    + " graphics=\(mib(info.ledger_tag_graphics_footprint))"
                    + " internal=\(mib(Int64(info.internal)))"
                    + " compressed=\(mib(Int64(info.compressed)))"
                    + " heap=\(mib(Int64(heap.size_in_use)))"
                    + " network=\(mib(info.ledger_tag_network_nonvolatile))"
                    + " media=\(mib(info.ledger_tag_media_footprint))")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { reportMemoryLedger() }
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
