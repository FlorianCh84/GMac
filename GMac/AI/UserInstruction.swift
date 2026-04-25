import Foundation

enum ReplyObjective: String, CaseIterable, Sendable, Identifiable {
    var id: String { rawValue }
    case conclude = "Conclure"
    case negotiate = "Négocier"
    case inform = "Informer"
    case refusePolitely = "Refuser poliment"
    case followUp = "Relancer"
    case clarify = "Clarifier"
    case thank = "Remercier"
}

enum ReplyTone: String, CaseIterable, Sendable, Identifiable {
    var id: String { rawValue }
    case formal = "Formel"
    case warm = "Chaleureux"
    case direct = "Direct"
    case firm = "Ferme"
    case diplomatic = "Diplomate"
    case conciliatory = "Conciliant"
}

enum ReplyLength: String, CaseIterable, Sendable, Identifiable {
    var id: String { rawValue }
    case concise = "Concis"
    case balanced = "Équilibré"
    case detailed = "Détaillé"
}

struct UserInstruction: Sendable {
    let freeText: String
    let objective: ReplyObjective?
    let tone: ReplyTone?
    let length: ReplyLength
    let senderEmail: String
    let toneExamples: [EmailMessage]

    init(freeText: String, objective: ReplyObjective? = nil, tone: ReplyTone? = nil,
         length: ReplyLength = .balanced, senderEmail: String = "", toneExamples: [EmailMessage] = []) {
        self.freeText = freeText; self.objective = objective; self.tone = tone
        self.length = length; self.senderEmail = senderEmail; self.toneExamples = toneExamples
    }
}
