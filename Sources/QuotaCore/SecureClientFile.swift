import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum SecureClientFile {
    public static func check(_ url: URL) throws {
        let components = url.path.split(separator: "/").map(String.init)
        guard url.isFileURL, !components.contains("."), !components.contains("..") else { throw CocoaError(.fileWriteNoPermission) }
        // Inspect the original path. URL standardization can resolve links on Darwin before we inspect them.
        for count in 1...max(1, components.count) {
            let path = "/" + components.prefix(count).joined(separator: "/")
            if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
               attributes[.type] as? FileAttributeType == .typeSymbolicLink { throw CocoaError(.fileWriteNoPermission) }
        }
    }
    public static func read(_ url: URL) throws -> Data? {
        try check(url)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 1_048_576 else { throw QuotaError.invalidCredentials }
        return try Data(contentsOf: url)
    }
    public static func write(_ data: Data?, to url: URL) throws {
        try check(url)
        guard let data else {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = directory.appendingPathComponent(".quotabar-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let handle = try FileHandle(forWritingTo: temporary)
        do { try handle.write(contentsOf: data); try handle.synchronize(); try handle.close() }
        catch { try? handle.close(); throw error }
        guard rename(temporary.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}
