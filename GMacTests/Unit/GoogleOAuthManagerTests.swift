import XCTest
@testable import GMac

final class GoogleOAuthManagerTests: XCTestCase {
    var keychain: KeychainService!
    var manager: GoogleOAuthManager!

    override func setUp() {
        keychain = KeychainService(service: "fr.agence810.GMac.tests")
        manager = GoogleOAuthManager(clientId: "test_client_id", clientSecret: "test_secret", keychain: keychain)
        try? keychain.delete(key: "google_access_token")
        try? keychain.delete(key: "google_refresh_token")
        try? keychain.delete(key: "google_token_expiry")
    }

    override func tearDown() {
        try? keychain.delete(key: "google_access_token")
        try? keychain.delete(key: "google_refresh_token")
        try? keychain.delete(key: "google_token_expiry")
    }

    func test_isAuthenticated_falseWhenNoTokens() {
        XCTAssertFalse(manager.isAuthenticated)
    }

    func test_isAuthenticated_trueWhenValidTokensStored() throws {
        try keychain.save("access_token", key: "google_access_token")
        try keychain.save("refresh_token", key: "google_refresh_token")
        let future = Date().addingTimeInterval(3600)
        try keychain.save("\(future.timeIntervalSince1970)", key: "google_token_expiry")
        XCTAssertTrue(manager.isAuthenticated)
    }

    func test_isAuthenticated_falseWhenExpired() throws {
        try keychain.save("access_token", key: "google_access_token")
        try keychain.save("refresh_token", key: "google_refresh_token")
        let past = Date().addingTimeInterval(-100)
        try keychain.save("\(past.timeIntervalSince1970)", key: "google_token_expiry")
        XCTAssertFalse(manager.isAuthenticated)
    }

    func test_sign_addsAuthorizationHeader() throws {
        try keychain.save("my_access_token", key: "google_access_token")
        try keychain.save("refresh_token", key: "google_refresh_token")
        let future = Date().addingTimeInterval(3600)
        try keychain.save("\(future.timeIntervalSince1970)", key: "google_token_expiry")

        let request = URLRequest(url: URL(string: "https://api.example.com")!)
        let signed = manager.sign(request)
        XCTAssertEqual(signed.value(forHTTPHeaderField: "Authorization"), "Bearer my_access_token")
    }

    func test_sign_noToken_doesNotAddHeader() {
        let request = URLRequest(url: URL(string: "https://api.example.com")!)
        let signed = manager.sign(request)
        XCTAssertNil(signed.value(forHTTPHeaderField: "Authorization"))
    }

    func test_logout_clearsKeychain() throws {
        try keychain.save("token", key: "google_access_token")
        try keychain.save("refresh", key: "google_refresh_token")
        try keychain.save("12345", key: "google_token_expiry")
        manager.logout()
        XCTAssertFalse(manager.isAuthenticated)
        XCTAssertThrowsError(try keychain.retrieve(key: "google_access_token"))
        XCTAssertThrowsError(try keychain.retrieve(key: "google_refresh_token"))
    }
}
