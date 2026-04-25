import Foundation
import Observation

@Observable
@MainActor
final class DrivePickerViewModel {
    var files: [DriveFile] = []
    var isLoading: Bool = false
    var lastError: AppError? = nil

    private let driveService: any DriveServiceProtocol

    init(driveService: any DriveServiceProtocol) {
        self.driveService = driveService
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let result = await driveService.listFiles()
        switch result {
        case .success(let f): files = f
        case .failure(let e): lastError = e
        }
    }
}
