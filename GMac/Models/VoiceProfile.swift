import Foundation
import SwiftData

@Model
final class VoiceProfile {
    var formalityLevel: String = ""
    var sentenceStructure: String = ""
    var averageEmailLength: String = ""
    var greetingPatterns: [String] = []
    var closingPatterns: [String] = []
    var vocabulary: String = ""
    var paragraphStyle: String = ""
    var usesLists: Bool = false
    var humorLevel: String = ""
    var writingRhythm: String = ""
    var specificExpressions: [String] = []
    var thingsToAvoid: [String] = []
    // Mémoire relationnelle par contact
    var tutoiementContacts: [String] = []
    var vouvoiementContacts: [String] = []
    var informalGreetingContacts: [String] = []
    var userDescription: String = ""
    var rawEmailSamples: [String] = []
    var lastUpdated: Date = Date()

    init() {}
}
