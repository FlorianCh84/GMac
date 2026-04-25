import Foundation

struct Attachment: Identifiable, Sendable {
    let id: UUID
    let filename: String
    let mimeType: String
    let data: Data

    var sizeDescription: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(data.count))
    }
}
