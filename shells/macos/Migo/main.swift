import AppKit
import CryptoKit
import MigoMacV8

/// The Migo arm: the bench game's Migo package (migo-shell's asset directory,
/// the same bytes every other Migo arm runs) in a `MigoGameView`, V8 with JIT
/// in this process.
BenchAppDelegate.main(title: "MigoBench") { window in
    do {
        guard let package = Bundle.main.url(forResource: Bench.asset, withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: Bench.asset])
        }
        if let reason = MigoGameView.unavailabilityReason {
            Bench.report("failed: \(reason)")
            exit(1)
        }
        // Bundled, so unsigned. The version is the package's own digest: an app
        // rebuilt around different game bytes keeps its build number, and the
        // installer skips a version it already has -- the bench would run the
        // previous game.
        let configuration = try MigoGameView.Configuration.standard(contentSigning: .unsigned)
        try MigoGameInstaller.install(
            package: package, id: Bench.asset, version: try digest(of: package),
            into: configuration.directories)
        let view = MigoGameView(configuration: configuration)
        view.onEvent = { event in
            switch event {
            case .ready: Bench.report("ready")
            case .failed(let reason): Bench.report("failed: \(reason)")
            case .error(let code, let message, let recoverable):
                Bench.report("error \(code) recoverable=\(recoverable): \(message)")
            default: break
            }
        }
        window.contentView = view
        view.loadGame(id: Bench.asset)
        Bench.run(watching: window) { view.frameClockStatistics?.delivered ?? 0 }
    } catch {
        Bench.report("failed: \(error)")
        exit(1)
    }
}

private func digest(of package: URL) throws -> String {
    var hash = SHA256()
    let files = try FileManager.default.contentsOfDirectory(at: package, includingPropertiesForKeys: nil)
    for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        hash.update(data: Data(file.lastPathComponent.utf8))
        hash.update(data: try Data(contentsOf: file))
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}
