import AppKit
import CoreGraphics

/// What both macOS bench apps share: the launch arguments, the lines the harness
/// reads, the window both arms run in, and the check that it is drawing.
///
/// The harness (scripts/macos-ab.sh) launches an app with
/// `-BenchGame <asset> -BenchLandscape YES|NO -BenchSettle <s> -BenchSeconds 0`,
/// waits for `[bench] measuring`, samples the arm's processes for the window,
/// ends the app, and reads the `fps=N` lines the game's own telemetry produced
/// inside it. `-BenchSeconds N` ends the run after N seconds instead, for a
/// check by hand. The same protocol as the iOS shell (shells/ios).
enum Bench {
    static let asset = UserDefaults.standard.string(forKey: "BenchGame") ?? "game"
    static let landscape = UserDefaults.standard.bool(forKey: "BenchLandscape")
    static let settle = UserDefaults.standard.double(forKey: "BenchSettle")
    static let seconds: Double? = UserDefaults.standard.object(forKey: "BenchSeconds") == nil
        ? nil : UserDefaults.standard.double(forKey: "BenchSeconds")

    /// Both arms run in a window of a phone's proportions, 9:16 in points --
    /// what these mini-games are laid out for -- and the same size in each, so
    /// both render the same number of pixels on the same display.
    static var contentSize: NSSize {
        landscape ? NSSize(width: 800, height: 450) : NSSize(width: 450, height: 800)
    }

    static func report(_ line: String) {
        print("[bench] \(line)")
        fflush(stdout)
    }

    /// A line the game wrote to `console`, from the WebView arm. The Migo arm's
    /// console reaches the harness on the engine's own log (`MIGO_CAPI_LOG`),
    /// which the harness reads the same way: only the fps telemetry and errors.
    static func console(level: Int, message: String) {
        if message.contains("fps=") || level >= 3 {
            report(message)
        }
    }

    /// The window both arms use: titled, not resizable, centred, in front.
    static func makeWindow(title: String) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title
        window.center()
        return window
    }

    /// After the settle, prove the window is on screen and drawing, then mark
    /// the start of the measurement window. With `seconds` 0 the run lasts until
    /// the harness ends it; otherwise exit after `seconds`, failing if
    /// `progress` never moved.
    ///
    /// A runtime whose content failed to start can keep its frame loop -- and
    /// the fps telemetry with it -- running over a blank window, so a flat
    /// window that stays flat for 1.5 s ends the run as a failure before
    /// anything is measured. An occluded or minimised window is refused too:
    /// macOS stops giving an occluded window's display link frames, and a cell
    /// measured like that compares a paused arm with a running one.
    static func run(watching window: NSWindow, progress: @escaping () -> Int) {
        guard let seconds else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) {
            guard window.occlusionState.contains(.visible) else {
                report("the window is not visible (screen locked, asleep or covered); nothing to measure")
                exit(1)
            }
            look(window, first: nil, remaining: 5) { drawing, detail in
                report("screen \(detail)")
                guard drawing else {
                    report("not rendering; nothing to measure")
                    exit(1)
                }
                report("measuring")
                guard seconds > 0 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                    let delivered = progress()
                    report("done progress=\(delivered)")
                    exit(delivered > 0 ? 0 : 1)
                }
            }
        }
    }

    private static func look(
        _ window: NSWindow, first: [UInt32]?, remaining: Int,
        done: @escaping (Bool, String) -> Void
    ) {
        guard let colours = sample(window) else {
            return done(false, "unreadable: the window server returned no image of this window")
        }
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
            look(window, first: first ?? colours, remaining: remaining - 1, done: done)
        }
    }

    /// A 32x32 grid of the window's content as the window server composited it,
    /// as 0xRRGGBB. Composited pixels, not the view's own drawing: the Migo arm
    /// presents through a CAMetalLayer, which no view-level capture can see.
    /// A process may image its own windows without the screen-recording
    /// permission, which is the only kind of window this asks for.
    private static func sample(_ window: NSWindow) -> [UInt32]? {
        let side = 32
        guard let content = window.contentView else { return nil }
        let inWindow = content.convert(content.bounds, to: nil)
        let onScreen = window.convertToScreen(inWindow)
        // CoreGraphics measures from the top of the main display, AppKit from
        // its bottom.
        let height = NSScreen.screens.first?.frame.height ?? onScreen.maxY
        let rect = CGRect(
            x: onScreen.minX, y: height - onScreen.maxY, width: onScreen.width, height: onScreen.height)
        guard let image = CGWindowListCreateImage(
            rect, .optionIncludingWindow, CGWindowID(window.windowNumber),
            [.boundsIgnoreFraming, .nominalResolution])
        else { return nil }
        var pixels = [UInt32](repeating: 0, count: side * side)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        // Stored R,G,B,x in memory order: drop the padding byte.
        return pixels.map { UInt32(bigEndian: $0) >> 8 }
    }
}

/// The application both arms run: one window, the game in it, quit when it
/// closes.
final class BenchAppDelegate: NSObject, NSApplicationDelegate {
    private let title: String
    private let makeContent: (NSWindow) -> Void
    private var window: NSWindow?

    init(title: String, makeContent: @escaping (NSWindow) -> Void) {
        self.title = title
        self.makeContent = makeContent
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = Bench.makeWindow(title: title)
        self.window = window
        makeContent(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    static func main(title: String, makeContent: @escaping (NSWindow) -> Void) {
        let delegate = BenchAppDelegate(title: title, makeContent: makeContent)
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
