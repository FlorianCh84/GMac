import Foundation
@testable import GMac

final class MockKeychainService: KeychainServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: String] = [:]

    func save(_ value: String, key: String) throws {
        lock.withLock { store[key] = value }
    }

    func retrieve(key: String) throws -> String {
        try lock.withLock {
            guard let value = store[key] else { throw KeychainError.notFound }
            return value
        }
    }

    func delete(key: String) throws {
        lock.withLock { store.removeValue(forKey: key) }
    }

    func contains(key: String) -> Bool {
        lock.withLock { store[key] != nil }
    }
}
