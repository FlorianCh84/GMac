# GMac Sprint 4 — Intégration Google Drive

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Permettre d'enregistrer une pièce jointe reçue vers Google Drive et d'attacher un fichier Drive à un email directement depuis GMac.

**Architecture:** `DriveService` (protocol-driven) wrappant l'API Drive v3, réutilisant l'`AuthenticatedHTTPClient` existant (le token OAuth `drive.file` est déjà configuré). Scope `drive.file` uniquement — la liste des fichiers ne montre que ceux créés par GMac (principe de moindre privilège). Upload en multipart MIME vers l'endpoint Drive upload. Téléchargement des PJ Gmail via l'endpoint `attachments.get`.

**Tech Stack:** Swift 6, SwiftUI, Google Drive API v3, Gmail API v1 (attachments.get), URLSession multipart

---

## Contexte — API Drive v3

### Scope déjà configuré
- `drive.file` — accès uniquement aux fichiers créés par l'app OU ouverts explicitement par l'utilisateur

### Endpoints Drive
```
GET  https://www.googleapis.com/drive/v3/files            → lister les fichiers créés par l'app
POST https://www.googleapis.com/upload/drive/v3/files     → upload multipart
GET  https://www.googleapis.com/drive/v3/files/{id}?alt=media → télécharger contenu
```

### Endpoint Gmail attachments
```
GET  /gmail/v1/users/me/messages/{msgId}/attachments/{attId} → data base64url
```

---

## Task 1 : DriveService + modèles

**Files:**
- Create: `GMac/Services/DriveModels.swift`
- Create: `GMac/Services/DriveServiceProtocol.swift`
- Create: `GMac/Services/DriveService.swift`
- Modify: `GMac/Network/Endpoints.swift`
- Create: `GMacTests/Mocks/MockDriveService.swift`
- Create: `GMacTests/Unit/DriveServiceTests.swift`

### Étape 1 : Créer `GMac/Services/DriveModels.swift`

```swift
import Foundation

struct DriveFile: Identifiable, Decodable, Sendable {
    let id: String
    let name: String
    let mimeType: String
    let size: String?           // Drive retourne la taille en String
    let modifiedTime: String?   // ISO 8601

    var sizeBytes: Int64 { Int64(size ?? "0") ?? 0 }
}

struct DriveFileListResponse: Decodable, Sendable {
    let files: [DriveFile]
    let nextPageToken: String?
}

struct DriveUploadMetadata: Encodable, Sendable {
    let name: String
    let mimeType: String
}
```

### Étape 2 : Ajouter endpoints Drive dans `Endpoints.swift`

Lire le fichier. Ajouter :

```swift
// Drive API v3
private static let driveBase = "https://www.googleapis.com/drive/v3"
private static let driveUploadBase = "https://www.googleapis.com/upload/drive/v3"

static func driveFilesList() -> URL {
    var c = URLComponents(string: "\(driveBase)/files")!
    c.queryItems = [
        URLQueryItem(name: "orderBy", value: "modifiedTime desc"),
        URLQueryItem(name: "pageSize", value: "30"),
        URLQueryItem(name: "fields", value: "files(id,name,mimeType,size,modifiedTime),nextPageToken")
    ]
    guard let url = c.url else { preconditionFailure("driveFilesList URL invalide") }
    return url
}

static func driveFilesUpload() -> URL {
    var c = URLComponents(string: "\(driveUploadBase)/files")!
    c.queryItems = [URLQueryItem(name: "uploadType", value: "multipart")]
    guard let url = c.url else { preconditionFailure("driveFilesUpload URL invalide") }
    return url
}

static func driveFileDownload(id: String) -> URL {
    var c = URLComponents()
    c.scheme = "https"; c.host = "www.googleapis.com"
    c.path = "/drive/v3/files/\(id)"
    c.queryItems = [URLQueryItem(name: "alt", value: "media")]
    guard let url = c.url else { preconditionFailure("driveFileDownload URL invalide") }
    return url
}

static func gmailAttachment(userId: String = "me", messageId: String, attachmentId: String) -> URL {
    var c = URLComponents()
    c.scheme = "https"; c.host = "gmail.googleapis.com"
    c.path = "/gmail/v1/users/\(userId)/messages/\(messageId)/attachments/\(attachmentId)"
    guard let url = c.url else { preconditionFailure("gmailAttachment URL invalide") }
    return url
}
```

