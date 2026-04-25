import Foundation
@testable import GMac

final class MockDriveService: DriveServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _listResult: Result<[DriveFile], AppError> = .success([])
    private var _uploadResult: Result<DriveFile, AppError> = .failure(.unknown)
    private var _downloadResult: Result<Data, AppError> = .failure(.unknown)

    func stubList(_ r: Result<[DriveFile], AppError>) { lock.withLock { _listResult = r } }
    func stubUpload(_ r: Result<DriveFile, AppError>) { lock.withLock { _uploadResult = r } }
    func stubDownload(_ r: Result<Data, AppError>) { lock.withLock { _downloadResult = r } }

    func listFiles() async -> Result<[DriveFile], AppError> { lock.withLock { _listResult } }
    func uploadFile(data: Data, filename: String, mimeType: String) async -> Result<DriveFile, AppError> { lock.withLock { _uploadResult } }
    func downloadFile(id: String) async -> Result<Data, AppError> { lock.withLock { _downloadResult } }
    func exportGoogleFile(id: String, mimeType: String) async -> Result<Data, AppError> { lock.withLock { _downloadResult } }
}
