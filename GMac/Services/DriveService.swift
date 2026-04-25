import Foundation

final class DriveService: DriveServiceProtocol, @unchecked Sendable {
    private let httpClient: any HTTPClientProtocol

    init(httpClient: any HTTPClientProtocol) {
        self.httpClient = httpClient
    }

    func listFiles() async -> Result<[DriveFile], AppError> {
        let request = URLRequest(url: Endpoints.driveFilesList())
        let result: Result<DriveFileListResponse, AppError> = await httpClient.send(request)
        switch result {
        case .success(let response):
            let files = response.files ?? []
            print("[GMac] Drive listFiles: \(files.count) fichier(s) trouvé(s)")
            return .success(files)
        case .failure(let error):
            print("[GMac] Drive listFiles error: \(error)")
            return .failure(error)
        }
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
        // Drive download nécessite une réponse binaire, pas JSON
        // On utilise le httpClient sous-jacent si c'est un AuthenticatedHTTPClient
        guard let authenticatedClient = httpClient as? AuthenticatedHTTPClient else {
            return .failure(.unknown)
        }
        let request = URLRequest(url: Endpoints.driveFileDownload(id: id))
        return await authenticatedClient.downloadRaw(request)
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
