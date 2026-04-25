protocol KeychainServiceProtocol: Sendable {
    func save(_ value: String, key: String) throws
    func retrieve(key: String) throws -> String
    func delete(key: String) throws
}
