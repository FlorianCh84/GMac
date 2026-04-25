import Foundation

struct DriveFile: Identifiable, Decodable, Sendable, Equatable {
    let id: String
    let name: String
    let mimeType: String
    let size: String?
    let modifiedTime: String?
    var parents: [String]? = nil   // dossier parent

    var sizeBytes: Int64 { Int64(size ?? "0") ?? 0 }
    var isFolder: Bool { mimeType == "application/vnd.google-apps.folder" }
}

struct DriveFileListResponse: Decodable, Sendable {
    let files: [DriveFile]?   // optionnel — absent si résultat vide
    let nextPageToken: String?
}
