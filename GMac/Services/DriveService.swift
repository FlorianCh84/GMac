import Foundation

final class DriveService: DriveServiceProtocol, @unchecked Sendable {
    private let httpClient: any HTTPClientProtocol

    init(httpClient: any HTTPClientProtocol) {
        self.httpClient = httpClient
    }

    func listFiles() async -> Result<[DriveFile], AppError> {
        let result: Result<DriveFileListResponse, AppError> = await httpClient.send(URLRequest(url: Endpoints.driveFilesList()))
        return result.map { $0.files }
    }

    func uploadFile(data: Data, filename: String, mimeType: String) async -> Result<DriveFile, AppError> {
        let boundary = "GMacDrive_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var request = URLRequest(url: Endpoints.driveFilesUpload())
        request.httpMethod = "POST"
        request.setValue("multipart/related; boundary=\"\(boundary)\"", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildMultipartBody(data: data, filename: filename, mimeType: mimeType, boundary: boundary)
        return await httpClient.send(request)
    }

    func downloadFile(id: String) async -> Result<Data, AppError> {
        // Drive retourne du contenu brut, pas JSON — non supporté par HTTPClientProtocol générique
        // Implémentation directe URLSession nécessaire pour les binaires
        return .failure(.unknown)
    }

    private func buildMultipartBody(data: Data, filename: String, mimeType: String, boundary: String) -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        let crlf = "\r\n"
        append("--\(boundary)\(crlf)")
        append("Content-Type: application/json; charset=UTF-8\(crlf)\(crlf)")
        append("{\"name\":\"\(filename)\",\"mimeType\":\"\(mimeType)\"}")
        append(crlf)
        append("--\(boundary)\(crlf)")
        append("Content-Type: \(mimeType)\(crlf)\(crlf)")
        body.append(data)
        append(crlf)
        append("--\(boundary)--\(crlf)")
        return body
    }
}
