import XCTest
@testable import GMac

final class KeychainServiceTests: XCTestCase {
    var keychain: KeychainService!

    override func setUp() {
        keychain = KeychainService(service: "fr.agence810.GMac.tests")
        try? keychain.delete(key: "test_token")
        try? keychain.delete(key: "nonexistent_key_gmac_test")
    }

    override func tearDown() {
        try? keychain.delete(key: "test_token")
        try? keychain.delete(key: "nonexistent_key_gmac_test")
    }

    func test_save_andRetrieve() throws {
        try keychain.save("my_token", key: "test_token")
        let retrieved = try keychain.retrieve(key: "test_token")
        XCTAssertEqual(retrieved, "my_token")
    }

    func test_update_existingKey() throws {
        try keychain.save("token_v1", key: "test_token")
        try keychain.save("token_v2", key: "test_token")
        let retrieved = try keychain.retrieve(key: "test_token")
        XCTAssertEqual(retrieved, "token_v2")
    }

    func test_delete_removesKey() throws {
        try keychain.save("token", key: "test_token")
        try keychain.delete(key: "test_token")
        XCTAssertThrowsError(try keychain.retrieve(key: "test_token")) { error in
            XCTAssertEqual(error as? KeychainError, .notFound)
        }
    }

    func test_retrieve_missingKey_throws() {
        XCTAssertThrowsError(try keychain.retrieve(key: "nonexistent_key_gmac_test")) { error in
            XCTAssertEqual(error as? KeychainError, .notFound)
        }
    }

    func test_delete_nonExistentKey_doesNotThrow() {
        XCTAssertNoThrow(try keychain.delete(key: "nonexistent_key_gmac_test"))
    }

    func test_save_unicodeValue() throws {
        try keychain.save("tôkén_üñíçödé_🔑", key: "test_token")
        let retrieved = try keychain.retrieve(key: "test_token")
        XCTAssertEqual(retrieved, "tôkén_üñíçödé_🔑")
    }
}
