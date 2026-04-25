import Foundation

enum PromptBuilder {

    static func buildReplyPrompt(thread: EmailThread, instruction: UserInstruction, toneSource: ToneSource) -> LLMConversation {
        var c = LLMConversation()
        var system = "Tu es un assistant qui rédige des réponses d'email au nom de l'utilisateur."
        system += " Écris uniquement le corps du message, sans salutation ni signature."
        system += " Longueur : \(instruction.length.rawValue)."
        if let obj = instruction.objective { system += " Objectif : \(obj.rawValue)." }
        if let tone = instruction.tone { system += " Ton : \(tone.rawValue)." }
        c.append(role: .system, content: system)

        let examples = toneSource.examples.prefix(3)
        if !examples.isEmpty {
            let ex = examples.map { "---\n\($0.bodyPlain ?? $0.snippet)" }.joined(separator: "\n")
            c.append(role: .user, content: "Voici des exemples de ma façon d'écrire :\n\(ex)\n\nÉcris dans ce même style.")
            c.append(role: .assistant, content: "Compris, je vais écrire dans ce style.")
        }

        let ctx = buildThreadContext(thread)
        let userMsg = "Échange email :\n\(ctx)\n\nInstruction : \(instruction.freeText.isEmpty ? "Réponds de façon appropriée" : instruction.freeText)"
        c.append(role: .user, content: userMsg)
        return c
    }

    static func buildOpinionPrompt(thread: EmailThread) -> LLMConversation {
        var c = LLMConversation()
        c.append(role: .system, content: "Tu analyses des échanges email de façon objective et stratégique. Identifie : le ton et l'intention de l'interlocuteur, les points de tension ou ambiguïtés, les enjeux sous-jacents, ce que l'interlocuteur attend réellement, et des recommandations stratégiques pour la suite. Sois direct et concis.")
        c.append(role: .user, content: "Analyse cet échange :\n\n\(buildThreadContext(thread))")
        return c
    }

    static func buildRefinementPrompt(existing: LLMConversation, instruction: String) -> LLMConversation {
        var c = existing
        c.append(role: .user, content: instruction)
        return c
    }

    private static func buildThreadContext(_ thread: EmailThread) -> String {
        thread.messages.suffix(5).map { "De : \($0.from)\n\($0.bodyPlain ?? $0.snippet)" }.joined(separator: "\n---\n")
    }
}
