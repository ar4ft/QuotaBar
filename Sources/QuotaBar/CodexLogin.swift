#if os(macOS)
import Foundation
import Observation
import QuotaCore

@MainActor
@Observable
final class CodexLogin {
    var output = ""
    var running = false
    var error: String?
    private var process: Process?
    private var workingFolder: URL?
    private var timeoutTask: Task<Void, Never>?
    private var generation = UUID()

    func start(root: URL, executable: String, completion: @escaping @MainActor @Sendable (Credential) -> Void) {
        cancel(); error = nil; output = "Starting an isolated Codex login…\n"
        let attempt = UUID(); generation = attempt
        do {
            let path = executable.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidates = path.isEmpty ? ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"] : [path]
            guard let binary = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                throw NSError(domain: "QuotaBar", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "Install Codex CLI with npm install -g @openai/codex, or enter the full path to your codex executable."])
            }
            let folder = root.appendingPathComponent("Login-\(attempt.uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            workingFolder = folder
            let process = Process(); let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = ["-c", "cli_auth_credentials_store=\"file\"", "login", "--device-auth"]
            var environment = ProcessInfo.processInfo.environment
            environment["CODEX_HOME"] = folder.path
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
            process.environment = environment; process.currentDirectoryURL = folder
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = pipe; process.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let text = String(decoding: data, as: UTF8.self)
                Task { @MainActor in
                    guard let self, self.generation == attempt else { return }
                    self.output = String((self.output + text).suffix(12_000))
                }
            }
            process.terminationHandler = { [weak self] terminated in
                pipe.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor in
                    guard let self, self.generation == attempt else { return }
                    defer { self.cleanup() }
                    guard terminated.terminationStatus == 0 else {
                        self.error = "Login did not finish. Retry, and make sure device-code login is enabled in your ChatGPT security settings."
                        return
                    }
                    do {
                        let file = folder.appendingPathComponent("auth.json")
                        let credential = try CredentialParser.parse(Data(contentsOf: file), provider: .openAI, ownsLogin: true)
                        completion(credential)
                    } catch { self.error = error.localizedDescription }
                }
            }
            self.process = process; try process.run(); running = true
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(900))
                guard !Task.isCancelled, let self, self.generation == attempt else { return }
                self.cancel(); self.error = "Login timed out. Start a new login to try again."
            }
        } catch { self.error = error.localizedDescription; cleanup() }
    }
    func cancel() {
        generation = UUID()
        if let process, process.isRunning {
            process.terminate()
            // Clean the isolated home after the child exits, including a late auth.json write.
            let folder = workingFolder
            process.terminationHandler = { _ in
                if let folder { try? FileManager.default.removeItem(at: folder) }
            }
            workingFolder = nil
        }
        cleanup()
    }
    private func cleanup() {
        timeoutTask?.cancel(); timeoutTask = nil
        if let folder = workingFolder { try? FileManager.default.removeItem(at: folder) }
        workingFolder = nil; process = nil; running = false
    }
}
#endif
