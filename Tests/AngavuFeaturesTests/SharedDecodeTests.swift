import XCTest
import AngavuDomain

// FSE-C1 — Oracolo della CONDIVISIONE del decode (Domain puro, gira su Linux/CI).
//
// Quando due rilevatori (foto simili E sfocate) chiedono la stessa immagine alla
// stessa taglia nella stessa scansione, il decoratore `SharedDownscaledImageProvider`
// fa pagare UN solo decode (memoizzazione per `(id, taglia)`), provato con un provider
// spione. Taglie diverse restano decode distinti (onestà: nessuna condivisione finta),
// e un non-residente resta `nil` senza ritentare a ogni confronto.
//   • AC-FSE-C1-3: decodificata una sola volta per taglia condivisa (contatore = 1).

// MARK: - Doppioni di test

private final class StubDownscaledImage: DownscaledImage {}

/// Provider-spione che CONTA i decode reali per `(id, taglia)`. Ogni decode produce
/// un'immagine con identità distinta, così un decode ripetuto sarebbe osservabile sia
/// come conteggio sia come identità diversa.
private final class CountingProvider: DownscaledImageProviding {
    private(set) var decodeCount = 0
    private(set) var decodesPerKey: [String: Int] = [:]
    private let nonResident: Set<String>

    init(nonResident: Set<String> = []) { self.nonResident = nonResident }

    func downscaledImage(for handle: AssetHandle, size: LogicalImageSize) -> DownscaledImage? {
        let key = "\(handle.assetLocalIdentifier)#\(size.longestSide)"
        decodeCount += 1
        decodesPerKey[key, default: 0] += 1
        return nonResident.contains(handle.assetLocalIdentifier) ? nil : StubDownscaledImage()
    }
}

final class SharedDecodeTests: XCTestCase {

    // AC-FSE-C1-3 — foto simili E sfocate chiedono la stessa immagine alla stessa taglia:
    // il decode reale avviene UNA sola volta, ed entrambi ricevono LA STESSA immagine.
    func testSameImageSharedSizeDecodedOnce() {
        let spy = CountingProvider()
        let shared = SharedDownscaledImageProvider(base: spy)
        let handle = IdentifierAssetHandle("A")

        // "Simili" chiede A a taglia condivisa; poi "sfocate" chiede lo stesso A/taglia.
        let forSimilar = shared.downscaledImage(for: handle, size: .featurePrint)
        let forBlurry = shared.downscaledImage(for: handle, size: .featurePrint)

        XCTAssertEqual(spy.decodeCount, 1)                       // un solo decode reale
        XCTAssertEqual(spy.decodesPerKey["A#224"], 1)
        XCTAssertNotNil(forSimilar)
        XCTAssertTrue(forSimilar === forBlurry)                  // stessa immagine riusata
    }

    // Taglie diverse per lo stesso asset = decode distinti (onestà: nessuna condivisione
    // fabbricata fra 64px e 224px).
    func testDifferentSizesAreDistinctDecodes() {
        let spy = CountingProvider()
        let shared = SharedDownscaledImageProvider(base: spy)
        let handle = IdentifierAssetHandle("A")

        _ = shared.downscaledImage(for: handle, size: .sharpness)
        _ = shared.downscaledImage(for: handle, size: .featurePrint)

        XCTAssertEqual(spy.decodeCount, 2)
        XCTAssertEqual(spy.decodesPerKey["A#64"], 1)
        XCTAssertEqual(spy.decodesPerKey["A#224"], 1)
    }

    // Un non-residente è memoizzato come "miss": il secondo consumatore NON ritenta il
    // decode, e riceve comunque `nil` (mai promosso a immagine).
    func testNonResidentMissIsMemoizedAndStaysNil() {
        let spy = CountingProvider(nonResident: ["ICLOUD"])
        let shared = SharedDownscaledImageProvider(base: spy)
        let handle = IdentifierAssetHandle("ICLOUD")

        let first = shared.downscaledImage(for: handle, size: .sharpness)
        let second = shared.downscaledImage(for: handle, size: .sharpness)

        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(spy.decodeCount, 1)                       // tentato una volta sola
    }

    // `evictAll()` (dieta memoria per-asset del motore concorrente, FSE-D) forza un nuovo
    // decode al prossimo uso: la cache non tiene viva l'intera libreria.
    func testEvictAllForcesRedecode() {
        let spy = CountingProvider()
        let shared = SharedDownscaledImageProvider(base: spy)
        let handle = IdentifierAssetHandle("A")

        _ = shared.downscaledImage(for: handle, size: .sharpness)
        shared.evictAll()
        _ = shared.downscaledImage(for: handle, size: .sharpness)

        XCTAssertEqual(spy.decodeCount, 2)
    }
}