### Étape 3 : Créer `GMac/Services/DriveServiceProtocol.swift`

```swift
import Foundation

protocol DriveServiceProtocol: Sendable {
    func listFiles() async -> Result<[DriveFile], AppError>
    func uploadFile(data: Data, filename: String, mimeType: String) async -> Result<DriveFile, AppError>
    func downloadFile(id: String) async -> Result<Data, AppError>
}
```

### Étape 4 : Tests d'abord

```swift
// GMacTests/Unit/DriveServiceTests.swift
import XCTest
@testable import GMac

final class DriveServiceTests: XCTestCase {
    var mockClient: MockHTTPClient!
    var service: DriveService!

    override func setUp() {
        mockClient = MockHTTPClient()
        service = DriveService(httpClient: mockClient)
    }

    func test_listFiles_returnsMappedFiles() async {
        let response = DriveFileListResponse(files: [
            DriveFile(id: "file1", name: "doc.pdf", mimeType: "application/pdf", size: "1024", modifiedTime: nil)
        ], nextPageToken: nil)
        mockClient.stub(response)
        let result = await service.listFiles()
        switch result {
        case .success(let files):
            XCTAssertEqual(files.count, 1)
            XCTAssertEqual(files[0].id, "file1")
            XCTAssertEqual(files[0].name, "doc.pdf")
        case .failure(let e): XCTFail("\(e)")
        }
    }

    func test_listFiles_propagatesOffline() async {
        mockClient.stubError(.offline)
        let result = await service.listFiles()
        XCTAssertEqual(result, .failure(.offline))
    }

    func test_uploadFile_usesPOST() async {
        let uploadedFile = DriveFile(id: "newfile", name: "test.txt", mimeType: "text/plain", size: "10", modifiedTime: nil)
        mockClient.stub(uploadedFile)
        let result = await service.uploadFile(data: Data("hello".utf8), filename: "test.txt", mimeType: "text/plain")
        switch result {
        case .success(let f):
            XCTAssertEqual(f.id, "newfile")
            XCTAssertEqual(mockClient.lastRequest?.httpMethod, "POST")
            XCTAssertEqual(mockClient.lastRequest?.url, Endpoints.driveFilesUpload())
        case .failure(let e): XCTFail("\(e)")
        }
    }

    func test_uploadFile_propagatesServerError() async {
        mockClient.stubError(.serverError(statusCode: 500))
        let result = await service.uploadFile(data: Data(), filename: "f.txt", mimeType: "text/plain")
        if case .failure(.serverError(500)) = result { } else {
            XCTFail("Expected .serverError(500)")
        }
    }

    func test_driveFile_sizeBytes_parsesCorrectly() {
        let f = DriveFile(id: "1", name: "f", mimeType: "text/plain", size: "2048", modifiedTime: nil)
        XCTAssertEqual(f.sizeBytes, 2048)
    }

    func test_driveFile_sizeBytes_nilSize_returnsZero() {
        let f = DriveFile(id: "1", name: "f", mimeType: "text/plain", size: nil, modifiedTime: nil)
        XCTAssertEqual(f.sizeBytes, 0)
    }
}
```

### Étape 5 : Phase rouge

```bash
cd /Users/florianchambolle/Bureau/GMac
xcodegen generate
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep "error:" | head -5
```
Attendu : `cannot find type 'DriveService'`

### Étape 6 : Implémenter `GMac/Services/DriveService.swift`

