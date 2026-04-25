import XCTest
@testable import GMac

// Compteur thread-safe pour les closures @Sendable en Swift 6
final class Counter: @unchecked Sendable {
    private(set) var value = 0
    func increment() { value += 1 }
}

final class RetryTests: XCTestCase {

    func test_withRetry_succeedsOnFirstAttempt() async {
        let counter = Counter()
        let result: Result<String, AppError> = await withRetry(maxAttempts: 3) {
            counter.increment()
            return .success("ok")
        }
        XCTAssertEqual(counter.value, 1)
        XCTAssertEqual(try? result.get(), "ok")
    }

    func test_withRetry_retriesOnNetworkConnectionLost() async {
        let counter = Counter()
        let result: Result<String, AppError> = await withRetry(maxAttempts: 3, delay: 0) {
            counter.increment()
            if counter.value < 3 {
                return .failure(.network(URLError(.networkConnectionLost)))
            }
            return .success("ok")
        }
        XCTAssertEqual(counter.value, 3)
        XCTAssertEqual(try? result.get(), "ok")
    }

    func test_withRetry_retriesOnGatewayError() async {
        let counter = Counter()
        let result: Result<String, AppError> = await withRetry(maxAttempts: 2, delay: 0) {
            counter.increment()
            if counter.value < 2 {
                return .failure(.gatewayError(statusCode: 502))
            }
            return .success("ok")
        }
        XCTAssertEqual(counter.value, 2)
        XCTAssertEqual(try? result.get(), "ok")
    }

    func test_withRetry_doesNotRetryServerError500() async {
        let counter = Counter()
        let result: Result<String, AppError> = await withRetry(maxAttempts: 3, delay: 0) {
            counter.increment()
            return .failure(.serverError(statusCode: 500))
        }
        XCTAssertEqual(counter.value, 1, "500 ne doit pas être retryé")
        if case .failure(.serverError(500)) = result { } else {
            XCTFail("Expected .serverError(500)")
        }
    }

    func test_withRetry_doesNotRetryForbidden() async {
        let counter = Counter()
        let result: Result<String, AppError> = await withRetry(maxAttempts: 3, delay: 0) {
            counter.increment()
            return .failure(.apiError(statusCode: 403, message: "Forbidden"))
        }
        XCTAssertEqual(counter.value, 1, "403 ne doit pas être retryé")
        _ = result
    }

    func test_withRetry_retriesOnRateLimited() async {
        let counter = Counter()
        let result: Result<String, AppError> = await withRetry(maxAttempts: 3, delay: 0) {
            counter.increment()
            if counter.value < 2 {
                return .failure(.rateLimited(retryAfter: 0))
            }
            return .success("retried")
        }
        XCTAssertEqual(counter.value, 2)
        XCTAssertEqual(try? result.get(), "retried")
    }

    func test_withRetry_exhaustsAllAttempts_returnsLastError() async {
        let counter = Counter()
        let result: Result<String, AppError> = await withRetry(maxAttempts: 2, delay: 0) {
            counter.increment()
            return .failure(.network(URLError(.networkConnectionLost)))
        }
        XCTAssertEqual(counter.value, 3, "maxAttempts=2 → 2 tentatives + 1 dernière = 3 appels")
        if case .failure(.network) = result { } else {
            XCTFail("Expected .network error")
        }
    }
}
