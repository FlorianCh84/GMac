import Foundation

protocol DriveServiceProtocol: Sendable {
    func listFiles() async -> Result<[DriveFile], AppError>
    func uploadFile(data: Data, filename: String, mimeType: String) async -> Result<DriveFile, AppError>
    func downloadFile(id: String) async -> Result<Data, AppError>
}