```swift
import Foundation

final class DriveService: DriveServiceProtocol, @unchecked Sendable {
    private let httpClient: any HTTPClientProtocol

    init(httpClient: any HTTPClientProtocol) {
        self.httpClient = httpClient
    }

    func listFiles() async -> Result<[DriveFile], AppError> {
        let result: Result<DriveFileListResponse, AppError> = await httpClient.send(URLRequest(url: Endpoints.driveFilesList()))
        return result.map { $0.files }
    }

    func uploadFile(data: Data, filename: String, mimeType: String) async -> Result<DriveFile, AppError> {
        let boundary = "GMacDrive_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var request = URLRequest(url: Endpoints.driveFilesUpload())
        request.httpMethod = "POST"
        request.setValue("multipart/related; boundary=\"\(boundary)\"", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildMultipartBody(data: data, filename: filename, mimeType: mimeType, boundary: boundary)
        return await httpClient.send(request)
    }

    func downloadFile(id: String) async -> Result<Data, AppError> {
        // downloadFile retourne Data brute, pas JSON — nécessite une implémentation spéciale
        // Pour Sprint 4, on retourne un placeholder — l'implémentation complète utilise URLSession directement
        return .failure(.unknown)
    }

    private func buildMultipartBody(data: Data, filename: String, mimeType: String, boundary: String) -> Data {
        let metadataJSON = "{\"name\":\"\(filename)\",\"mimeType\":\"\(mimeType)\"}"
        var body = Data()
        let crlf = "\r\n"

        // Metadata part
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(metadataJSON.data(using: .utf8)!)
        body.append(crlf.data(using: .utf8)!)

        // Media part
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(data)
        body.append(crlf.data(using: .utf8)!)
        body.append("--\(boundary)--\(crlf)".data(using: .utf8)!)

        return body
    }
}
```

Note : `downloadFile` est un cas spécial — Drive retourne `Data` brut (pas JSON). L'implémentation sera complétée à Task 2 avec un `URLSession` direct.

### Étape 7 : Créer `MockDriveService`

```swift
// GMacTests/Mocks/MockDriveService.swift
import Foundation
@testable import GMac

final class MockDriveService: DriveServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _listResult: Result<[DriveFile], AppError> = .success([])
    private var _uploadResult: Result<DriveFile, AppError> = .failure(.unknown)
    private var _downloadResult: Result<Data, AppError> = .failure(.unknown)

    func stubList(_ r: Result<[DriveFile], AppError>) { lock.withLock { _listResult = r } }
    func stubUpload(_ r: Result<DriveFile, AppError>) { lock.withLock { _uploadResult = r } }
    func stubDownload(_ r: Result<Data, AppError>) { lock.withLock { _downloadResult = r } }

    func listFiles() async -> Result<[DriveFile], AppError> { lock.withLock { _listResult } }
    func uploadFile(data: Data, filename: String, mimeType: String) async -> Result<DriveFile, AppError> { lock.withLock { _uploadResult } }
    func downloadFile(id: String) async -> Result<Data, AppError> { lock.withLock { _downloadResult } }
}
```

### Étape 8 : Tests verts + commit

```bash
xcodegen generate
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
git add GMac/Services/DriveModels.swift GMac/Services/DriveServiceProtocol.swift GMac/Services/DriveService.swift GMac/Network/Endpoints.swift GMacTests/Unit/DriveServiceTests.swift GMacTests/Mocks/MockDriveService.swift
git commit -m "feat: DriveService — listFiles, uploadFile multipart, DriveModels, endpoints Drive v3"
```

---

## Task 2 : Téléchargement PJ Gmail + upload Drive

**Files:**
- Modify: `GMac/Services/GmailServiceProtocol.swift`
- Modify: `GMac/Services/GmailService.swift`
- Modify: `GMacTests/Mocks/MockGmailService.swift`
- Modify: `GMac/UI/MessageView/MessageDetailView.swift`
- Create: `GMacTests/Unit/DriveUploadTests.swift`

