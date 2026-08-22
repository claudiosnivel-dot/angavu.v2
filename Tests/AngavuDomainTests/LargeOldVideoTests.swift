import XCTest
@testable import AngavuDomain

// T-060 — AC-060-1 / AC-060-2. Video grandi E vecchi ordinati per dimensione/età.
// Domain puro: l'oracolo gira senza device.

final class LargeOldVideoTests: XCTestCase {

    // Date di riferimento fisse via epoch UTC (nessun orologio, nessun force-unwrap
    // → deterministico e conforme alla regola SwiftLint force_unwrapping).
    private let year2019 = Date(timeIntervalSince1970: 1_546_300_800) // 2019-01-01
    private let year2020 = Date(timeIntervalSince1970: 1_577_836_800) // 2020-01-01
    private let year2021 = Date(timeIntervalSince1970: 1_609_459_200) // 2021-01-01
    private let year2024 = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01

    private func video(_ id: String, bytes: Int64, created: Date?) -> SizedAsset {
        let asset = LibraryAsset(
            id: id,
            kind: .video,
            pixelSize: PixelSize(width: 1920, height: 1080),
            creationDate: created,
            subtypes: []
        )
        return SizedAsset(asset: asset, size: .exact(bytes: bytes))
    }

    private func photo(_ id: String, bytes: Int64, created: Date?) -> SizedAsset {
        let asset = LibraryAsset(
            id: id,
            kind: .photo,
            pixelSize: PixelSize(width: 4032, height: 3024),
            creationDate: created,
            subtypes: []
        )
        return SizedAsset(asset: asset, size: .exact(bytes: bytes))
    }

    // AC-060-1: solo i video oltre ENTRAMBE le soglie, ordinati per dimensione
    // decrescente. Soglia: >= 100 MB e creato <= 2021-01-01.
    func test_selectsLargeAndOldVideosSortedBySizeDescending() {
        let thresholds = LargeOldThresholds(
            minBytes: 100_000_000,
            olderThanOrEqualTo: year2021
        )
        let items = [
            video("big-old-a", bytes: 300_000_000, created: year2020),   // grande + vecchio ✓
            video("big-old-b", bytes: 500_000_000, created: year2019),   // grande + vecchio ✓ (più grande)
            video("big-recent", bytes: 400_000_000, created: year2024),  // grande ma recente ✗
            video("small-old", bytes: 10_000_000, created: year2019),    // vecchio ma piccolo ✗
            photo("photo-big-old", bytes: 900_000_000, created: year2019) // foto, non video ✗
        ]

        let result = LargeOldVideoSelection.select(items, thresholds: thresholds)

        // Solo i due video grandi+vecchi, ordinati per dimensione decrescente.
        XCTAssertEqual(result.map(\.asset.id), ["big-old-b", "big-old-a"])
    }

    // A parità di dimensione, il più vecchio viene prima (secondo criterio: età).
    func test_tieOnSizeOrdersOlderFirst() {
        let thresholds = LargeOldThresholds(minBytes: 0, olderThanOrEqualTo: year2024)
        let items = [
            video("newer", bytes: 200_000_000, created: year2021),
            video("older", bytes: 200_000_000, created: year2019)
        ]

        let result = LargeOldVideoSelection.select(items, thresholds: thresholds)

        XCTAssertEqual(result.map(\.asset.id), ["older", "newer"])
    }

    // AC-060-2: nessun video oltre soglia → lista vuota (nessun falso positivo).
    func test_noVideoOverThresholdYieldsEmptyList() {
        let thresholds = LargeOldThresholds(
            minBytes: 1_000_000_000,   // soglia altissima
            olderThanOrEqualTo: year2021
        )
        let items = [
            video("a", bytes: 300_000_000, created: year2019),
            video("b", bytes: 500_000_000, created: year2020)
        ]

        let result = LargeOldVideoSelection.select(items, thresholds: thresholds)

        XCTAssertTrue(result.isEmpty)
    }

    // Un video senza data di creazione non è verificabile come "vecchio": escluso
    // (nessun falso positivo, invariante di onestà).
    func test_videoWithoutCreationDateIsExcluded() {
        let thresholds = LargeOldThresholds(minBytes: 0, olderThanOrEqualTo: year2024)
        let items = [video("no-date", bytes: 900_000_000, created: nil)]

        let result = LargeOldVideoSelection.select(items, thresholds: thresholds)

        XCTAssertTrue(result.isEmpty)
    }

    // Insieme vuoto: nessun risultato, nessun crash.
    func test_emptyInputYieldsEmptyList() {
        let thresholds = LargeOldThresholds(minBytes: 0, olderThanOrEqualTo: year2020)
        XCTAssertTrue(LargeOldVideoSelection.select([], thresholds: thresholds).isEmpty)
    }
}
