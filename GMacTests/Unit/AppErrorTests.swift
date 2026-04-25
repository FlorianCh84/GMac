import XCTest
@testable import GMac

final class AppErrorTests: XCTestCase {

    func test_equality_simpleCases() {
        XCTAssertEqual(AppError.tokenExpired, AppError.tokenExpired)
        XCTAssertEqual(AppError.offline, AppError.offline)
        XCTAssertEqual(AppError.dnsError, AppError.dnsError)
        XCTAssertEqual(AppError.emptyResponse, AppError.emptyResponse)
        XCTAssertNotEqual(AppError.offline, AppError.tokenExpired)
    }

    func test_equality_apiError() {
        XCTAssertEqual(
            AppError.apiError(statusCode: 401, message: "Unauthorized"),
            AppError.apiError(statusCode: 401, message: "Unauthorized")
        )
        XCTAssertNotEqual(
            AppError.apiError(statusCode: 401, message: "Unauthorized"),
            AppError.apiError(statusCode: 403, message: "Forbidden")
        )
    }

    func test_equality_rateLimited() {
        XCTAssertEqual(AppError.rateLimited(retryAfter: 5), AppError.rateLimited(retryAfter: 5))
        XCTAssertNotEqual(AppError.rateLimited(retryAfter: 5), AppError.rateLimited(retryAfter: 10))
    }

    func test_equality_serverError() {
        XCTAssertEqual(AppError.serverError(statusCode: 500), AppError.serverError(statusCode: 500))
        XCTAssertNotEqual(AppError.serverError(statusCode: 500), AppError.serverError(statusCode: 501))
    }

    func test_equality_gatewayError() {
        XCTAssertEqual(AppError.gatewayError(statusCode: 502), AppError.gatewayError(statusCode: 502))
        XCTAssertNotEqual(AppError.gatewayError(statusCode: 502), AppError.gatewayError(statusCode: 503))
    }

    func test_equality_decodingError() {
        XCTAssertEqual(AppError.decodingError("field missing"), AppError.decodingError("field missing"))
        XCTAssertNotEqual(AppError.decodingError("a"), AppError.decodingError("b"))
    }

    // isRetryable tests
    func test_isRetryable_rateLimited() {
        XCTAssertTrue(AppError.rateLimited(retryAfter: 5).isRetryable)
    }

    func test_isRetryable_gatewayError() {
        XCTAssertTrue(AppError.gatewayError(statusCode: 502).isRetryable)
        XCTAssertTrue(AppError.gatewayError(statusCode: 503).isRetryable)
    }

    func test_isRetryable_networkConnectionLost() {
        XCTAssertTrue(AppError.network(URLError(.networkConnectionLost)).isRetryable)
    }

    func test_isRetryable_timedOut() {
        XCTAssertTrue(AppError.network(URLError(.timedOut)).isRetryable)
    }

    func test_isNotRetryable_serverError500() {
        XCTAssertFalse(AppError.serverError(statusCode: 500).isRetryable)
    }

    func test_isNotRetryable_apiError403() {
        XCTAssertFalse(AppError.apiError(statusCode: 403, message: "Forbidden").isRetryable)
    }

    func test_isNotRetryable_tokenExpired() {
        XCTAssertFalse(AppError.tokenExpired.isRetryable)
    }

    func test_isNotRetryable_offline() {
        XCTAssertFalse(AppError.offline.isRetryable)
    }

    func test_isNotRetryable_dnsError() {
        XCTAssertFalse(AppError.dnsError.isRetryable)
    }

    func test_isNotRetryable_emptyResponse() {
        XCTAssertFalse(AppError.emptyResponse.isRetryable)
    }

    func test_isNotRetryable_decodingError() {
        XCTAssertFalse(AppError.decodingError("err").isRetryable)
    }

    func test_isNotRetryable_unknown() {
        XCTAssertFalse(AppError.unknown.isRetryable)
    }

    func test_isNotRetryable_networkCancelled() {
        XCTAssertFalse(AppError.network(URLError(.cancelled)).isRetryable)
    }
}
