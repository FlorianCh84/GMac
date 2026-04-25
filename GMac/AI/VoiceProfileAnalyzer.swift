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
                greetingPatterns: [], closingPatterns: [], vocabulary: "standard",
                paragraphStyle: "court", specificExpressions: [], thingsToAvoid: []
            )
        }

        let samples = sentMessages.prefix(30).compactMap { $0.bodyPlain ?? $0.snippet }.filter { !$0.isEmpty }
        let emailsText = samples.prefix(15).enumerated()
            .map { "---Email \($0.offset + 1)---\n\($0.element)" }
            .joined(separator: "\n")

        let prompt = """
        Analyse ces emails envoyés et décris le style d'écriture de leur auteur.
        Réponds UNIQUEMENT avec un JSON valide sans markdown ni texte supplémentaire.
        Format requis :
        {
          "formalityLevel": "formel|semi-formel|informel",
          "sentenceStructure": "courtes|longues|mixtes",
          "greetingPatterns": ["formule1"],
          "closingPatterns": ["formule1"],
          "vocabulary": "soutenu|courant|familier",
          "paragraphStyle": "court|développé|mixte",
          "specificExpressions": ["expression"],
          "thingsToAvoid": ["chose"]
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
    let greetingPatterns: [String]
    let closingPatterns: [String]
    let vocabulary: String
    let paragraphStyle: String
    let specificExpressions: [String]
    let thingsToAvoid: [String]

    func applyTo(_ profile: VoiceProfile) {
        profile.formalityLevel = formalityLevel
        profile.sentenceStructure = sentenceStructure
        profile.greetingPatterns = greetingPatterns
        profile.closingPatterns = closingPatterns
        profile.vocabulary = vocabulary
        profile.paragraphStyle = paragraphStyle
        profile.specificExpressions = specificExpressions
        profile.thingsToAvoid = thingsToAvoid
        profile.lastUpdated = Date()
    }
}
