import XCTest
import AngavuDomain
@testable import AngavuData

// FSE-C1 — Oracolo a livello di ADAPTER: i rilevatori reali chiedono al provider
// ridimensionato la loro taglia PICCOLA dichiarata, mai il full-res. Gira al confine
// Apple (macOS/iOS in CI); degrada a skip dove i framework non ci sono.
//   • AC-FSE-C1-1: la nitidezza chiede `.sharpness` (64px); il feature print `.featurePrint`.
//
// Il provider-spione restituisce un'immagine opaca senza `CGImage` reale → gli adapter
// degradano a `nil` (nessun pixel), ma la TAGLIA richiesta è comunque registrata: è
// esattamente ciò che quest'oracolo verifica.

private final class StubDownscaledImage: DownscaledImage {}

private final class RecordingProvider: DownscaledImageProviding {
    private(set) var requestedSizes: [LogicalImageSize] = []
    func downscaledImage(for handle: AssetHandle, size: LogicalImageSize) -> DownscaledImage? {
        requestedSizes.append(size)
        return StubDownscaledImage()
    }
}

private func makeAsset(_ id: String) -> LibraryAsset {
    LibraryAsset(
        id: id,
        kind: .photo,
        pixelSize: PixelSize(width: 100, height: 100),
        creationDate: nil,
        subtypes: []
    )
}

final class DownscaledSizeRequestTests: XCTestCase {

    #if canImport(Photos) && canImport(ImageIO) && canImport(CoreGraphics)
    func testSharpnessScorerRequestsSmallSharpnessSize() throws {
        let provider = RecordingProvider()
        let scorer = CoreImageSharpnessScorer(imageProvider: provider)

        _ = try scorer.sharpness(for: makeAsset("A"))

        XCTAssertEqual(provider.requestedSizes, [.sharpness])
        XCTAssertEqual(LogicalImageSize.sharpness.longestSide, 64)
    }
    #endif

    #if canImport(Vision) && canImport(Photos)
    func testFeaturePrinterRequestsFeaturePrintSize() throws {
        let provider = RecordingProvider()
        let printer = VisionFeaturePrinter(imageProvider: provider)

        _ = try printer.distance(between: makeAsset("A"), and: makeAsset("B"))

        // Almeno il primo asset è stato richiesto alla taglia `.featurePrint` (il secondo
        // può non essere richiesto: senza feature print del primo la distanza è già `nil`).
        XCTAssertEqual(provider.requestedSizes.first, .featurePrint)
        XCTAssertTrue(provider.requestedSizes.allSatisfy { $0 == .featurePrint })
    }
    #endif
}