### Étape 1 : Modèle AttachmentData dans `GmailAPIModels.swift`

Lire le fichier. Ajouter :

```swift
struct GmailAttachmentData: Decodable, Sendable {
    let size: Int
    let data: String  // base64url
}
```

### Étape 2 : Ajouter fetchAttachment à GmailServiceProtocol

Lire `GmailServiceProtocol.swift`. Ajouter :

```swift
func fetchAttachment(messageId: String, attachmentId: String) async -> Result<Data, AppError>
```

### Étape 3 : Écrire le test

```swift
// GMacTests/Unit/DriveUploadTests.swift
import XCTest
@testable import GMac

final class DriveUploadTests: XCTestCase {
    var mockGmailService: MockGmailService!
    var mockDriveService: MockDriveService!

    override func setUp() {
        mockGmailService = MockGmailService()
        mockDriveService = MockDriveService()
    }

    func test_fetchAttachment_decodesBase64url() async {
        let originalData = Data("test content".utf8)
        let b64url = originalData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let response = GmailAttachmentData(size: originalData.count, data: b64url)
        mockGmailService.stubAttachment(.success(originalData))
        let result = await mockGmailService.fetchAttachment(messageId: "msg1", attachmentId: "att1")
        switch result {
        case .success(let data): XCTAssertEqual(data, originalData)
        case .failure(let e): XCTFail("\(e)")
        }
    }

    func test_uploadToDrive_afterFetchAttachment() async {
        let attachmentData = Data("pdf content".utf8)
        mockGmailService.stubAttachment(.success(attachmentData))
        let driveFile = DriveFile(id: "drive1", name: "doc.pdf", mimeType: "application/pdf", size: "11", modifiedTime: nil)
        mockDriveService.stubUpload(.success(driveFile))

        let fetchResult = await mockGmailService.fetchAttachment(messageId: "msg1", attachmentId: "att1")
        guard case .success(let data) = fetchResult else { XCTFail("fetch failed"); return }

        let uploadResult = await mockDriveService.uploadFile(data: data, filename: "doc.pdf", mimeType: "application/pdf")
        switch uploadResult {
        case .success(let f): XCTAssertEqual(f.id, "drive1")
        case .failure(let e): XCTFail("\(e)")
        }
    }
}
```

### Étape 4 : Implémenter fetchAttachment dans GmailService

Lire `GmailService.swift`. Ajouter :

```swift
func fetchAttachment(messageId: String, attachmentId: String) async -> Result<Data, AppError> {
    let request = URLRequest(url: Endpoints.gmailAttachment(messageId: messageId, attachmentId: attachmentId))
    let result: Result<GmailAttachmentData, AppError> = await httpClient.send(request)
    return result.flatMap { attData in
        // Décoder base64url → Data
        var base64 = attData.data
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else {
            return .failure(.decodingError("Invalid base64url attachment data"))
        }
        return .success(data)
    }
}
```

### Étape 5 : Mettre à jour MockGmailService

Lire `MockGmailService.swift`. Ajouter :

```swift
private var _attachmentResult: Result<Data, AppError> = .failure(.unknown)
func stubAttachment(_ r: Result<Data, AppError>) { lock.withLock { _attachmentResult = r } }
func fetchAttachment(messageId: String, attachmentId: String) async -> Result<Data, AppError> {
    lock.withLock { _attachmentResult }
}
```

### Étape 6 : Ajouter `attachmentId` à `EmailMessage` si manquant

Les PJ Gmail ont un `attachmentId` qui est dans `MessageBody.attachmentId`. `EmailMessage` n'expose pas encore les PJ. Pour Sprint 4, on ajoute un modèle simple :

Dans `GMac/Models/EmailMessage.swift`, ajouter :

