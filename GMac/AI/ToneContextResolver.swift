import Foundation

enum ToneSource: Sendable {
    case currentThread([EmailMessage])
    case knownSender(email: String, [EmailMessage])
    case sameDomain(domain: String, [EmailMessage])
    case similarSubject([EmailMessage])
    case globalProfile

    var label: String {
        switch self {
        case .currentThread: return "Ton de cet échange"
        case .knownSender(let email, _): return "Ton avec \(email)"
        case .sameDomain(let domain, _): return "Ton avec \(domain)"
        case .similarSubject: return "Ton de tes échanges similaires"
        case .globalProfile: return "Ton général"
        }
    }

    var examples: [EmailMessage] {
        switch self {
        case .currentThread(let msgs): return msgs
        case .knownSender(_, let msgs): return msgs
        case .sameDomain(_, let msgs): return msgs
        case .similarSubject(let msgs): return msgs
        case .globalProfile: return []
        }
    }
}

enum ToneContextResolver {
    static func resolve(thread: EmailThread, sentMessages: [EmailMessage]) -> ToneSource {
        let senderEmail = thread.messages.first?.from ?? ""
        let senderDomain = senderEmail.components(separatedBy: "@").last ?? ""

        // Priority 1 : réponses déjà envoyées dans ce thread (pas INBOX)
        let threadReplies = thread.messages.filter { !$0.labelIds.contains("INBOX") && $0.from != senderEmail }
        if !threadReplies.isEmpty {
            return .currentThread(threadReplies)
        }

        // Priority 2 : emails envoyés à cet expéditeur
        let toSender = sentMessages.filter { $0.to.contains(senderEmail) }
        if !toSender.isEmpty {
            return .knownSender(email: senderEmail, toSender)
        }

        // Priority 3 : emails au même domaine
        if !senderDomain.isEmpty {
            let toDomain = sentMessages.filter { $0.to.contains(where: { $0.hasSuffix("@\(senderDomain)") }) }
            if !toDomain.isEmpty {
                return .sameDomain(domain: senderDomain, toDomain)
            }
        }

        // Priority 4 : sujet similaire (mots > 3 chars en commun)
        let subjectWords = Set(thread.subject.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { $0.count > 3 })
        let similar = sentMessages.filter { msg in
            let words = Set(msg.subject.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { $0.count > 3 })
            return !subjectWords.intersection(words).isEmpty
        }
        if !similar.isEmpty { return .similarSubject(Array(similar.prefix(5))) }

        return .globalProfile
    }
}
