# GmailMac — Design Architecture Fiabilité
**Date :** 25 avril 2026
**Contexte :** 65% des switchers de clients mail partent à cause de bugs, sync cassée, emails qui disparaissent. Ce document définit l'architecture qui rend ces bugs structurellement impossibles.

---

## Décisions clés

| Décision | Choix | Raison |
|---|---|---|
| Source de vérité | Gmail API uniquement | Zéro mail perdu par design |
| Persistance locale | Aucune pour les données Gmail | Supprime toute une classe de bugs de sync |
| SwiftData | VoiceProfile + préférences uniquement | Données non-critiques seulement |
| Optimistic updates | Désactivés | L'UI ne ment jamais sur l'état réel |
| Envoi différé (UX) | Countdown 3s annulable avant appel API | Undo send — mail ne part jamais pendant le countdown |

---

## 1. Architecture en couches

```
┌─────────────────────────────────────┐
│           UI (SwiftUI)              │  Affiche l'état, envoie des intentions
├─────────────────────────────────────┤
│        ViewModels (@Observable)     │  Transforme l'état, orchestre les actions
├─────────────────────────────────────┤
│     Session Store (in-memory)       │  Cache session : threads, messages ouverts
├─────────────────────────────────────┤
│     Services (GmailService, AI…)    │  Appels API, logique métier
├─────────────────────────────────────┤
│     Network Layer (URLSession)      │  HTTP, auth, retry, rate limiting
├─────────────────────────────────────┤
│     SwiftData (VoiceProfile, prefs) │  Persistance locale UNIQUEMENT non-Gmail
└─────────────────────────────────────┘
```

**Règle stricte :** les couches du haut ne connaissent que la couche immédiatement en dessous. L'UI ne touche jamais URLSession. Les Services ne connaissent pas SwiftUI.

**Gestion d'erreurs :** chaque Service retourne `Result<T, AppError>` — jamais de `throws` non typé, jamais de force-unwrap (`!`).

```swift
enum AppError {
    case network(URLError)
    case apiError(statusCode: Int, message: String)
    case rateLimited(retryAfter: TimeInterval)
    case tokenExpired
    case offline
}
```

---

## 2. Session Store

`SessionStore` est une classe `@Observable` qui vit tant que l'app tourne — unique source de vérité en mémoire.

```swift
@Observable
final class SessionStore {
    // Données Gmail (jamais persistées sur disque)
    var threads: [EmailThread] = []
    var openMessages: [String: EmailMessage] = [:]
    var labels: [GmailLabel] = []
    var currentHistoryId: String = ""

    // État de navigation
    var selectedLabelId: String = "INBOX"
    var selectedThreadId: String? = nil

    // État des opérations en cours
    var pendingOperations: Set<String> = []
    var isLoading: Bool = false
    var lastSyncError: AppError? = nil
}
```

### Règle de mutation (invariant central du projet)

Toute écriture (archive, label, suppression) suit ce schéma :
1. Ajouter `threadId` à `pendingOperations` → UI affiche spinner, désactive les actions
2. Appeler l'API Gmail
3a. Succès → mettre à jour SessionStore + retirer de `pendingOperations`
3b. Échec → afficher l'erreur + retirer de `pendingOperations` (aucune mutation locale)

Jamais d'optimistic update. L'UI reflète toujours l'état confirmé par Gmail.

### Réconciliation via historyId

Après chaque opération réussie, récupérer `history.list?startHistoryId=X` pour mettre à jour le cache session. Beaucoup moins coûteux qu'un `threads.list` complet.

---

## 3. Envoi — Pattern Undo Send

```swift
enum SendState {
    case idle
    case countdown(progress: Double)   // 0.0 → 1.0 sur 3 secondes, annulable
    case sending                        // API en cours, non annulable
    case failed(AppError)              // erreur, composer reste ouvert
}
```

**Flux :**
1. Clic "Envoyer" → state passe à `.countdown(0.0)`
2. Barre de progression sur le bouton pendant 3 secondes
3. Bouton "Annuler" visible — annulation = retour à `.idle`, rien envoyé
4. Après 3s → state passe à `.sending`, API appelée
5. Succès → composer ferme, `historyId` réconcilié
6. Échec → state `.failed(error)`, composer reste ouvert avec le brouillon intact

Le mail ne touche jamais l'API pendant le countdown. Si l'app crashe pendant le countdown : Gmail intact.

---

## 4. Couche réseau — fiabilité structurelle

### Token refresh transparent

```swift
final class AuthenticatedHTTPClient: HTTPClientProtocol {
    func send<T: Decodable>(_ request: URLRequest) async -> Result<T, AppError> {
        var req = await tokenManager.sign(request)
        let result = await perform(req)
        if case .apiError(401, _) = result {
            await tokenManager.refresh()
            return await perform(tokenManager.sign(request))
        }
        return result
    }
}
```

