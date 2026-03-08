import Observation
import Foundation

@Observable
final class ObjectPrototype: Identifiable {
    var id: UUID
    var canonicalName: String
    var displayName: String
    var synonyms: [String]
    var closedSetEnabled: Bool
    var openVocabularyEnabled: Bool
    var signalCapable: Bool
    var supportSurfaces: [String]
    var occlusionPriors: [String]

    var observations: [ObjectObservation] = []

    init(canonicalName: String, displayName: String, synonyms: [String] = [],
         closedSetEnabled: Bool = true, openVocabularyEnabled: Bool = false,
         signalCapable: Bool = false, supportSurfaces: [String] = [],
         occlusionPriors: [String] = []) {
        self.id = UUID()
        self.canonicalName = canonicalName
        self.displayName = displayName
        self.synonyms = synonyms
        self.closedSetEnabled = closedSetEnabled
        self.openVocabularyEnabled = openVocabularyEnabled
        self.signalCapable = signalCapable
        self.supportSurfaces = supportSurfaces
        self.occlusionPriors = occlusionPriors
    }
}
