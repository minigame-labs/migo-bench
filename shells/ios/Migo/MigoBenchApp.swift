import CryptoKit
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
            // Bundled, so unsigned. The version is the package's own digest: an
            // app rebuilt around different game bytes keeps its build number,
            // and the installer skips a version it already has -- the bench
            // would run the previous game.
            let configuration = try MigoGameView.Configuration.standard(contentSigning: .unsigned)
            try MigoGameInstaller.install(
                package: package, id: Bench.asset, version: try digest(of: package),
                into: configuration.directories)
            view = MigoGameView(configuration: configuration)
        } catch {
            Bench.report("failed: \(error)")
            exit(1)
        }
    }

    private func digest(of package: URL) throws -> String {
        var hash = SHA256()
        let files = try FileManager.default.contentsOfDirectory(
            at: package, includingPropertiesForKeys: nil)
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            hash.update(data: Data(file.lastPathComponent.utf8))
            hash.update(data: try Data(contentsOf: file))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
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
