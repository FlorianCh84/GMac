import Foundation

protocol HTTPClientProtocol: Sendable {
    func send<T: Decodable & Sendable>(_ request: URLRequest) async -> Result<T, AppError>
}

func withRetry<T: Sendable>(
    maxRetries: Int = 3,
    delay: TimeInterval = -1,
    operation: @Sendable () async -> Result<T, AppError>
) async -> Result<T, AppError> {
    for attempt in 0..<maxRetries {
        let result = await operation()
        switch result {
        case .success:
            return result
        case .failure(let error) where error.isRetryable:
            let waitTime: TimeInterval
            if case .rateLimited(let retryAfter) = error {
                waitTime = delay >= 0 ? delay : max(1, retryAfter)
            } else {
                waitTime = delay >= 0 ? delay : pow(2.0, Double(attempt + 1))
            }
            if waitTime > 0 {
                try? await Task.sleep(for: .seconds(waitTime))
            }
        case .failure:
            return result
        }
    }
    return await operation()
}
