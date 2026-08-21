import XCTest
@testable import AngavuDomain

// T-014 — AC-014-1 / AC-014-2. Byte reali vs stima, senza barare.

final class ByteSizeTests: XCTestCase {

    // AC-014-1: dimensione esatta disponibile → ByteSize.exact col valore.
    func test_exactSize_whenResourceProvidesIt() {
        let raw = RawResourceSize(exactBytes: 12_345, fallbackEstimate: 9_999)
        let size = ByteSizePolicy.resolve(raw)

        XCTAssertEqual(size, .exact(bytes: 12_345))
        XCTAssertTrue(size.isExact)
        XCTAssertEqual(size.bytes, 12_345)
    }

    // AC-014-2: dimensione esatta assente → ByteSize.estimated, mai spacciata per exact.
    func test_estimatedSize_whenExactMissing() {
        let raw = RawResourceSize(exactBytes: nil, fallbackEstimate: 4_096)
        let size = ByteSizePolicy.resolve(raw)

        XCTAssertEqual(size, .estimated(bytes: 4_096))
        XCTAssertFalse(size.isExact, "una stima non deve mai risultare esatta")
        XCTAssertEqual(size.bytes, 4_096)
    }

    // Valori negativi normalizzati a 0 (nessuna dimensione negativa).
    func test_negativeValuesClampToZero() {
        let raw = RawResourceSize(exactBytes: -5, fallbackEstimate: -1)
        XCTAssertEqual(ByteSizePolicy.resolve(raw), .exact(bytes: 0))

        let onlyFallback = RawResourceSize(exactBytes: nil, fallbackEstimate: -10)
        XCTAssertEqual(ByteSizePolicy.resolve(onlyFallback), .estimated(bytes: 0))
    }
}
