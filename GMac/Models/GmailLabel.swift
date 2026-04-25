struct GmailLabel: Identifiable, Hashable, Decodable {
    let id: String
    let name: String
    let type: LabelType
    let messagesUnread: Int?

    enum LabelType: String, Decodable {
        case system
        case user
    }
}
