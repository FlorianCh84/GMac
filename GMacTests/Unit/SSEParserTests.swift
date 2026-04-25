import XCTest
@testable import GMac

final class SSEParserTests: XCTestCase {

    func test_parseClaudeDelta_validLine() {
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#
        XCTAssertEqual(SSEParser.parseClaudeDelta(line), "Hello")
    }

    func test_parseClaudeDelta_wrongType_returnsNil() {
        let line = #"data: {"type":"message_stop","delta":{"type":"text_delta","text":"x"}}"#
        XCTAssertNil(SSEParser.parseClaudeDelta(line))
    }

    func test_parseClaudeDelta_noDataPrefix_returnsNil() {
        XCTAssertNil(SSEParser.parseClaudeDelta("event: ping"))
        XCTAssertNil(SSEParser.parseClaudeDelta(""))
    }

    func test_parseOpenAIDelta_validLine() {
        let line = #"data: {"choices":[{"delta":{"content":"World"},"finish_reason":null}]}"#
        XCTAssertEqual(SSEParser.parseOpenAIDelta(line), "World")
    }

    func test_parseOpenAIDelta_doneMarker_returnsNil() {
        XCTAssertNil(SSEParser.parseOpenAIDelta("data: [DONE]"))
    }

    func test_parseOpenAIDelta_nullContent_returnsNil() {
        let line = #"data: {"choices":[{"delta":{"content":null},"finish_reason":"stop"}]}"#
        XCTAssertNil(SSEParser.parseOpenAIDelta(line))
    }
}
