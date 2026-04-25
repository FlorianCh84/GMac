import Foundation

final class AuthenticatedHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private static let defaultRetryAfterSeconds: Double = 1
    private let session: any URLSessionProtocol
    private let oauth: GoogleOAuthManager

    init(session: any URLSessionProtocol = URLSession.shared, oauth: GoogleOAuthManager) {
        self.session = session
        self.oauth = oauth
    }

    func send<T: Decodable & Sendable>(_ request: URLRequest) async -> Result<T, AppError> {
        let signed = await oauth.sign(request)
        let result: Result<T, AppError> = await performRequest(signed)

        if case .failure(.apiError(401, _)) = result {
            do {
                try await oauth.refresh()
                let resigned = await oauth.sign(request)
                return await performRequest(resigned)
            } catch {
                return .failure(.tokenExpired)
            }
        }
        return result
    }

    private func performRequest<T: Decodable & Sendable>(_ request: URLRequest) async -> Result<T, AppError> {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.unknown)
            }
            switch httpResponse.statusCode {
            case 200...299:
                guard !data.isEmpty else { return .failure(.emptyResponse) }
                do {
                    let decoded = try JSONDecoder().decode(T.self, from: data)
                    return .success(decoded)
                } catch let e {
                    return .failure(.decodingError(String(describing: e)))
                }
            case 401:
                return .failure(.apiError(statusCode: 401, message: "Unauthorized"))
            case 403:
                return .failure(.apiError(statusCode: 403, message: "Forbidden"))
            case 429:
                let retryAfter = Double(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "") ?? Self.defaultRetryAfterSeconds
                return .failure(.rateLimited(retryAfter: max(1, retryAfter)))
            case 500:
                return .failure(.serverError(statusCode: 500))
            case 502, 503:
                return .failure(.gatewayError(statusCode: httpResponse.statusCode))
            default:
                let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                return .failure(.apiError(statusCode: httpResponse.statusCode, message: msg))
            }
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return .failure(.offline)
            case .dnsLookupFailed, .cannotFindHost:
                return .failure(.dnsError)
            default:
                return .failure(.network(urlError))
            }
        } catch {
            return .failure(.unknown)
        }
    }
}