### Backoff exponentiel

```swift
func withRetry<T>(
    maxAttempts: Int = 3,
    operation: () async -> Result<T, AppError>
) async -> Result<T, AppError> {
    for attempt in 0..<maxAttempts {
        let result = await operation()
        switch result {
        case .success: return result
        case .failure(.rateLimited(let delay)):
            try? await Task.sleep(for: .seconds(delay))
        case .failure(.network):
            try? await Task.sleep(for: .seconds(pow(2.0, Double(attempt))))
        case .failure:
            return result  // erreur non-retryable → remonte immédiatement
        }
    }
    return await operation()
}
```

### Annulation des requêtes en vol

```swift
private var loadTask: Task<Void, Never>?

func loadThread(_ id: String) {
    loadTask?.cancel()
    loadTask = Task { /* fetch */ }
}
```

---

## 5. Stratégie de tests

### Structure

```
Tests/
├── Unit/
│   ├── GmailServiceTests.swift
│   ├── SessionStoreTests.swift       // tester que pendingOperations libéré en cas d'erreur
│   ├── PromptBuilderTests.swift
│   ├── ToneContextResolverTests.swift
│   └── AppErrorTests.swift
├── Integration/
│   ├── GmailAPIIntegrationTests.swift
│   └── AuthFlowTests.swift
└── Mocks/
    ├── MockHTTPClient.swift
    └── MockGmailService.swift
```

### Protocol-driven mocks

```swift
protocol HTTPClientProtocol {
    func send<T: Decodable>(_ request: URLRequest) async -> Result<T, AppError>
}
```

Tout Service prend un `HTTPClientProtocol` en injection de dépendance. Tests unitaires sans internet.

### Règles de contribution (PR template)

- [ ] Nouveau Service → tests couvrent les cas d'erreur API (401, 429, 5xx)
- [ ] Nouvelle mutation → test que l'UI reste cohérente si l'API échoue
- [ ] Tout ViewModel avec mutation → test que `pendingOperations` libéré en cas d'erreur
- [ ] Aucun force-unwrap (`!`) — SwiftLint règle `force_unwrapping: error`

---

## 6. Structure projet

```
GmailMac/
├── App/
│   ├── GmailMacApp.swift
│   └── AppEnvironment.swift          // DI root — fichier d'entrée pour les contributeurs
├── Network/
│   ├── HTTPClientProtocol.swift
│   ├── AuthenticatedHTTPClient.swift
│   └── Endpoints.swift
├── Auth/
│   ├── GoogleOAuthManager.swift
│   └── KeychainService.swift
├── Services/
│   ├── GmailService.swift
│   ├── DriveService.swift
│   ├── SyncEngine.swift
│   └── AI/
│       ├── LLMProvider.swift
│       ├── Providers/
│       ├── ToneContextResolver.swift
│       ├── VoiceProfileAnalyzer.swift
│       └── PromptBuilder.swift
├── Store/
│   └── SessionStore.swift
├── Models/
│   ├── EmailThread.swift
│   ├── EmailMessage.swift
│   ├── GmailLabel.swift
│   ├── AppError.swift
│   └── VoiceProfile.swift            // SwiftData — seul modèle persisté
├── UI/
│   ├── Sidebar/
│   ├── ThreadList/
│   ├── MessageView/
│   ├── Compose/
│   ├── AIPanel/
│   ├── Settings/
│   └── Components/
└── Resources/
    └── Fixtures/                     // JSON réponses API sauvegardées pour les tests
```

## 7. Conventions open source

- `.swiftformat` + SwiftLint — style automatique, pas sujet à débat en PR
- `SwiftLint: force_unwrapping: error` — pas de `!` possible en prod
- `CONTRIBUTING.md` — règles de test + style
- GitHub Actions — build + tests sur chaque PR (macOS runner)
- `AppEnvironment.swift` — fichier d'entrée unique pour comprendre l'app entière

## 8. UI — Liquid Glass

Toute l'interface suit le langage visuel **Liquid Glass** (macOS/iOS 26 Tahoe). Implémentation via le skill `frontend-design` au moment des sprints UI.

---

## Résumé des garanties structurelles

| Risque | Garantie |
|---|---|
| Mail perdu | API-first : rien n'est "envoyé" tant que l'API ne répond pas 200 |
| Mail envoyé par erreur | Countdown 3s annulable avant tout appel API |
| UI bloquée après erreur réseau | `pendingOperations` libéré dans tous les cas (succès ET erreur) |
| Données Gmail corrompues en local | Zéro persistance Gmail sur disque |
| Crash sur token expiré | Refresh transparent, retry automatique |
| Boucle infinie de retry | Erreurs non-retryables remontent immédiatement |
| Force-unwrap crash | SwiftLint `force_unwrapping: error` bloque en CI |

---

*Document validé le 25 avril 2026 — à mettre à jour à chaque sprint.*
