#if os(macOS)
import SwiftUI
import Sparkle
import Combine

@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = false
    @Published private(set) var automaticDownloads = false
    private var controller: SPUStandardUpdaterController?
    private var observers: Set<AnyCancellable> = []
    private var started = false
    var configured: Bool { controller != nil }
    init() {
        guard Bundle.main.bundleURL.pathExtension == "app",
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32,
              let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https" else { return }
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    }
    func start() {
        guard let controller, !started else { return }
        started = true
        controller.startUpdater()
        controller.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main)
            .sink { [weak self] value in self?.canCheck = value }.store(in: &observers)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).receive(on: RunLoop.main)
            .sink { [weak self] value in self?.automaticChecks = value }.store(in: &observers)
        controller.updater.publisher(for: \.automaticallyDownloadsUpdates).receive(on: RunLoop.main)
            .sink { [weak self] value in self?.automaticDownloads = value }.store(in: &observers)
    }
    func check() { if canCheck { controller?.checkForUpdates(nil) } }
    func setAutomaticChecks(_ value: Bool) { controller?.updater.automaticallyChecksForUpdates = value }
    func setAutomaticDownloads(_ value: Bool) { controller?.updater.automaticallyDownloadsUpdates = value }
}
#endif
