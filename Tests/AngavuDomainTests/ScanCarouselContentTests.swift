import XCTest
@testable import AngavuDomain

// E-4 — Contenuto del carosello di scansione (dominio puro). Oracolo: struttura,
// unicità degli id, ordine (manifesto prima), e l'invariante d'onestà (le curiosità
// sono approssimate, il manifesto no). La resa (layout/paging) è View-level.

final class ScanCarouselContentTests: XCTestCase {

    private let content = ScanCarouselContent.angavu

    func test_hasAllSlides_uniqueIds() {
        let ids = content.slideIDs
        XCTAssertEqual(ids.count, ScanSlideID.allCases.count, "una slide per ogni id dichiarato")
        XCTAssertEqual(Set(ids).count, ids.count, "id unici, nessun duplicato")
    }

    func test_fourManifestoThenCuriosities() {
        XCTAssertEqual(content.manifestoSlides.count, 4)
        XCTAssertEqual(content.curiositySlides.count, content.slides.count - 4)
        // Le prime quattro sono il manifesto, in ordine.
        XCTAssertEqual(Array(content.slides.prefix(4)).map(\.kind), Array(repeating: .manifesto, count: 4))
        XCTAssertTrue(content.slides.dropFirst(4).allSatisfy { $0.kind == .curiosity })
    }

    // Onestà: ogni curiosità è marcata approssimata; ogni manifesto no.
    func test_honestyInvariant_holds() {
        XCTAssertTrue(content.honestyInvariantHolds)
        XCTAssertTrue(content.curiositySlides.allSatisfy(\.isApproximate))
        XCTAssertTrue(content.manifestoSlides.allSatisfy { !$0.isApproximate })
    }

    // Nessuna slide vuota: titolo, corpo e simbolo sempre presenti.
    func test_noEmptyContent() {
        for slide in content.slides {
            XCTAssertFalse(slide.title.isEmpty, "titolo non vuoto: \(slide.id)")
            XCTAssertFalse(slide.body.isEmpty, "corpo non vuoto: \(slide.id)")
            XCTAssertFalse(slide.symbol.isEmpty, "simbolo non vuoto: \(slide.id)")
        }
    }

    // Le quattro promesse del manifesto sono presenti per id (coerenza col manifesto).
    func test_manifestoSlidesCoverCorePromises() {
        let ids = Set(content.manifestoSlides.map(\.id))
        XCTAssertEqual(ids, [.onDevice, .noAds, .realNumbers, .safetyNet])
    }
}
