import UIKit
import WebKit

/// The baseline arm: the same game as a web page (webview-shell's asset
/// directory, the bytes the Android WebView arm loads) in a `WKWebView`.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = WebViewBenchViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class WebViewBenchViewController: BenchViewController, WKScriptMessageHandler {
    /// Forwards every `console` line, and every uncaught error, to the app --
    /// as the Migo arm's engine does -- so the fps telemetry and a failing
    /// script reach the harness by the same route on both arms.
    private static let consoleBridge = """
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

    private var consoleLines = 0

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.consoleBridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.add(self, name: "bench")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = true
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        view = webView
    }

    override func startGame() {
        guard let webView = view as? WKWebView,
              let directory = Bundle.main.url(forResource: Bench.asset, withExtension: nil)
        else {
            Bench.report("failed: \(Bench.asset) is not in the app bundle")
            exit(1)
        }
        webView.loadFileURL(
            directory.appendingPathComponent("index.html"), allowingReadAccessTo: directory)
        Bench.run(watching: webView) { [unowned self] in consoleLines }
    }

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        guard let entry = message.body as? [Any], entry.count == 2,
              let level = entry[0] as? Int, let text = entry[1] as? String
        else { return }
        consoleLines += 1
        Bench.console(level: level, message: text)
    }
}
