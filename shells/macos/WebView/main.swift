import AppKit
import WebKit

/// The baseline arm: the same game as a web page (webview-shell's asset
/// directory, the bytes every WebView arm loads) in a `WKWebView`.
final class ConsoleBridge: NSObject, WKScriptMessageHandler {
    /// Forwards every `console` line, and every uncaught error, to the app --
    /// the route the fps telemetry takes on this arm, as on iOS.
    static let source = """
        (() => {
          const post = (level, text) => window.webkit.messageHandlers.bench.postMessage([level, text]);
          const levels = { log: 1, info: 1, warn: 2, error: 3 };
          for (const name of Object.keys(levels)) {
            const original = console[name];
            console[name] = function (...args) {
              post(levels[name], args.map(String).join(' '));
              return original.apply(console, args);
            };
          }
          addEventListener('error', (e) => post(3, `Uncaught ${e.message} at ${e.filename}:${e.lineno}`));
          addEventListener('unhandledrejection', (e) => post(3, `Unhandled rejection: ${e.reason}`));
        })();
        """

    private(set) var lines = 0

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        guard let entry = message.body as? [Any], entry.count == 2,
              let level = entry[0] as? Int, let text = entry[1] as? String
        else { return }
        lines += 1
        Bench.console(level: level, message: text)
    }
}

let bridge = ConsoleBridge()
BenchAppDelegate.main(title: "WebViewBench") { window in
    guard let directory = Bundle.main.url(forResource: Bench.asset, withExtension: nil) else {
        Bench.report("failed: \(Bench.asset) is not in the app bundle")
        exit(1)
    }
    let configuration = WKWebViewConfiguration()
    configuration.mediaTypesRequiringUserActionForPlayback = []
    configuration.userContentController.addUserScript(WKUserScript(
        source: ConsoleBridge.source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    configuration.userContentController.add(bridge, name: "bench")
    let webView = WKWebView(frame: NSRect(origin: .zero, size: Bench.contentSize), configuration: configuration)
    window.contentView = webView
    webView.loadFileURL(directory.appendingPathComponent("index.html"), allowingReadAccessTo: directory)
    Bench.run(watching: window) { bridge.lines }
}
