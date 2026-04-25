import Foundation
@testable import GMac

final class MockHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private var stubbedResult: Any?
    private var stubbedError: AppError?
    var callCount = 0
    var lastRequest: URLRequest?

    func send<T: Decodable & Sendable>(_ request: URLRequest) async -> Result<T, AppError> {
        callCount += 1
        lastRequest = request
        if let error = stubbedError {
            return .failure(error)
        }
        if let result = stubbedResult as? T {
            return .success(result)
        }
        return .failure(.unknown)
    }

    func stub<T>(_ result: T) { stubbedResult = result }
    func stubError(_ error: AppError) { stubbedError = error }
    func reset() { stubbedResult = nil; stubbedError = nil; callCount = 0; lastRequest = nil }
}
