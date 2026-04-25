import Foundation

enum AppError: Error, Equatable, Sendable {
    case network(URLError)
    case apiError(statusCode: Int, message: String)
    case serverError(statusCode: Int)
    case gatewayError(statusCode: Int)
    case rateLimited(retryAfter: TimeInterval)
    case tokenExpired
    case offline
    case dnsError
    case emptyResponse
    case decodingError(String)
    case unknown

    var isRetryable: Bool {
        switch self {
        case .rateLimited, .gatewayError: return true
        case .network(let e): return e.code == .networkConnectionLost || e.code == .timedOut
        default: return false
        }
    }

    static func == (lhs: AppError, rhs: AppError) -> Bool {
        switch (lhs, rhs) {
        case (.tokenExpired, .tokenExpired), (.offline, .offline),
             (.unknown, .unknown), (.dnsError, .dnsError),
             (.emptyResponse, .emptyResponse): return true
        case (.network(let a), .network(let b)): return a.code == b.code
        case (.apiError(let a, let b), .apiError(let c, let d)): return a == c && b == d
        case (.serverError(let a), .serverError(let b)): return a == b
        case (.gatewayError(let a), .gatewayError(let b)): return a == b
        case (.rateLimited(let a), .rateLimited(let b)): return a == b
        case (.decodingError(let a), .decodingError(let b)): return a == b
        default: return false
        }
    }
}
