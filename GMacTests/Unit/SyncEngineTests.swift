import XCTest
@testable import GMac

@MainActor
final class SyncEngineTests: XCTestCase {

    private func makeEngine(intervalSeconds: TimeInterval = 3600) -> (SyncEngine, MockGmailService) {
        let service = MockGmailService()
        let store = SessionStore(gmailService: service)
        return (SyncEngine(store: store, intervalSeconds: intervalSeconds), service)
    }

    func test_start_setsIsRunning() {
        let (engine, _) = makeEngine()
        engine.start()
        XCTAssertTrue(engine.isRunning)
        engine.stop()
    }

    func test_stop_clearsIsRunning() {
        let (engine, _) = makeEngine()
        engine.start()
        engine.stop()
        XCTAssertFalse(engine.isRunning)
    }

    func test_start_idempotent() {
        let (engine, _) = makeEngine()
        engine.start()
        engine.start()  // deuxième appel — ne doit pas créer une deuxième Task
        XCTAssertTrue(engine.isRunning)
        engine.stop()
    }
}
