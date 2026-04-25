import XCTest
@testable import GMac

final class AuthenticatedHTTPClientTests: XCTestCase {
    struct TestPayload: Decodable, Sendable, Equatable { let value: String }

    var mockKeychain: MockKeychainService!
    var oauth: GoogleOAuthManager!

    override func setUp() async throws {
        let keychain = MockKeychainService()
        let oauthInstance = await MainActor.run {
            GoogleOAuthManager(clientId: "test", clientSecret: "secret", keychain: keychain)
        }
        mockKeychain = keychain
        oauth = oauthInstance
    }

    @MainActor
    func test_send_addsAuthorizationHeader() async throws {
        try mockKeychain.save("test_token", key: "google_access_token")
        try mockKeychain.save("refresh_token", key: "google_refresh_token")
        let future = Date().addingTimeInterval(3600)
        try mockKeychain.save("\(future.timeIntervalSince1970)", key: "google_token_expiry")

        let session = MockURLSession(data: try JSONEncoder().encode(["value": "ok"]), statusCode: 200)
        let client = AuthenticatedHTTPClient(session: session, oauth: oauth)

        let result: Result<TestPayload, AppError> = await client.send(
            URLRequest(url: URL(string: "https://api.test.com")!)
        )

        XCTAssertEqual(try? result.get(), TestPayload(value: "ok"))
        XCTAssertEqual(
            session.lastRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer test_token"
        )
    }

    @MainActor
    func test_send_emptyResponse_returnsEmptyResponse() async throws {
        try mockKeychain.save("token", key: "google_access_token")
        try mockKeychain.save("refresh", key: "google_refresh_token")
        try mockKeychain.save("\(Date().addingTimeInterval(3600).timeIntervalSince1970)", key: "google_token_expiry")

        let session = MockURLSession(data: Data(), statusCode: 200)
        let client = AuthenticatedHTTPClient(session: session, oauth: oauth)
        let result: Result<TestPayload, AppError> = await client.send(
            URLRequest(url: URL(string: "https://api.test.com")!)
        )
        XCTAssertEqual(result, .failure(.emptyResponse))
    }

    @MainActor
    func test_send_500_returnsServerError() async throws {
        let session = MockURLSession(data: Data("error".utf8), statusCode: 500)
        let client = AuthenticatedHTTPClient(session: session, oauth: oauth)
        let result: Result<TestPayload, AppError> = await client.send(
            URLRequest(url: URL(string: "https://api.test.com")!)
        )
        XCTAssertEqual(result, .failure(.serverError(statusCode: 500)))
    }

    @MainActor
    func test_send_429_returnsRateLimited() async throws {
        let session = MockURLSession(data: Data(), statusCode: 429, headers: ["Retry-After": "30"])
        let client = AuthenticatedHTTPClient(session: session, oauth: oauth)
        let result: Result<TestPayload, AppError> = await client.send(
            URLRequest(url: URL(string: "https://api.test.com")!)
        )
        XCTAssertEqual(result, .failure(.rateLimited(retryAfter: 30)))
    }

    @MainActor
    func test_send_invalidJSON_returnsDecodingError() async throws {
        let session = MockURLSession(data: Data("not json".utf8), statusCode: 200)
        let client = AuthenticatedHTTPClient(session: session, oauth: oauth)
        let result: Result<TestPayload, AppError> = await client.send(
            URLRequest(url: URL(string: "https://api.test.com")!)
        )
        if case .failure(.decodingError) = result { } else {
            XCTFail("Expected .decodingError, got \(result)")
        }
    }
}

// Helper mock URLSession
final class MockURLSession: @unchecked Sendable {
    private let lock = NSLock()
    private var _lastRequest: URLRequest?
    private let data: Data
    private let statusCode: Int
    private let headers: [String: String]

    var lastRequest: URLRequest? { lock.withLock { _lastRequest } }

    init(data: Data, statusCode: Int, headers: [String: String] = [:]) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
    }
}

extension MockURLSession: URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock { _lastRequest = request }
        let url = request.url ?? URL(string: "https://mock.test")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
        return (data, response)
    }
}