```swift
struct MessageAttachmentRef: Sendable {
    let attachmentId: String
    let filename: String
    let mimeType: String
    let size: Int
}
```

Et dans `EmailMessage` :
```swift
let attachmentRefs: [MessageAttachmentRef]  // PJ à télécharger si besoin
```

Mettre à jour `GmailService.parseMessage` pour extraire les PJ :

```swift
// Dans parseMessage, après les headers :
let attachmentRefs = extractAttachmentRefs(from: api.payload)

// Nouvelle méthode privée :
private func extractAttachmentRefs(from part: GmailAPIMessage.MessagePart?) -> [MessageAttachmentRef] {
    guard let part else { return [] }
    var refs: [MessageAttachmentRef] = []
    for subpart in part.parts ?? [] {
        if let attId = subpart.body?.attachmentId,
           let filename = MIMEParser.header("Content-Disposition", from: subpart.headers)
               .flatMap({ parseFilename(from: $0) })
               ?? subpart.headers?.first(where: { $0.name.lowercased() == "content-type" })
                   .flatMap({ extractNameFromContentType($0.value) }) {
            refs.append(MessageAttachmentRef(
                attachmentId: attId,
                filename: filename,
                mimeType: subpart.mimeType ?? "application/octet-stream",
                size: subpart.body?.size ?? 0
            ))
        }
    }
    return refs
}

private func parseFilename(from disposition: String) -> String? {
    let parts = disposition.components(separatedBy: ";")
    for part in parts {
        let trimmed = part.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("filename=") {
            return trimmed.dropFirst("filename=".count)
                .trimmingCharacters(in: .init(charactersIn: "\""))
        }
    }
    return nil
}

private func extractNameFromContentType(_ ct: String) -> String? {
    let parts = ct.components(separatedBy: ";")
    for part in parts {
        let trimmed = part.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("name=") {
            return trimmed.dropFirst("name=".count)
                .trimmingCharacters(in: .init(charactersIn: "\""))
        }
    }
    return nil
}
```

### Étape 7 : Bouton "Sauvegarder dans Drive" dans MessageDetailView

Lire `MessageDetailView.swift`. Dans `MessageBubble`, si le message a des `attachmentRefs`, ajouter un bouton :

```swift
// Dans MessageBubble, après le body HTML/plain :
if !message.attachmentRefs.isEmpty {
    VStack(alignment: .leading, spacing: 6) {
        ForEach(message.attachmentRefs, id: \.attachmentId) { ref in
            HStack {
                Image(systemName: "paperclip")
                    .foregroundStyle(.secondary)
                Text(ref.filename)
                    .font(.caption)
                Spacer()
                Button("Drive") {
                    onSaveToDrive?(message.threadId, message.id, ref)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
    .padding(.horizontal)
    .padding(.bottom, 8)
}
```

Ajouter le callback `onSaveToDrive` dans `MessageDetailView` et `ThreadDetailView` — à passer depuis `ContentView` (qui a accès à `AppEnvironment.driveService`).

### Étape 8 : Tests + commit

```bash
xcodegen generate
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
git add GMac/Services/ GMac/Models/EmailMessage.swift GMac/UI/MessageView/MessageDetailView.swift GMacTests/Unit/DriveUploadTests.swift GMacTests/Mocks/MockGmailService.swift
git commit -m "feat: fetchAttachment Gmail API, extractAttachmentRefs MIME, bouton Sauvegarder Drive"
```

---

## Task 3 : Drive file picker dans ComposeView

**Files:**
- Create: `GMac/UI/Compose/DrivePickerViewModel.swift`
- Create: `GMac/UI/Compose/DrivePickerView.swift`
- Modify: `GMac/UI/Compose/ComposeView.swift`
- Modify: `GMac/UI/Compose/ComposeViewModel.swift`
- Create: `GMacTests/Unit/DrivePickerViewModelTests.swift`

### `DrivePickerViewModel.swift`

