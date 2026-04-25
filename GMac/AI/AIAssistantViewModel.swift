import Foundation
import Observation

enum AIAssistantState: Sendable {
    case idle
    case generating
    case done(String)
    case opinionDone(String)
    case failed(String)
}

@Observable
@MainActor
final class AIAssistantViewModel {
    var state: AIAssistantState = .idle
    var freeText: String = ""
    var selectedObjective: ReplyObjective? = nil
    var selectedTone: ReplyTone? = nil
    var selectedLength: ReplyLength = .balanced
    var refinementText: String = ""
    var toneSource: ToneSource = .globalProfile
    private(set) var conversation: LLMConversation = LLMConversation()

    var streamingText: String = ""

    private let provider: any LLMProvider

    init(provider: any LLMProvider) { self.provider = provider }

    var generatedText: String? {
        if case .done(let t) = state { return t }
        return nil
    }

    var isGenerating: Bool {
        if case .generating = state { return true }
        return false
    }

    func generate(thread: EmailThread, senderEmail: String, sentMessages: [EmailMessage]) async {
        state = .generating
        toneSource = ToneContextResolver.resolve(thread: thread, sentMessages: sentMessages)
        let instruction = UserInstruction(freeText: freeText, objective: selectedObjective, tone: selectedTone,
                                          length: selectedLength, senderEmail: senderEmail, toneExamples: toneSource.examples)
        do {
            conversation = PromptBuilder.buildReplyPrompt(thread: thread, instruction: instruction, toneSource: toneSource)
            let response = try await provider.generateReply(thread: thread, instruction: instruction)
            conversation.append(role: .assistant, content: response)
            state = .done(response)
        } catch LLMError.noAPIKey {
            state = .failed("Clé API \(provider.type.rawValue) manquante. Allez dans Paramètres → Assistant IA, entrez la clé et cliquez 'Sauvegarder les clés'.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func generateStreaming(thread: EmailThread, senderEmail: String, sentMessages: [EmailMessage]) async {
        state = .generating
        streamingText = ""
        toneSource = ToneContextResolver.resolve(thread: thread, sentMessages: sentMessages)
        let instruction = UserInstruction(freeText: freeText, objective: selectedObjective, tone: selectedTone,
                                          length: selectedLength, senderEmail: senderEmail, toneExamples: toneSource.examples)
        do {
            var accumulated = ""
            conversation = PromptBuilder.buildReplyPrompt(thread: thread, instruction: instruction, toneSource: toneSource)
            for try await chunk in provider.generateReplyStream(thread: thread, instruction: instruction) {
                accumulated += chunk
                streamingText = accumulated
                state = .done(accumulated)
            }
            conversation.append(role: .assistant, content: accumulated)
            if accumulated.isEmpty { state = .failed("Réponse vide reçue.") }
        } catch LLMError.noAPIKey {
            state = .failed("Clé API \(provider.type.rawValue) manquante. Allez dans Paramètres → Assistant IA, entrez la clé et cliquez 'Sauvegarder les clés'.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func requestOpinion(thread: EmailThread) async {
        state = .generating
        do {
            state = .opinionDone(try await provider.requestOpinion(thread: thread))
        } catch LLMError.noAPIKey {
            state = .failed("Clé API manquante.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func refine(thread: EmailThread) async {
        guard case .done = state, !refinementText.isEmpty else { return }
        state = .generating
        // Snapshot de l'instruction avant de la vider
        let instruction = refinementText
        do {
            // Ajouter le tour user AVANT l'appel réseau
            conversation.append(role: .user, content: instruction)
            let refined = try await provider.refine(conversation: conversation, instruction: instruction)
            conversation.append(role: .assistant, content: refined)
            refinementText = ""
            state = .done(refined)
        } catch LLMError.noAPIKey {
            state = .failed("Clé API \(provider.type.rawValue) manquante. Allez dans Paramètres → Assistant IA, entrez la clé et cliquez 'Sauvegarder les clés'.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func reset() {
        state = .idle; freeText = ""; selectedObjective = nil; selectedTone = nil
        selectedLength = .balanced; refinementText = ""; conversation = LLMConversation()
    }
}
