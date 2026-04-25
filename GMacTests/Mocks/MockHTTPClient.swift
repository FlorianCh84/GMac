import Foundation
@testable import GMac

final class MockHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _stubbedResult: Any?
    private var _stubbedError: AppError?
    private(set) var callCount = 0
    private(set) var lastRequest: URLRequest?

    func send<T: Decodable & Sendable>(_ request: URLRequest) async -> Result<T, AppError> {
        lock.withLock { callCount += 1; lastRequest = request }
        if let error = lock.withLock({ _stubbedError }) { return .failure(error) }
        if let result = lock.withLock({ _stubbedResult }) as? T { return .success(result) }
        return .failure(.unknown)
    }

    func stub<T>(_ result: T) { lock.withLock { _stubbedResult = result; _stubbedError = nil } }
    func stubError(_ error: AppError) { lock.withLock { _stubbedError = error; _stubbedResult = nil } }
    func reset() { lock.withLock { _stubbedResult = nil; _stubbedError = nil; callCount = 0; lastRequest = nil } }
}