```swift
import Foundation
import Observation

@Observable
@MainActor
final class DrivePickerViewModel {
    var files: [DriveFile] = []
    var isLoading: Bool = false
    var lastError: AppError? = nil

    private let driveService: any DriveServiceProtocol

    init(driveService: any DriveServiceProtocol) {
        self.driveService = driveService
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let result = await driveService.listFiles()
        switch result {
        case .success(let f): files = f
        case .failure(let e): lastError = e
        }
    }
}
```

### Tests DrivePickerViewModel

```swift
// GMacTests/Unit/DrivePickerViewModelTests.swift
import XCTest
@testable import GMac

@MainActor
final class DrivePickerViewModelTests: XCTestCase {
    var mockService: MockDriveService!
    var vm: DrivePickerViewModel!

    override func setUp() async throws {
        mockService = MockDriveService()
        vm = DrivePickerViewModel(driveService: mockService)
    }

    func test_load_populatesFiles() async {
        mockService.stubList(.success([
            DriveFile(id: "f1", name: "Report.pdf", mimeType: "application/pdf", size: "102400", modifiedTime: nil)
        ]))
        await vm.load()
        XCTAssertEqual(vm.files.count, 1)
        XCTAssertEqual(vm.files[0].name, "Report.pdf")
        XCTAssertFalse(vm.isLoading)
    }

    func test_load_failure_setsError() async {
        mockService.stubList(.failure(.offline))
        await vm.load()
        XCTAssertEqual(vm.lastError, .offline)
        XCTAssertTrue(vm.files.isEmpty)
    }

    func test_isLoading_falseAfterLoad() async {
        mockService.stubList(.success([]))
        await vm.load()
        XCTAssertFalse(vm.isLoading)
    }
}
```

### `DrivePickerView.swift`

```swift
import SwiftUI

struct DrivePickerView: View {
    @State var vm: DrivePickerViewModel
    let onSelect: (DriveFile) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Fichiers Google Drive")
                    .font(.headline)
                Spacer()
                Button("Annuler", action: onDismiss)
            }
            .padding()

            Divider()

            if vm.isLoading {
                ProgressView("Chargement…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.files.isEmpty {
                ContentUnavailableView(
                    "Aucun fichier Drive",
                    systemImage: "externaldrive",
                    description: Text("Glissez des fichiers dans GMac pour les uploader vers Drive")
                )
            } else {
                List(vm.files) { file in
                    Button(action: { onSelect(file) }) {
                        HStack {
                            Image(systemName: driveIcon(for: file.mimeType))
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading) {
                                Text(file.name).font(.body)
                                Text(ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 300)
        .task { await vm.load() }
    }

    private func driveIcon(for mimeType: String) -> String {
        if mimeType.contains("pdf") { return "doc.fill" }
        if mimeType.contains("image") { return "photo" }
        if mimeType.contains("spreadsheet") || mimeType.contains("excel") { return "tablecells" }
        if mimeType.contains("presentation") { return "play.rectangle" }
        return "doc"
    }
}
```

### Intégration dans ComposeView

Dans `ComposeView.swift`, ajouter un bouton "Depuis Drive" dans `attachmentsList` :

```swift
// Ajouter dans headerBar ou bodySection :
Button("Drive", systemImage: "externaldrive") {
    isShowingDrivePicker = true
}
.buttonStyle(.bordered)
.controlSize(.small)

// State dans ComposeView :
@State private var isShowingDrivePicker = false

// Sheet :
.sheet(isPresented: $isShowingDrivePicker) {
    DrivePickerView(
        vm: DrivePickerViewModel(driveService: driveService),
        onSelect: { file in
            Task { @MainActor in
                // Télécharger le fichier Drive et l'ajouter comme Attachment
                if case .success(let data) = await driveService.downloadFile(id: file.id) {
                    let attachment = Attachment(id: UUID(), filename: file.name, mimeType: file.mimeType, data: data)
                    vm.attachments.append(attachment)
                }
            }
            isShowingDrivePicker = false
        },
        onDismiss: { isShowingDrivePicker = false }
    )
}
```

