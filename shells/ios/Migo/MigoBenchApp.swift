import MigoApplePerformancePlus
import UIKit

/// The Migo arm: the bench game's Migo package (migo-shell's asset directory,
/// the same bytes the Android Migo arm runs) in a `MigoGameView`.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = MigoBenchViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class MigoBenchViewController: BenchViewController {
    override func loadView() {
        do {
            guard let package = Bundle.main.url(forResource: Bench.asset, withExtension: nil) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: Bench.asset])
            }
            // Bundled, so unsigned; the build number as the version skips the
            // copy on every launch after the first.
            let configuration = try MigoGameView.Configuration.standard(contentSigning: .unsigned)
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            try MigoGameInstaller.install(
                package: package, id: Bench.asset, version: version, into: configuration.directories)
            view = MigoGameView(configuration: configuration)
        } catch {
            Bench.report("failed: \(error)")
            exit(1)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let gameView = view as? MigoGameView else { return }
        gameView.onEvent = { event in
            switch event {
            case .ready: Bench.report("ready")
            case .console(let level, let message): Bench.console(level: level, message: message)
            case .failed(let reason): Bench.report("failed: \(reason)")
            case .error(let code, let message, let recoverable):
                Bench.report("error \(code) recoverable=\(recoverable): \(message)")
            default: break
            }
        }
        gameView.loadGame(id: Bench.asset)
        Bench.run(watching: gameView) { gameView.frameClockStatistics?.delivered ?? 0 }
    }
}
