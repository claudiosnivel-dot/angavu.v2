import XCTest
import AngavuDomain

// FSE-B1 — Oracolo del RIUSO: lo stesso asset, toccato da più adapter nella stessa
// scansione (byte E residenza E pixel), è risolto UNA sola volta e riusato.
//
// La prova è a livello di pattern (Domain/Features puri, gira su Linux): gli adapter
// reali sono Apple-only e device-only (L-COL-006). Si prova che, risolvendo una volta
// in una mappa condivisa (`ResolvedAssetHandles`), ogni consumatore legge lo STESSO
// handle senza innescare un nuovo fetch — che è esattamente ciò che FSE-F cablerà.
//   • AC-FSE-B1-2: contatore di risoluzione = 1 per asset, handle riusato fra adapter.

// MARK: - Doppioni di test

private final class FakeHandle: AssetHandle {
    let assetLocalIdentifier: String
    init(_ id: String) { self.assetLocalIdentifier = id }
}

/// Resolver-spia: conta quante VOLTE ogni id viene risolto (una risoluzione = un id
/// incluso in una chiamata `resolve`). Prova che gli adapter non rifetchano.
private final class SpyResolver: AssetHandleResolving {
    private(set) var resolveCallCount = 0
    private(set) var resolutionsPerID: [String: Int] = [:]

    func resolve(localIdentifiers: [String]) -> ResolvedAssetHandles {
        resolveCallCount += 1
        var handles: [AssetHandle] = []
        for id in localIdentifiers {
            resolutionsPerID[id, default: 0] += 1
            handles.append(FakeHandle(id))
        }
        return ResolvedAssetHandles(handles)
    }
}

final class BatchResolverReuseTests: XCTestCase {

    // AC-FSE-B1-2 — una scansione risolve gli asset UNA volta; byte, residenza e pixel
    // leggono lo stesso handle dalla mappa condivisa (contatore di risoluzione = 1 per
    // asset), senza rifetchare.
    func testHandleResolvedOnceAndReusedAcrossAdapters() {
        let ids = ["A", "B"]
        let resolver = SpyResolver()

        // La scansione risolve UNA volta all'inizio e condivide la mappa.
        let handles = resolver.resolve(localIdentifiers: ids)

        // Tre "adapter" (byte, residenza, pixel) chiedono l'handle già risolto.
        let forBytes = ids.map { handles.handle(for: $0) }
        let forResidency = ids.map { handles.handle(for: $0) }
        let forPixels = ids.map { handles.handle(for: $0) }

        // Un solo batch di risoluzione, e ogni id risolto esattamente una volta.
        XCTAssertEqual(resolver.resolveCallCount, 1)
        XCTAssertEqual(resolver.resolutionsPerID, ["A": 1, "B": 1])

        // Ogni adapter ha ricevuto un handle non-nil...
        XCTAssertTrue(forBytes.allSatisfy { $0 != nil })
        XCTAssertTrue(forResidency.allSatisfy { $0 != nil })
        XCTAssertTrue(forPixels.allSatisfy { $0 != nil })

        // ...ed è lo STESSO handle (identità), prova del riuso senza refetch.
        for index in ids.indices {
            XCTAssertTrue(forBytes[index] === forResidency[index])
            XCTAssertTrue(forResidency[index] === forPixels[index])
        }
    }

    // Un asset assente dalla scansione (nuovo) non è servito con un handle finto: la
    // mappa restituisce nil (l'adapter ricadrà sul proprio fetch on-demand).
    func testUnresolvedAssetIsNilNotFabricated() {
        let resolver = SpyResolver()
        let handles = resolver.resolve(localIdentifiers: ["A"])

        XCTAssertNotNil(handles.handle(for: "A"))
        XCTAssertNil(handles.handle(for: "NEW"))
        XCTAssertEqual(resolver.resolutionsPerID["NEW"], nil)
    }
}