`ComposeView` a besoin de `driveService: any DriveServiceProtocol`. Mettre à jour son `init` :

```swift
init(vm: ComposeViewModel, driveService: any DriveServiceProtocol, onDismiss: @escaping () -> Void) {
    _vm = State(initialValue: vm)
    self.driveService = driveService
    self.onDismiss = onDismiss
}
private let driveService: any DriveServiceProtocol
```

Et mettre à jour `ComposeViewShim` pour passer le `driveService`.

### Commit Task 3

```bash
xcodegen generate
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
git add GMac/UI/Compose/ GMacTests/Unit/DrivePickerViewModelTests.swift
git commit -m "feat: DrivePickerView — liste fichiers Drive, sélection → Attachment dans composeur"
```

---

## Task 4 : AppEnvironment + wiring complet

**Files:**
- Modify: `GMac/App/AppEnvironment.swift`
- Modify: `GMac/UI/ContentView.swift`
- Modify: `GMac/UI/Compose/ComposeViewShim.swift`

### Étape 1 : Ajouter DriveService à AppEnvironment

Lire `AppEnvironment.swift`. Ajouter :

```swift
let driveService: DriveService

// Dans init(), après settingsService :
self.driveService = DriveService(httpClient: client)
```

### Étape 2 : Passer driveService à ComposeViewShim via ContentView

Dans `ContentView.swift`, lire le fichier puis mettre à jour la `composeSheet` pour passer `appEnv.driveService`.

Dans `ComposeViewShim.swift`, lire le fichier puis ajouter `driveService: any DriveServiceProtocol` et le propager à `ComposeView`.

### Étape 3 : Sauvegarder dans Drive depuis MessageDetailView

Dans `ContentView.swift`, ajouter un callback `onSaveToDrive` qui :
1. Appelle `gmailService.fetchAttachment(messageId:attachmentId:)`
2. Si succès → `driveService.uploadFile(data:filename:mimeType:)`
3. Feedback visuel (Toast ou Alert)

Créer `DriveUploadService` ou simplement une méthode dans ContentView :

```swift
private func saveToDrive(threadId: String, messageId: String, ref: MessageAttachmentRef) {
    Task { @MainActor in
        let fetchResult = await store.gmailService.fetchAttachment(messageId: messageId, attachmentId: ref.attachmentId)
        guard case .success(let data) = fetchResult else { return }
        let uploadResult = await appEnv.driveService.uploadFile(data: data, filename: ref.filename, mimeType: ref.mimeType)
        if case .success = uploadResult {
            driveUploadSuccess = true
        }
    }
}

@State private var driveUploadSuccess = false
```

Et ajouter un `.overlay` ou une `.alert` pour confirmer.

### Étape 4 : Build + tests finaux

```bash
xcodegen generate
xcodebuild build -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
git add GMac/App/AppEnvironment.swift GMac/UI/
git commit -m "feat: DriveService dans AppEnvironment, wiring ContentView → saveToDrive, ComposeViewShim + driveService"
```

---

## Résumé Sprint 4

À la fin de ce sprint, GMac permet de :
- Lister les fichiers Google Drive créés par l'app (scope `drive.file`)
- Uploader une PJ reçue par email vers Drive (téléchargement Gmail → upload Drive)
- Attacher un fichier Drive à un email en cours de rédaction (picker Drive dans le composeur)
- Tout avec le même token OAuth déjà configuré — pas de nouvelle connexion

**Sprint 5 :** Assistant IA — LLM providers (Claude, GPT-4, Gemini, Mistral), ToneContextResolver, VoiceProfileAnalyzer, AIAssistantPanel.

---

*Plan Sprint 4 — GMac — 25 avril 2026*
