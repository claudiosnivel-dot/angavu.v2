import XCTest
@testable import AngavuDomain

// T-013 — AC-013-1 / AC-013-2. Applicazione pura del delta all'indice.

private func asset(_ id: String, kind: MediaKind = .photo, width: Int = 100) -> LibraryAsset {
    LibraryAsset(
        id: id,
        kind: kind,
        pixelSize: PixelSize(width: width, height: 100),
        creationDate: nil,
        subtypes: []
    )
}

final class IncrementalIndexDeltaTests: XCTestCase {

    // AC-013-1: 5 asset, delta che rimuove 1 e aggiunge 2 → 6 asset coerenti.
    func test_applyDelta_addsAndRemoves_withoutFullRebuild() {
        let snapshot = ["A", "B", "C", "D", "E"].map { asset($0) }
        let delta = IndexDelta(
            added: [asset("F"), asset("G")],
            removed: ["C"],
            changed: []
        )

        let result = IncrementalIndex.apply(delta, to: snapshot)

        XCTAssertEqual(result.count, 6)
        XCTAssertEqual(result.map(\.id), ["A", "B", "D", "E", "F", "G"])
        XCTAssertFalse(result.contains { $0.id == "C" })
    }

    // AC-013-2: un delta che modifica i metadati di un asset esistente → record
    // aggiornato in place, stesso id.
    func test_applyDelta_updatesChangedInPlace_sameId() {
        let snapshot = [asset("A", width: 100), asset("B", width: 100)]
        let changed = asset("A", width: 4_000) // stesso id, metadati diversi
        let delta = IndexDelta(added: [], removed: [], changed: [changed])

        let result = IncrementalIndex.apply(delta, to: snapshot)

        XCTAssertEqual(result.count, 2, "nessun duplicato: aggiornamento in place")
        let updated = result.first { $0.id == "A" }
        XCTAssertEqual(updated?.pixelSize.width, 4_000)
    }

    // Idempotenza: applicare due volte lo stesso add non crea duplicati.
    func test_applyDelta_isIdempotentById() {
        let snapshot = [asset("A")]
        let delta = IndexDelta(added: [asset("A"), asset("B")], removed: [], changed: [])

        let once = IncrementalIndex.apply(delta, to: snapshot)
        let twice = IncrementalIndex.apply(delta, to: once)

        XCTAssertEqual(once.map(\.id), ["A", "B"])
        XCTAssertEqual(twice.map(\.id), ["A", "B"])
    }
}
