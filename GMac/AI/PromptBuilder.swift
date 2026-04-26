import Foundation

enum PromptBuilder {

    // MARK: - Réponse dans un thread existant

    static func buildReplyPrompt(thread: EmailThread, instruction: UserInstruction, toneSource: ToneSource) -> LLMConversation {
        var c = LLMConversation()

        // Détecter si c'est le premier message ou une réponse dans un fil
        let isReplyInThread = thread.messages.count > 1

        var system = """
        Tu rédiges des réponses d'email au nom de l'utilisateur.

        RÈGLES STRICTES :
        - Corps uniquement. Pas de signature. Pas de "PS".
        - Ne jamais inventer d'engagements, de dates ou de faits absents de l'échange.
        - Ne pas reformuler les questions de l'interlocuteur.
        - Longueur : \(instruction.length.rawValue == "Concis" ? "3-5 lignes" : instruction.length.rawValue == "Équilibré" ? "6-10 lignes" : "10-20 lignes").
        """

        if let obj = instruction.objective { system += "\n- Objectif prioritaire : \(obj.rawValue)." }
        if let tone = instruction.tone { system += "\n- Ton : \(tone.rawValue)." }
        system += "\n- Si l'instruction utilisateur contredit la longueur ou le ton, l'instruction utilisateur prime."

        system += """

        GESTION DE LA SALUTATION :
        """
        if isReplyInThread {
            system += "\n- Fil existant : pas de salutation."
        } else {
            let toneName = instruction.tone?.rawValue ?? "Équilibré"
            if toneName == "Formel" || toneName == "Diplomate" {
                system += "\n- Premier message, ton \(toneName) → \"Bonjour [Prénom],\" ou \"Bonjour M./Mme [Nom],\""
            } else {
                system += "\n- Premier message → \"Bonjour [Prénom],\" (ou \"Salut [Prénom],\" si relation décontractée établie)"
            }
            system += "\n- En cas de doute → \"Bonjour [Prénom],\""
            system += "\n- Ne jamais utiliser \"Madame, Monsieur,\" sauf destinataire inconnu et contexte très institutionnel."
        }

        c.append(role: .system, content: system)

        // Few-shot si exemples disponibles
        let examples = toneSource.examples.prefix(3)
        if !examples.isEmpty {
            let ex = examples.map { "---\n\($0.bodyPlain ?? $0.snippet)" }.joined(separator: "\n")
            c.append(role: .user, content: "Voici des exemples de ma façon d'écrire :\n\(ex)\n\nÉcris dans ce même style.")
            c.append(role: .assistant, content: "Compris.")
        }

        let ctx = buildThreadContext(thread)
        let userMsg = """
        Échange email :
        \(ctx)

        Instruction : \(instruction.freeText.isEmpty ? "Réponds de façon appropriée" : instruction.freeText)
        """
        c.append(role: .user, content: userMsg)
        return c
    }

    // MARK: - Nouveau mail (premier d'un échange)

    static func buildNewEmailPrompt(
        recipientName: String,
        recipientInfo: String,
        contactContext: String,
        instruction: UserInstruction,
        toneSource: ToneSource
    ) -> LLMConversation {
        var c = LLMConversation()

        let toneName = instruction.tone?.rawValue ?? "Direct"
        var system = """
        Tu rédiges un email initial (premier contact ou relance sans fil existant) au nom de l'utilisateur.

        RÈGLES STRICTES :
        - Inclure une salutation d'ouverture adaptée (voir règles ci-dessous).
        - Corps uniquement ensuite. Pas de signature.
        - Ne jamais inventer d'engagements, de dates ou de faits non fournis.
        - Longueur : \(instruction.length.rawValue == "Concis" ? "3-5 lignes" : instruction.length.rawValue == "Équilibré" ? "6-10 lignes" : "10-20 lignes").
        """
        if let obj = instruction.objective { system += "\n- Objectif : \(obj.rawValue)." }
        system += "\n- Ton : \(toneName)."

        system += """

        RÈGLES DE SALUTATION (priorité décroissante) :
        1. Si l'historique indique des échanges décontractés (tutoiement, "Salut", emojis) → "Salut [Prénom],"
        2. Si relation établie mais formelle → "Bonjour [Prénom],"
        3. Si premier contact absolu ou ton Formel → "Bonjour M./Mme [Nom]," ou "Bonjour [Prénom]," selon le contexte
        4. En cas de doute → "Bonjour [Prénom],"
        Ne jamais utiliser "Madame, Monsieur," sauf destinataire inconnu et contexte très institutionnel.
        """

        c.append(role: .system, content: system)

        let examples = toneSource.examples.prefix(3)
        if !examples.isEmpty {
            let ex = examples.map { "---\n\($0.bodyPlain ?? $0.snippet)" }.joined(separator: "\n")
            c.append(role: .user, content: "Voici des exemples de ma façon d'écrire :\n\(ex)\n\nÉcris dans ce même style.")
            c.append(role: .assistant, content: "Compris.")
        }

        let userMsg = """
        Destinataire : \(recipientName)\(recipientInfo.isEmpty ? "" : " — \(recipientInfo)")
        Historique de contact : \(contactContext.isEmpty ? "Aucun" : contactContext)
        Contexte / objet du mail : \(instruction.freeText.isEmpty ? "À déterminer selon le contexte" : instruction.freeText)
        """
        c.append(role: .user, content: userMsg)
        return c
    }

    // MARK: - Analyse stratégique

    static func buildOpinionPrompt(thread: EmailThread) -> LLMConversation {
        var c = LLMConversation()
        let system = """
        Tu analyses des échanges email de façon objective et stratégique.
        Réponds TOUJOURS avec cette structure exacte, en markdown :

        **Ton & intention** : [1-2 phrases]
        **Points de tension / ambiguïtés** : [bullet points]
        **Enjeux sous-jacents** : [bullet points]
        **Ce que l'interlocuteur attend réellement** : [1-2 phrases]
        **Signaux faibles (non-dits, absences notables)** : [bullet points ou "Aucun détecté"]
        **Recommandations pour la suite** : [2-3 actions concrètes numérotées]

        Longueur totale : 150-250 mots. Sois direct, sans formules de politesse.
        """
        c.append(role: .system, content: system)
        c.append(role: .user, content: "Analyse cet échange :\n\n\(buildThreadContext(thread))")
        return c
    }

    // MARK: - Affinage

    static func buildRefinementPrompt(existing: LLMConversation, instruction: String) -> LLMConversation {
        var c = existing
        // Injecter les règles d'affinage dans le system si pas déjà présent
        let refinementSystemNote = """

        [Mode affinage] Applique UNIQUEMENT l'instruction suivante. \
        Ne modifie pas ce qui n'est pas concerné. \
        Retourne le draft complet modifié. \
        Conserve la salutation sauf instruction explicite contraire. \
        Aucun commentaire autour du draft.
        """
        if var firstSystem = c.messages.first, firstSystem.role == .system {
            // Append note to existing system message
            let updatedContent = firstSystem.content + refinementSystemNote
            firstSystem.content = updatedContent
            c.messages[0] = firstSystem
        }
        c.append(role: .user, content: instruction)
        return c
    }

    // MARK: - Private

    private static func buildThreadContext(_ thread: EmailThread) -> String {
        thread.messages.suffix(5).map { "De : \($0.from)\n\($0.bodyPlain ?? $0.snippet)" }.joined(separator: "\n---\n")
    }
}
