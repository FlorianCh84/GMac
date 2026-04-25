import Foundation
import Observation

struct DriveBreadcrumb: Sendable {
    let id: String?   // nil = root
    let name: String
}

@Observable
@MainActor
final class DrivePickerViewModel {
    var files: [DriveFile] = []
    var isLoading: Bool = false
    var lastError: AppError? = nil
    var breadcrumbs: [DriveBreadcrumb] = [DriveBreadcrumb(id: nil, name: "Mon Drive")]

    private let driveService: any DriveServiceProtocol

    init(driveService: any DriveServiceProtocol) {
        self.driveService = driveService
    }

    var currentFolderId: String? { breadcrumbs.last?.id ?? nil }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let result = await driveService.listFiles(parentId: currentFolderId)
        switch result {
        case .success(let f): files = f
        case .failure(let e): lastError = e
        }
    }

    func navigateInto(folder: DriveFile) async {
        breadcrumbs.append(DriveBreadcrumb(id: folder.id, name: folder.name))
        await load()
    }

    func navigateTo(breadcrumb: DriveBreadcrumb) async {
        if let idx = breadcrumbs.firstIndex(where: { $0.id == breadcrumb.id && $0.name == breadcrumb.name }) {
            breadcrumbs = Array(breadcrumbs.prefix(idx + 1))
        }
        await load()
    }
}
