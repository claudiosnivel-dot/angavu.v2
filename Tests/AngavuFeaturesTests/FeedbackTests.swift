import XCTest
@testable import AngavuFeatures

// Rifinitura HIG R-06 — l'ORACOLO puro del vocabolario di feedback aptico.
// La mappa evento→livello è totale, non vacua e deterministica (un evento = un
// livello). La traduzione a `SensoryFeedback` è SwiftUI, compilata-non-resa.

final class FeedbackTests: XCTestCase {

    func test_everyEventMapsToALevel_totalAndNonEmpty() {
        XCTAssertFalse(FeedbackEvent.allCases.isEmpty)
        // Totale per costruzione: `.level` non è opzionale; qui verifichiamo che
        // ogni caso sia raggiungibile senza crash e che la mappa sia esaustiva.
        for event in FeedbackEvent.allCases {
            _ = event.level
        }
    }

    func test_vocabularyByRarity_oneEventOneLevel() {
        XCTAssertEqual(FeedbackEvent.actionAdvance.level, .impactLight)
        XCTAssertEqual(FeedbackEvent.destructivePreview.level, .warning)
        XCTAssertEqual(FeedbackEvent.success.level, .success)
        XCTAssertEqual(FeedbackEvent.failure.level, .error)
    }

    func test_distinctSignatureEvents_haveDistinctLevels() {
        let levels = FeedbackEvent.allCases.map(\.level)
        XCTAssertEqual(Set(levels).count, FeedbackEvent.allCases.count,
                       "Ogni evento-firma ha un livello distinto: nessuna collisione.")
    }

    func test_hapticsDefault_isEnabled() {
        XCTAssertTrue(HapticsPreference.defaultEnabled)
    }
}
