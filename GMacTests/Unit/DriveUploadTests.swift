import XCTest
@testable import GMac

final class DriveUploadTests: XCTestCase {
    var mockGmail: MockGmailService!
    var mockDrive: MockDriveService!

    override func setUp() {
        mockGmail = MockGmailService()
        mockDrive = MockDriveService()
    }

    func test_fetchAttachment_returnsData() async {
        let data = Data("file content".utf8)
        mockGmail.stubAttachment(.success(data))
        let result = await mockGmail.fetchAttachment(messageId: "msg1", attachmentId: "att1")
        switch result {
        case .success(let d): XCTAssertEqual(d, data)
        case .failure(let e): XCTFail("\(e)")
        }
    }

    func test_fetchAttachment_propagatesError() async {
        mockGmail.stubAttachment(.failure(.offline))
        let result = await mockGmail.fetchAttachment(messageId: "msg1", attachmentId: "att1")
        XCTAssertEqual(result, .failure(.offline))
    }

    func test_uploadAfterFetch_chain() async {
        let data = Data("pdf".utf8)
        mockGmail.stubAttachment(.success(data))
        let driveFile = DriveFile(id: "d1", name: "doc.pdf", mimeType: "application/pdf", size: "3", modifiedTime: nil)
        mockDrive.stubUpload(.success(driveFile))
        let fetch = await mockGmail.fetchAttachment(messageId: "m1", attachmentId: "a1")
        guard case .success(let d) = fetch else { XCTFail(); return }
        let upload = await mockDrive.uploadFile(data: d, filename: "doc.pdf", mimeType: "application/pdf")
        if case .success(let f) = upload { XCTAssertEqual(f.id, "d1") }
        else { XCTFail("upload failed") }
    }
}
