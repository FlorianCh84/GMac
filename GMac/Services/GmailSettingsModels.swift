import Foundation

struct SendAsAlias: Decodable, Sendable {
    let sendAsEmail: String
    let displayName: String?
    let signature: String?
    let isDefault: Bool?
    let isPrimary: Bool?
}

struct SendAsListResponse: Decodable, Sendable {
    let sendAs: [SendAsAlias]
}

struct UpdateSignatureRequest: Encodable, Sendable {
    let signature: String

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(signature, forKey: .signature)
    }
    enum CodingKeys: String, CodingKey { case signature }
}

struct VacationSettings: Codable, Sendable {
    var enableAutoReply: Bool
    var responseSubject: String?
    var responseBodyPlainText: String?
    var responseBodyHtml: String?
    var startTime: String?
    var endTime: String?
    var restrictToContacts: Bool?
    var restrictToDomain: Bool?

    enum CodingKeys: String, CodingKey {
        case enableAutoReply, responseSubject, responseBodyPlainText, responseBodyHtml
        case startTime, endTime, restrictToContacts, restrictToDomain
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enableAutoReply, forKey: .enableAutoReply)
        try c.encodeIfPresent(responseSubject, forKey: .responseSubject)
        try c.encodeIfPresent(responseBodyPlainText, forKey: .responseBodyPlainText)
        try c.encodeIfPresent(responseBodyHtml, forKey: .responseBodyHtml)
        try c.encodeIfPresent(startTime, forKey: .startTime)
        try c.encodeIfPresent(endTime, forKey: .endTime)
        try c.encodeIfPresent(restrictToContacts, forKey: .restrictToContacts)
        try c.encodeIfPresent(restrictToDomain, forKey: .restrictToDomain)
    }
}

struct CreateLabelRequest: Encodable, Sendable {
    let name: String
    let labelListVisibility: String
    let messageListVisibility: String

    init(name: String) {
        self.name = name
        self.labelListVisibility = "labelShow"
        self.messageListVisibility = "show"
    }
}

struct UpdateLabelRequest: Encodable, Sendable {
    let name: String
}
