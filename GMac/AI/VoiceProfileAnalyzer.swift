import Foundation

final class VoiceProfileAnalyzer: Sendable {
    private let provider: any LLMProvider

    init(provider: any LLMProvider) {
        self.provider = provider
    }

    func analyze(sentMessages: [EmailMessage]) async throws -> VoiceProfileData {
        guard !sentMessages.isEmpty else {
            return VoiceProfileData(
                formalityLevel: "semi-formel", sentenceStructure: "mixte",
                averageEmailLength: nil,
                greetingPatterns: [], closingPatterns: [], vocabulary: "standard",
                paragraphStyle: "court", usesLists: nil, humorLevel: nil,
                writingRhythm: nil, specificExpressions: [], thingsToAvoid: [],
                contactRelationshipHints: nil
            )
        }

        let samples = sentMessages.prefix(30).compactMap { $0.bodyPlain ?? $0.snippet }.filter { !$0.isEmpty }
        let emailsText = samples.prefix(15).enumerated()
            .map { "---Email \($0.offset + 1)---\n\($0.element)" }
            .joined(separator: "\n")

        let prompt = """
        Analyse ces emails envoyés et décris précisément le style d'écriture de leur auteur.

        CONTRAINTES :
        - Réponds UNIQUEMENT avec un JSON valide.
        - Aucun markdown, aucun texte avant ou après le JSON.
        - Les champs "thingsToAvoid" et "specificExpressions" doivent contenir des exemples concrets tirés des emails, pas des généralités.
        - Pour "averageEmailLength", base-toi sur une estimation objective des emails fournis.
        - Pour "greetingPatterns" et "closingPatterns", liste uniquement les formules réellement présentes.

        Format requis :
        {
          "formalityLevel": "formel|semi-formel|informel",
          "sentenceStructure": "courtes|longues|mixtes",
          "averageEmailLength": "très court (<50 mots)|court (50-100 mots)|moyen (100-200 mots)|long (>200 mots)",
          "greetingPatterns": ["Bonjour [Prénom],", "Salut [Prénom],"],
          "closingPatterns": ["Bonne journée,", "Cordialement,"],
          "vocabulary": "soutenu|courant|familier",
          "paragraphStyle": "court|développé|mixte",
          "usesLists": true,
          "humorLevel": "absent|rare|occasionnel|fréquent",
          "writingRhythm": "direct (va droit au but)|contextuel (pose le cadre avant)|mixte",
          "specificExpressions": ["expression réellement trouvée dans les emails"],
          "thingsToAvoid": ["comportement précis avec exemple tiré des emails"],
          "contactRelationshipHints": {
            "tutoiementContacts": ["prénom1", "prénom2"],
            "vouvoiementContacts": ["prénom1"],
            "informalGreetingContacts": ["prénom1"]
          }
        }

        Emails :
        \(emailsText)
        """

        var conversation = LLMConversation()
        conversation.append(role: .user, content: prompt)
        let response = try await provider.refine(conversation: conversation, instruction: prompt)
        return try parseVoiceProfileJSON(response)
    }

    private func parseVoiceProfileJSON(_ json: String) throws -> VoiceProfileData {
        let cleaned = json
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else {
            throw LLMError.decodingFailed("Cannot encode JSON string")
        }
        return try JSONDecoder().decode(VoiceProfileData.self, from: data)
    }
}

struct VoiceProfileData: Decodable, Sendable {
    let formalityLevel: String
    let sentenceStructure: String
    let averageEmailLength: String?
    let greetingPatterns: [String]
    let closingPatterns: [String]
    let vocabulary: String
    let paragraphStyle: String
    let usesLists: Bool?
    let humorLevel: String?
    let writingRhythm: String?
    let specificExpressions: [String]
    let thingsToAvoid: [String]
    let contactRelationshipHints: ContactRelationshipHints?

    struct ContactRelationshipHints: Decodable, Sendable {
        let tutoiementContacts: [String]?
        let vouvoiementContacts: [String]?
        let informalGreetingContacts: [String]?
    }

    func applyTo(_ profile: VoiceProfile) {
        profile.formalityLevel = formalityLevel
        profile.sentenceStructure = sentenceStructure
        profile.averageEmailLength = averageEmailLength ?? ""
        profile.greetingPatterns = greetingPatterns
        profile.closingPatterns = closingPatterns
        profile.vocabulary = vocabulary
        profile.paragraphStyle = paragraphStyle
        profile.usesLists = usesLists ?? false
        profile.humorLevel = humorLevel ?? ""
        profile.writingRhythm = writingRhythm ?? ""
        profile.specificExpressions = specificExpressions
        profile.thingsToAvoid = thingsToAvoid
        profile.tutoiementContacts = contactRelationshipHints?.tutoiementContacts ?? []
        profile.vouvoiementContacts = contactRelationshipHints?.vouvoiementContacts ?? []
        profile.informalGreetingContacts = contactRelationshipHints?.informalGreetingContacts ?? []
        profile.lastUpdated = Date()
    }
}
