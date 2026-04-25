import Foundation

protocol DriveServiceProtocol: Sendable {
    func listFiles(parentId: String?) async -> Result<[DriveFile], AppError>
    func uploadFile(data: Data, filename: String, mimeType: String) async -> Result<DriveFile, AppError>
    func downloadFile(id: String) async -> Result<Data, AppError>
    func exportGoogleFile(id: String, mimeType: String) async -> Result<Data, AppError>
}
