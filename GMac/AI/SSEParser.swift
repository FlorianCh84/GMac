import Foundation

enum SSEParser {

    static func parseClaudeDelta(_ line: String) -> String? {
        guard line.hasPrefix("data: ") else { return nil }
        let json = String(line.dropFirst(6))
        guard let data = json.data(using: .utf8) else { return nil }
        struct Root: Decodable { let type: String?; let delta: Delta? }
        struct Delta: Decodable { let type: String?; let text: String? }
        guard let root = try? JSONDecoder().decode(Root.self, from: data),
              root.type == "content_block_delta",
              root.delta?.type == "text_delta" else { return nil }
        return root.delta?.text
    }

    static func parseOpenAIDelta(_ line: String) -> String? {
        guard line.hasPrefix("data: ") else { return nil }
        let json = String(line.dropFirst(6))
        if json.trimmingCharacters(in: .whitespaces) == "[DONE]" { return nil }
        guard let data = json.data(using: .utf8) else { return nil }
        struct Root: Decodable { let choices: [Choice]? }
        struct Choice: Decodable { let delta: Delta }
        struct Delta: Decodable { let content: String? }
        guard let root = try? JSONDecoder().decode(Root.self, from: data) else { return nil }
        return root.choices?.first?.delta.content
    }
}
