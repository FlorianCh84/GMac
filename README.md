# GMac

**Client Gmail natif macOS avec assistant IA intégré**

GMac est un client mail open source pour macOS 26 (Tahoe), construit avec SwiftUI natif. Il utilise directement l'API Gmail REST (pas IMAP) et intègre un assistant IA multi-LLM qui génère des réponses dans votre ton, avec injection directe dans le composeur.

## Pourquoi GMac ?

| App | Natif macOS | Gmail API | IA intégrée | Prix | Open source |
|---|---|---|---|---|---|
| Mimestream | ✅ | ✅ | ❌ | 120$/an | ❌ |
| Superhuman | ❌ Electron | ✅ | Partiel | 360$/an | ❌ |
| **GMac** | **✅ SwiftUI** | **✅** | **✅ Multi-LLM** | **Gratuit** | **✅ MIT** |

## Fonctionnalités

- **Client Gmail complet** — threads, labels natifs, envoi différé, pièces jointes, recherche
- **Countdown 3s annulable** — le mail ne part jamais pendant le countdown
- **Assistant IA multi-LLM** — Claude, GPT-4o, Gemini, Mistral avec vos propres clés API
- **ToneContextResolver** — l'IA écrit dans votre ton (5 niveaux de contexte)
- **Google Drive** — upload/download de PJ directement depuis GMac
- **Settings Gmail** — signature HTML, message d'absence, labels
- **Privacy first** — IA opt-in, clés API dans le Keychain, données Gmail jamais persistées sur disque

## Prérequis

- macOS 26.0+
- Xcode 26+
- Compte Google Cloud avec Gmail API v1 et Drive API v3 activés

## Installation

```bash
git clone https://github.com/florianchambolle/GMac
cd GMac
xcodegen generate
open GMac.xcodeproj
```

Créer les credentials OAuth 2.0 (application macOS) dans [Google Cloud Console](https://console.cloud.google.com), puis remplir `GMac/Resources/Info.plist` :
- `GOOGLE_CLIENT_ID`  
- `GOOGLE_CLIENT_SECRET`

Optionnel : configurer vos clés LLM dans **GMac → ⚙️ → Assistant IA**.

## Architecture

Voir [`docs/2026-04-25-architecture-fiabilite-design.md`](docs/2026-04-25-architecture-fiabilite-design.md).

**Principe central :** Gmail est la source de vérité. Aucune donnée Gmail n'est persistée sur disque. Toutes les mutations bloquent l'UI jusqu'à confirmation API.

```
UI (SwiftUI / Liquid Glass)
    ↓
ViewModels (@Observable @MainActor)
    ↓
SessionStore (in-memory, pendingOperations + defer)
    ↓
Services (GmailService, DriveService, GmailSettingsService)
    ↓
AuthenticatedHTTPClient (token refresh auto, retry isRetryable)
    ↓
SwiftData (VoiceProfile uniquement — jamais données Gmail)
```

## Tests

```bash
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64'
```

180+ tests unitaires couvrant : réseau, auth, MIME, SessionStore, LLM providers, SSEParser.

## Contribution

Voir [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

MIT — voir [LICENSE](LICENSE).
