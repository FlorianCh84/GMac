import Foundation

struct DriveFile: Identifiable, Decodable, Sendable, Equatable {
    let id: String
    let name: String
    let mimeType: String
    let size: String?
    let modifiedTime: String?

    var sizeBytes: Int64 { Int64(size ?? "0") ?? 0 }
}

struct DriveFileListResponse: Decodable, Sendable {
    let files: [DriveFile]
    let nextPageToken: String?
}
