import XCTest
@testable import GMac

@MainActor
final class SessionStoreTests: XCTestCase {
    var mockService: MockGmailService!
    var store: SessionStore!

    override func setUp() async throws {
        mockService = MockGmailService()
        store = SessionStore(gmailService: mockService)
    }

    func test_initialState() {
        XCTAssertTrue(store.threads.isEmpty)
        XCTAssertTrue(store.labels.isEmpty)
        XCTAssertFalse(store.isLoading)
        XCTAssertTrue(store.pendingOperations.isEmpty)
        XCTAssertNil(store.lastSyncError)
    }

    func test_loadLabels_success() async {
        mockService.stubLabels(.success([
            GmailLabel(id: "INBOX", name: "INBOX", type: .system, messagesUnread: 2)
        ]))
        await store.loadLabels()
        XCTAssertEqual(store.labels.count, 1)
        XCTAssertNil(store.lastSyncError)
    }

    func test_loadLabels_failure_setsLastSyncError() async {
        mockService.stubLabels(.failure(.offline))
        await store.loadLabels()
        XCTAssertEqual(store.lastSyncError, .offline)
        XCTAssertTrue(store.labels.isEmpty)
    }

    // TEST LE PLUS IMPORTANT — pendingOperations libéré après succès
    func test_archiveThread_pendingOperations_clearedOnSuccess() async {
        mockService.stubArchive(.success(()))
        await store.archiveThread(id: "t1")
        XCTAssertFalse(store.pendingOperations.contains("t1"),
                       "pendingOperations doit être libéré après succès")
    }

    // TEST LE PLUS IMPORTANT — pendingOperations libéré même en cas d'erreur
    func test_archiveThread_pendingOperations_clearedOnError() async {
        mockService.stubArchive(.failure(.offline))
        await store.archiveThread(id: "t1")
        XCTAssertFalse(store.pendingOperations.contains("t1"),
                       "pendingOperations doit être libéré même en cas d'erreur")
    }

    func test_archiveThread_success_removesThreadFromList() async {
        let thread = EmailThread(id: "t1", snippet: "Hello", historyId: "100", messages: [])
        store.threads = [thread]
        store.selectedThreadId = "t1"
        mockService.stubArchive(.success(()))
        await store.archiveThread(id: "t1")
        XCTAssertTrue(store.threads.isEmpty)
        XCTAssertNil(store.selectedThreadId)
    }

    func test_archiveThread_failure_doesNotRemoveThread() async {
        let thread = EmailThread(id: "t1", snippet: "Hello", historyId: "100", messages: [])
        store.threads = [thread]
        mockService.stubArchive(.failure(.offline))
        await store.archiveThread(id: "t1")
        XCTAssertEqual(store.threads.count, 1, "Le thread ne doit pas être supprimé si l'API échoue")
    }

    func test_reconcile_onHistoryId400_resetsHistoryIdAndReloads() async {
        store.currentHistoryId = "stale_id"
        mockService.stubHistory(.failure(.apiError(statusCode: 400, message: "Invalid historyId")))
        mockService.stubThreadList(.success([]))
        await store.reconcile()
        XCTAssertEqual(store.currentHistoryId, "",
                       "currentHistoryId doit être réinitialisé après 400")
    }

    func test_loadLabels_isLoading_false_after_completion() async {
        mockService.stubLabels(.success([]))
        await store.loadLabels()
        XCTAssertFalse(store.isLoading)
    }
}
