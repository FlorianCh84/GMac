import Foundation
import SwiftData

@Model
final class VoiceProfile {
    var formalityLevel: String = ""
    var sentenceStructure: String = ""
    var greetingPatterns: [String] = []
    var closingPatterns: [String] = []
    var vocabulary: String = ""
    var paragraphStyle: String = ""
    var specificExpressions: [String] = []
    var thingsToAvoid: [String] = []
    var userDescription: String = ""
    var rawEmailSamples: [String] = []
    var lastUpdated: Date = Date()

    init() {}
}
