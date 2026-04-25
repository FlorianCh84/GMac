# GmailMac — Spécification Technique v1.1

**Client mail natif macOS avec IA intégrée**
Florian Chambolle — agence810.fr — Avril 2026
*Projet open source — usage personnel initial*

---

## Table des matières

1. [Vision & Objectifs](#1-vision--objectifs)
2. [Architecture Générale](#2-architecture-générale)
3. [Modules Fonctionnels](#3-modules-fonctionnels)
4. [Assistant IA](#4-assistant-ia)
5. [Système de Ton de Voix](#5-système-de-ton-de-voix)
6. [UX Flow — Réponse Assistée par IA](#6-ux-flow--réponse-assistée-par-ia)
7. [Confidentialité & Sécurité](#7-confidentialité--sécurité)
8. [Analyse des Frictions du Marché](#8-analyse-des-frictions-du-marché)
9. [Roadmap — Sprints](#9-roadmap--sprints)
10. [Points de Vigilance Techniques](#10-points-de-vigilance-techniques)

---

## 1. Vision & Objectifs

GmailMac est un client mail natif macOS conçu pour les utilisateurs de Gmail qui veulent retrouver l'ergonomie de l'interface web Gmail tout en bénéficiant d'une intégration profonde avec l'environnement macOS (notifications natives, Keychain, SwiftUI). La différenciation clé est l'assistant IA contextuel qui comprend le ton de l'utilisateur et ses intentions pour générer des réponses alignées.

### 1.1 Positionnement

| App | Natif macOS | Gmail API | IA intégrée | Prix/an | Open source |
|---|---|---|---|---|---|
| Mimestream | ✅ | ✅ | ❌ | $120 | ❌ |
| Airmail | ✅ | ✔ IMAP | ❌ | $10 | ❌ |
| Spark | ✅ | ✔ IMAP | Partiel | $60 | ❌ |
| Superhuman | ❌ Electron | ✅ | Oui | $360 | ❌ |
| **GmailMac** | **✅ SwiftUI** | **✅** | **✅ Multi-LLM** | **Gratuit** | **✅ MIT** |

### 1.2 Principes directeurs

- **Natif macOS avant tout** — SwiftUI, Keychain, notifications natives, menu bar
- **Zéro friction IA** — aucun copier-coller, les suggestions s'insèrent directement dans le composeur
- **Respect du ton de l'utilisateur** — le LLM écrit comme lui, pas comme un générateur de texte
- **Open source** — code propre, architecturé, documenté
- **Privacy first** — les données Gmail ne partent vers les LLMs que sur action explicite
- **IA opt-in** — jamais forcée, toujours consentie, avec les clés API de l'utilisateur

---

## 2. Architecture Générale

### 2.1 Stack technique

| Couche | Technologie | Justification |
|---|---|---|
| UI | SwiftUI + AppKit (hybrid) | Natif macOS, performances, HIG |
| Rendu HTML | WKWebView (WebKit) | Seule option viable pour les emails HTML complexes |
| Données locales | SwiftData | Cache emails, profil de voix, préférences |
| Auth | OAuth 2.0 + macOS Keychain | Tokens sécurisés, refresh automatique |
| API mail | Gmail REST API v1 | Support des features Gmail spécifiques (labels, scheduled send…) |
| API fichiers | Google Drive API v3 | Réutilise l'OAuth Google existant |
| Async | Swift Concurrency (async/await) | Natif Swift 5.9+, intégration SwiftUI |

### 2.2 Structure du projet

```
GmailMac/
├── App/
│   ├── GmailMacApp.swift              # Entry point
│   └── AppEnvironment.swift           # DI container global
├── Auth/
│   ├── GoogleOAuthManager.swift       # OAuth2 + token refresh
│   └── KeychainService.swift          # Stockage sécurisé des tokens
├── Services/
│   ├── GmailService.swift             # Wrapper Gmail API
│   ├── DriveService.swift             # Wrapper Google Drive API
│   └── SyncEngine.swift               # Sync incrémentale + pagination
├── AI/
│   ├── LLMProvider.swift              # Protocole commun
│   ├── Providers/
│   │   ├── ClaudeProvider.swift
│   │   ├── OpenAIProvider.swift
│   │   ├── GeminiProvider.swift
│   │   └── MistralProvider.swift
│   ├── ToneContextResolver.swift      # Détection contextuelle du ton
│   ├── VoiceProfileAnalyzer.swift     # Analyse style utilisateur
│   ├── PromptBuilder.swift            # Construction des prompts
│   └── LLMConversation.swift          # Gestion des affinages
├── Models/
│   ├── Thread.swift / Message.swift
│   ├── Attachment.swift
│   ├── VoiceProfile.swift
│   └── UserInstruction.swift
├── UI/
│   ├── Sidebar/
│   ├── ThreadList/
│   ├── MessageView/
│   ├── Compose/
│   ├── AIAssistant/
│   └── Settings/
└── Resources/
```

---

## 3. Modules Fonctionnels

### 3.1 Client Gmail

#### Scopes OAuth requis

- `gmail.readonly` — lecture de la boîte de réception et des threads
- `gmail.send` — envoi et envoi différé
- `gmail.settings.basic` — lecture des paramètres
- `gmail.settings.sharing` — gestion des signatures (sendAs)
- `drive.file` — accès aux fichiers Google Drive

#### Features Gmail

| Feature | Endpoint API | Notes |
|---|---|---|
| Lecture boîte + threads | `users.threads.list` | Pagination par pageToken |
| Lecture message | `users.messages.get` | Format FULL pour les headers MIME |
| Envoi simple | `users.messages.send` | Encodage base64url du MIME |
| Envoi différé | `users.messages.send` | Header `scheduleTime` (timestamp Unix) |
| Gestion des labels | `users.labels.*` | Labels traités nativement — jamais mappés en dossiers IMAP |
| Signature HTML | `users.settings.sendAs` | PATCH pour modifier, GET pour lire |
| Message d'absence | `users.settings.vacationSettings` | Activation/désactivation + texte |
| Recherche | `users.messages.list?q=` | Syntaxe de recherche Gmail native |

#### Stratégie de sync

La sync utilise le `historyId` de Gmail pour des mises à jour incrémentales. Au premier lancement : chargement complet des N derniers threads. Ensuite : polling sur `users.history.list` avec le dernier `historyId` connu. Les emails sont mis en cache dans SwiftData pour le mode offline.

> **Note marché** : la gestion correcte des labels Gmail est le point de friction #1 d'Apple Mail selon les forums 2024-2025. GmailMac utilise l'API native Gmail — les labels ne sont jamais mappés en dossiers IMAP.

### 3.2 Intégration Google Drive

- Télécharger une PJ et l'envoyer vers Drive : Drive API `files.create` (multipart upload)
- Sélectionner une PJ depuis Drive : UI picker natif avec liste des fichiers récents (`files.list`)
- Le même token OAuth est réutilisé — pas de double connexion
- Scope `drive.file` : accès limité aux fichiers créés par l'app (principe de moindre privilège)

### 3.3 Composeur de mail

- Rédaction avec mise en forme basique (gras, italique, lien, liste)
- Rendu de la signature HTML via WKWebView éditable (`contenteditable`)
- Sélecteur de date/heure pour l'envoi différé avec confirmation visuelle
- Glisser-déposer de fichiers locaux comme pièces jointes
- Bouton Drive pour sélectionner ou sauvegarder des PJ
- Auto-complétion des destinataires depuis les contacts Gmail

---

## 4. Assistant IA

### 4.1 Providers LLM

L'assistant est conçu autour d'un protocole Swift unique — `LLMProvider` — implémenté par quatre providers. L'utilisateur configure ses propres clés API dans les Settings, stockées dans le Keychain macOS. GmailMac ne facture aucun abonnement pour l'IA.

| Provider | Endpoint | Modèle conseillé | Note |
|---|---|---|---|
| Claude | `api.anthropic.com/v1/messages` | claude-sonnet-4-6 | Excellent contexte long |
| ChatGPT | `api.openai.com/v1/chat/completions` | gpt-4o | Streaming natif |
| Gemini | `generativelanguage.googleapis.com` | gemini-1.5-pro | Réutilise l'OAuth Google |
| Mistral | `api.mistral.ai/v1/chat/completions` | mistral-large-latest | Compatible format OpenAI |

### 4.2 Protocole Swift commun

```swift
protocol LLMProvider {
    var name: String { get }

    func generateReply(
        thread: EmailThread,
        instruction: UserInstruction
    ) async throws -> String

    func requestOpinion(
        thread: EmailThread,
        question: String?
    ) async throws -> String

    func refine(
        conversation: LLMConversation,
        with instruction: String
    ) async throws -> String
}
```

### 4.3 Interface utilisateur IA

Le panneau IA s'ouvre en split view à droite du composeur. Conçu pour un flux sans copier-coller :

- **Champ libre** : l'utilisateur décrit ce qu'il veut répondre en langage naturel
- **Chips Objectif** : Conclure / Négocier / Informer / Refuser poliment / Relancer / Clarifier / Remercier
- **Chips Ton** : Formel / Chaleureux / Direct / Ferme / Diplomate / Conciliant
- **Sélecteur de longueur** : Concis / Équilibré / Détaillé
- **Bouton "Demander son avis"** : le LLM analyse l'échange et donne une lecture stratégique
- La réponse générée est directement éditable dans le panneau
- **Champ d'affinage** : instruction supplémentaire après génération (ex : "raccourcis la 2e phrase")
- **⌘+Return** : insère la réponse directement dans le composeur, sans presse-papiers

### 4.4 Feature "Demander l'avis du LLM"

L'utilisateur peut solliciter le LLM non pas pour générer une réponse, mais pour obtenir une analyse de l'échange en cours :

```
"Analyse cet échange email de façon objective. Identifie :
 - Le ton et l'intention de l'interlocuteur
 - Les points de tension ou ambiguïtés
 - Les enjeux sous-jacents
 - Ce que l'interlocuteur attend réellement
 - Des recommandations stratégiques pour la suite"
```

L'avis est affiché dans une zone dédiée, distincte de la zone de réponse générée.

---

## 5. Système de Ton de Voix

### 5.1 Analyse du style utilisateur

Au premier lancement, l'app analyse les 30 derniers emails envoyés pour construire un `VoiceProfile`. Mis à jour automatiquement toutes les semaines.

```swift
struct VoiceProfile: Codable {
    let formalityLevel: String
    let sentenceStructure: String
    let greetingPatterns: [String]
    let closingPatterns: [String]
    let vocabulary: String
    let paragraphStyle: String
    let specificExpressions: [String]
    let thingsToAvoid: [String]
    var userDescription: String?   // saisie manuelle optionnelle
    var lastUpdated: Date
}
```

> **Insight marché** : c'est le différenciateur le plus cité dans les critiques des clients IA actuels. Superhuman reconnaît avoir besoin de "semaines pour apprendre le style". Spark AI "perd le ton si on l'utilise trop". Le few-shot sur vrais emails résout ce problème structurellement.

### 5.2 Logique de résolution contextuelle

| Priorité | Cas | Source du ton | Affiché comme |
|---|---|---|---|
| 1 | L'utilisateur a déjà écrit dans ce thread | Ses réponses dans le thread en cours | "Ton de cet échange" |
| 2 | Expéditeur connu — échanges antérieurs | Emails envoyés à cet expéditeur par le passé | "Ton avec [Prénom]" |
| 3 | Même domaine d'expéditeur, personne différente | Emails envoyés à ce domaine | "Ton avec [domaine.fr]" |
| 4 | Même type de sujet (détecté par le LLM) | Emails similaires (même contexte) | "Ton de tes échanges similaires" |
| 5 | Inconnu, sans analogie | VoiceProfile global de l'utilisateur | "Ton général" |

### 5.3 Few-shot prompting

La source de ton est injectée dans le prompt sous forme d'**exemples réels** (vrais emails de l'utilisateur dans ce contexte), pas d'une description abstraite. Cette approche few-shot produit des résultats significativement plus fidèles au style réel.

### 5.4 Contrôle utilisateur

Une ligne dans le panneau IA indique la source de ton utilisée avec un bouton `[Changer]` pour basculer manuellement. Les listes d'objectifs et de tons sont éditables dans les Settings.

---

## 6. UX Flow — Réponse Assistée par IA

1. L'utilisateur reçoit un email et ouvre le thread
2. Il clique sur **✶ IA** dans la barre d'outils du composeur
3. Le panneau IA s'ouvre en split view à droite
4. Le `ToneContextResolver` identifie la source de ton (étape silencieuse)
5. L'utilisateur saisit son intention en langage naturel
6. Il sélectionne optionnellement des chips Objectif et Ton
7. Il appuie sur **[Générer]** — streaming de la réponse en temps réel
8. La réponse apparaît dans une zone éditable du panneau
9. L'utilisateur édite directement OU saisit une instruction d'affinage
10. **⌘+Return** — la réponse est injectée dans le composeur sans presse-papiers
11. L'utilisateur relit, ajuste si besoin, et envoie

**Variante "Demander l'avis"** : à l'étape 5, clic sur `[Analyser cet échange]`. Le LLM retourne une analyse stratégique dans une zone distincte. L'utilisateur peut ensuite générer une réponse en continuant le flux normal.

---

## 7. Confidentialité & Sécurité

### 7.1 Données locales

- Tokens OAuth → macOS Keychain (jamais en clair)
- Clés API LLM → Keychain, jamais dans `UserDefaults`
- Cache emails → SwiftData chiffré avec Data Protection
- VoiceProfile → stocké localement, jamais envoyé à des tiers

### 7.2 Données envoyées aux LLMs

- Avertissement clair au premier usage de la feature IA
- Option pour désactiver l'envoi de certains contenus (Cci, pièces jointes)
- Mode anonymisation (masquage des noms et adresses avant envoi)
- Jamais d'envoi sans action explicite de l'utilisateur
- Documentation claire dans le README sur ce qui part où

> **Insight marché** : la résistance à l'IA forcée est très forte (HN, Reddit 2024-2025). Les utilisateurs fuient Gmail à cause de Gemini "poussé dans la gorge". GmailMac adopte le modèle inverse : IA 100% opt-in, clés API de l'utilisateur. Argument fort pour l'open source.

### 7.3 Permissions macOS requises

- `NSContactsUsageDescription` — auto-complétion des destinataires
- `NSUserNotificationUsageDescription` — notifications
- `com.apple.security.network.client` — accès APIs Google et LLM

---

## 8. Analyse des Frictions du Marché

*Recherche effectuée en avril 2026 — Reddit (r/MacOS, r/productivity, r/apple), Hacker News, App Store reviews, X/Twitter — période : 12 derniers mois.*

### 8.1 Points de friction par application

#### Apple Mail — fuite silencieuse des utilisateurs Gmail

- Labels Gmail mappés en dossiers IMAP → emails dupliqués, threads cassés, archives qui disparaissent
- Recherche "inutilisable depuis Sonoma" : indexation incomplète, PJ non indexées
- Aucune fonctionnalité IA, pas d'undo send natif
- Sync erratique sous iOS 18 / macOS Sequoia
- **~40% des utilisateurs Gmail ont switché** selon les polls Reddit 2024-2025

#### Airmail — mort clinique

- Crashes systématiques sur macOS Sequoia, développement abandonné
- Snooze défaillant : les emails re-apparaissent après avoir été reportés
- Qualifiée de "zombie app" dans les threads 2025
- **Exode quasi-total** — réservoir de réfugiés potentiels pour GmailMac

#### Spark — drain batterie et IA retournée contre l'utilisateur

- 20–30% de CPU continu sur M3/M4 ; drain batterie massif, cité dans des dizaines de threads
- IA smart inbox avec faux positifs : emails urgents archivés automatiquement par erreur
- Subscription creep : fonctions de base passées derrière paywall à $60/an
- Labels Gmail qui cassent les threads en réponse
- **Raison de switch #1 : la batterie**

#### Mimestream — trahison de la communauté fidèle

- Beta gratuite → $120/an du jour au lendemain → **30% de churn** dans les polls Reddit
- Moteur de recherche qui rame sur les boîtes > 10 000 emails
- Pas de support multi-provider (Gmail exclusivement), pas d'app iOS avec parité
- Concurrent direct le plus proche de GmailMac

#### Superhuman — la meilleure UX, le pire rapport qualité/prix

- $360/an vécus comme "Netflix for email" — ~50% de churn sur les trials
- IA de tri (split inbox) qui archive les mauvais emails
- Besoin de "semaines pour apprendre le style" selon leur propre documentation
- Référence absolue en UX et vitesse clavier — mais inaccessible financièrement

### 8.2 Frictions spécifiques à l'IA email

**Ton générique — la plainte universelle**
"Corporate speak", "robotique", "on voit que c'est du ChatGPT". Aucun outil ne résout structurellement ce problème aujourd'hui.

**Contexte insuffisant**
Les LLMs ignorent la relation entre correspondants et l'historique des échanges. Personne ne résout ça.

**Friction d'utilisation**
Trop de clics, copier-coller obligatoire. Les utilisateurs abandonnent une feature utile parce qu'elle ralentit plus qu'elle n'aide.

**IA imposée, non consentie**
Intégration forcée de Gemini dans Gmail décrite comme "poussée dans la gorge". Réaction très négative sur HN et Reddit 2024-2025.

**Confidentialité des emails professionnels**
Réticence forte à envoyer des emails sensibles (contrats, négociations, RH) vers des APIs cloud tierces.

### 8.3 Moteurs de switch (~50 threads Reddit 2024-2025)

| Moteur | % des switchers |
|---|---|
| Sync / fiabilité / bugs | 65% |
| IA décevante ou trop chère | 25% |
| Prix | 10% |

### 8.4 Opportunités directes pour GmailMac

| Friction identifiée | Réponse GmailMac |
|---|---|
| Labels Gmail cassés (Apple Mail, Spark) | API Gmail native — labels traités nativement |
| Drain batterie (Spark, Electron) | Swift natif, zéro Electron, polling maîtrisé |
| Prix prohibitif (Mimestream $120, Superhuman $360) | Open source, gratuit |
| Ton IA générique (tous) | ToneContextResolver + few-shot sur vrais emails |
| Copier-coller obligatoire | Injection directe ⌘+Return |
| IA forcée sans consentement (Gmail/Gemini) | IA 100% opt-in, clés API de l'utilisateur |
| Pas de compréhension de la relation expéditeur | Analyse des échanges passés — feature unique |
| Risques confidentialité | Clés API perso + mode anonymisation + avertissement explicite |

**Positionnement synthétique** : la gratuité open source de Mimestream + l'IA de Superhuman, sans le prix de l'un ni le ton générique de l'autre.

---

## 9. Roadmap — Sprints

### Sprint 1 — Fondations (Semaines 1–3)
**Objectif : app qui ouvre la boîte de réception et affiche les emails.**
- Setup projet Xcode + SwiftUI
- OAuth2 Google (callback URL scheme, Keychain)
- `GmailService` : list threads, get message
- UI : Sidebar labels + ThreadList + MessageView (WKWebView)
- SwiftData : cache local des messages

### Sprint 2 — Composition (Semaines 4–5)
**Objectif : pouvoir répondre et envoyer des emails.**
- Composeur : réponse, transfert, nouveau mail
- Pièces jointes locales (drag & drop)
- Envoi différé (date picker + `scheduleTime`)
- Gestion des brouillons

### Sprint 3 — Settings Gmail (Semaines 6–7)
**Objectif : accès aux paramètres Gmail depuis l'app.**
- Éditeur de signature HTML (WKWebView `contenteditable`)
- Configuration message d'absence (`vacationSettings`)
- Gestion des labels personnalisés

### Sprint 4 — Google Drive (Semaines 8–9)
**Objectif : intégration bi-directionnelle avec Drive.**
- `DriveService` : upload, list fichiers récents
- Picker Drive natif dans le composeur
- Sauvegarde PJ reçue vers Drive

### Sprint 5 — Assistant IA (Semaines 10–13)
**Objectif : assistant IA complet, instruction-first, injection directe.**
- Protocole `LLMProvider` + 4 implémentations
- Settings clés API (Keychain)
- `VoiceProfileAnalyzer` + analyse des emails envoyés
- `ToneContextResolver` (5 niveaux de priorité)
- `PromptBuilder` avec few-shot et instruction utilisateur
- `AIAssistantPanel` : instruction, chips, génération, affinage
- `LLMConversation` : historique des affinages successifs
- Injection directe dans le composeur (⌘+Return)
- Feature "Analyser cet échange"

### Sprint 6 — Polish & Open Source (Semaines 14–16)
**Objectif : app stable, documentée, prête pour GitHub.**
- Tests unitaires : `GmailService`, `PromptBuilder`, `ToneContextResolver`
- Onboarding (premier lancement, configuration OAuth et IA)
- Performances : lazy loading, annulation des requêtes en vol
- README complet + documentation d'architecture
- Publication GitHub sous licence MIT

---

## 10. Points de Vigilance Techniques

| Sujet | Recommandation |
|---|---|
| OAuth2 callback | Utiliser `ASWebAuthenticationSession` sur macOS 12+ |
| Token refresh | Intercepteur HTTP qui rafraîchit automatiquement sur 401 |
| Rendu HTML emails | WKWebView en sandbox stricte — bloquer les ressources externes par défaut |
| Pagination Gmail | Gérer les `pageToken` dès le début pour éviter des refactos coûteuses |
| Rate limiting API | Backoff exponentiel sur les erreurs 429 |
| Encodage MIME | Encodage base64url (pas base64 standard) pour l'envoi via Gmail API |
| Fenêtre de contexte LLM | Tronquer les threads longs : garder début + N derniers messages |
| VoiceProfile stale | Invalider si l'utilisateur n'a pas envoyé d'email depuis > 30 jours |
| Streaming LLM | SSE (Server-Sent Events) pour afficher la réponse IA en temps réel |
| Recherche sur grosses boîtes | SwiftData local + fallback API pour les boîtes > 10k emails |
| Labels Gmail | Ne jamais mapper en dossiers IMAP — API Gmail native uniquement |

---

*GmailMac — Spécification Technique v1.1 — Document évolutif, à mettre à jour à chaque sprint.*
*Dernière mise à jour : Avril 2026*
