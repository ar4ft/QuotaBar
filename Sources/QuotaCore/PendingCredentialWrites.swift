import Foundation

// Only newly rotated credentials are retained, until secure persistence succeeds.
// This buffer has no disk representation and must not be encoded into metadata.
public struct PendingCredentialWrites {
    private var pending: [UUID: Credential] = [:]
    public init() {}

    public mutating func retain(_ credential: Credential, id: UUID) { pending[id] = credential }
    public mutating func remove(_ id: UUID) { pending[id] = nil }

    public mutating func load(id: UUID, read: () throws -> Credential, write: (Credential) throws -> Void) throws -> Credential {
        guard let credential = pending[id] else { return try read() }
        try save(credential, id: id, write: write)
        return credential
    }

    public mutating func save(_ credential: Credential, id: UUID, write: (Credential) throws -> Void) throws {
        try write(credential)
        pending[id] = nil
    }
}
