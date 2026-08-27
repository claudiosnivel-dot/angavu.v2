import XCTest
@testable import AngavuDomain

// FSE-C1 — Oracolo del CONTRATTO del provider di immagine ridimensionata (Domain puro,
// gira su Linux/CI). Il guadagno di velocità è device-only (§7): qui si prova solo la
// LOGICA — la taglia richiesta è quella piccola dichiarata, e un non-residente resta
// `nil` (mai un'immagine fabbricata).
//   • AC-FSE-C1-1: il rilevatore nitidezza chiede la taglia piccola (64px), mai full-res.
//   • AC-FSE-C1-2: originale non producibile on-device → `nil`, mai un download né un finto.

// MARK: - Doppioni di test

/// Immagine ridimensionata finta: identità osservabile, nessun pixel (il Domain non li
/// legge mai — resta opaca, come in produzione).
private final class StubDownscaledImage: DownscaledImage {}

/// Provider-spia: registra ogni `(id, taglia)` richiesto e restituisce un'immagine
/// finta (o `nil` se l'id è dichiarato non residente). Prova quale taglia chiede chi
/// consuma il port, senza device.
private final class RecordingProvider: DownscaledImageProviding {
    private(set) var requests: [(id: String, size: LogicalImageSize)] = []
    private let nonResident: Set<String>

    init(nonResident: Set<String> = []) { self.nonResident = nonResident }

    func downscaledImage(for handle: AssetHandle, size: LogicalImageSize) -> DownscaledImage? {
        requests.append((handle.assetLocalIdentifier, size))
        return nonResident.contains(handle.assetLocalIdentifier) ? nil : StubDownscaledImage()
    }
}

final class DownscaledImageContractTests: XCTestCase {

    // AC-FSE-C1-1 — chiedendo l'immagine per la nitidezza, il provider riceve la taglia
    // `.sharpness` (piccola, 64px), mai la piena risoluzione.
    func testSharpnessRequestUsesSmallDeclaredSize() {
        let provider = RecordingProvider()
        let handle = IdentifierAssetHandle("A")

        let image = DownscaledImageRequest.image(for: handle, size: .sharpness, using: provider)

        XCTAssertNotNil(image)
        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertEqual(provider.requests.first?.size, .sharpness)
        // La taglia è piccola (mai un francobollo da un originale full-res).
        XCTAssertEqual(LogicalImageSize.sharpness.longestSide, 64)
    }

    // La stessa via serve il feature print a ≈224px (taglia dichiarata, piccola).
    func testFeaturePrintRequestUsesDeclaredSize() {
        let provider = RecordingProvider()
        let handle = IdentifierAssetHandle("A")

        _ = DownscaledImageRequest.image(for: handle, size: .featurePrint, using: provider)

        XCTAssertEqual(provider.requests.first?.size, .featurePrint)
        XCTAssertEqual(LogicalImageSize.featurePrint.longestSide, 224)
    }

    // Le taglie logiche dei rilevatori sono PICCOLE per costruzione; una taglia
    // esplicita è confinata a ≥1 (mai una richiesta degenere). Il tipo non ha alcun
    // caso "piena risoluzione": la vecchia via full-res è rimossa per costruzione.
    func testLogicalSizesAreSmallAndClamped() {
        XCTAssertEqual(LogicalImageSize.sharpness.longestSide, 64)
        XCTAssertEqual(LogicalImageSize.featurePrint.longestSide, 224)
        XCTAssertEqual(LogicalImageSize.pixels(128).longestSide, 128)
        XCTAssertEqual(LogicalImageSize.pixels(0).longestSide, 1)
        XCTAssertEqual(LogicalImageSize.pixels(-5).longestSide, 1)
    }

    // AC-FSE-C1-2 — un originale non producibile on-device (in iCloud, rete disabilitata)
    // → il provider restituisce `nil` e la richiesta lo propaga: mai un'immagine finta.
    // Il rilevatore degrada onestamente (nitidezza `nil` → mai "sfocato"; distanza `nil`
    // → fallback dHash), come già provato dai loro oracoli.
    func testNonResidentReturnsNilNeverFabricated() {
        let provider = RecordingProvider(nonResident: ["ICLOUD"])
        let handle = IdentifierAssetHandle("ICLOUD")

        let image = DownscaledImageRequest.image(for: handle, size: .sharpness, using: provider)

        XCTAssertNil(image)
        XCTAssertEqual(provider.requests.count, 1)   // ha tentato on-device, senza download
    }

    // Il null-object non produce mai un'immagine (categoria/asset non analizzabile).
    func testEmptyProviderYieldsNil() {
        let provider = EmptyDownscaledImageProvider()
        XCTAssertNil(provider.downscaledImage(for: IdentifierAssetHandle("A"), size: .featurePrint))
    }
}
