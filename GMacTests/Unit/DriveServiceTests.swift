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
        case .failure(let e): XCTFail("\(e)")
        }
    }

    func test_listFiles_propagatesOffline() async {
        mockClient.stubError(.offline)
        let result = await service.listFiles()
        XCTAssertEqual(result, .failure(.offline))
    }

    func test_uploadFile_usesPOST_toCorrectURL() async {
        let uploaded = DriveFile(id: "newfile", name: "test.txt", mimeType: "text/plain", size: "10", modifiedTime: nil)
        mockClient.stub(uploaded)
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

    func test_driveFile_sizeBytes() {
        XCTAssertEqual(DriveFile(id: "1", name: "f", mimeType: "text/plain", size: "2048", modifiedTime: nil).sizeBytes, 2048)
        XCTAssertEqual(DriveFile(id: "1", name: "f", mimeType: "text/plain", size: nil, modifiedTime: nil).sizeBytes, 0)
    }
}
