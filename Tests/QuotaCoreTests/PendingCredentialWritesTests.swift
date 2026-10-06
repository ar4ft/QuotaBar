import XCTest
@testable import QuotaCore

final class PendingCredentialWritesTests: XCTestCase {
    func testDeniedWriteRetainsRotatedTokenAndRetriesPersistenceBeforeAnyOldRead() throws {
        let id = UUID(), credential = Credential(kind: .codex, secret: "synthetic-new-access", refreshToken: "synthetic-new-refresh")
        var buffer = PendingCredentialWrites()
        buffer.retain(credential, id: id)
        var reads = 0
        XCTAssertThrowsError(try buffer.load(id: id, read: { reads += 1; throw QuotaError.unauthorized },
                                            write: { _ in throw QuotaError.forbidden }))
        var saved: Credential?
        let recovered = try buffer.load(id: id, read: { reads += 1; throw QuotaError.unauthorized }, write: { saved = $0 })
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(recovered.secret, credential.secret)
        XCTAssertEqual(saved?.refreshToken, credential.refreshToken)
        _ = try buffer.load(id: id, read: { reads += 1; return credential }, write: { _ in XCTFail("Already persisted") })
        XCTAssertEqual(reads, 1)
    }

    func testReplacementAndRemovalCannotResurrectAnOlderRotation() throws {
        let id = UUID(), old = Credential(kind: .codex, secret: "old"), replacement = Credential(kind: .codex, secret: "replacement")
        var buffer = PendingCredentialWrites()
        buffer.retain(old, id: id)
        try buffer.save(replacement, id: id, write: { _ in })
        let current = try buffer.load(id: id, read: { replacement }, write: { _ in XCTFail("Old rotation must be cleared") })
        XCTAssertEqual(current.secret, replacement.secret)
        buffer.retain(old, id: id)
        buffer.remove(id)
        XCTAssertThrowsError(try buffer.load(id: id, read: { throw QuotaError.invalidCredentials }, write: { _ in XCTFail("Removed account") }))
    }
}
