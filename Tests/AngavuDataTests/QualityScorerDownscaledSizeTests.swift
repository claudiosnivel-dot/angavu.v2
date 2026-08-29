import XCTest
import AngavuDomain
@testable import AngavuData

// FSE-I2 (AC-FSE-I2-1) — Oracolo a livello di ADAPTER: il quality scorer del keep-best
// chiede al provider ridimensionato la sua taglia PICCOLA dichiarata (≈224px
// `.featurePrint`), MAI la piena risoluzione (come AC-FSE-C1-1 per nitidezza/feature
// print). Prima di FSE-I2 lo scorer decodificava l'originale full-res
// (`OnDeviceImageBytes.data`) una volta per membro di cluster → causa del ~1 min di
// freeze alla fase «simili» al 2° device-test.
//
// Il provider-spione restituisce un'immagine opaca senza `CGImage` reale → lo scorer
// degrada a un `QualityScore` neutro (nessun pixel), ma la TAGLIA richiesta è comunque
// registrata: è esattamente ciò che quest'oracolo verifica, senza device. Gira al
// confine Apple (macOS/iOS in CI); dove i framework non ci sono, il test è assente col
// tipo stesso (l'adapter è dietro lo stesso gate).

private final class QSStubDownscaledImage: DownscaledImage {}

private final class QSRecordingProvider: DownscaledImageProviding {
    private(set) var requestedSizes: [LogicalImageSize] = []
    func downscaledImage(for handle: AssetHandle, size: LogicalImageSize) -> DownscaledImage? {
        requestedSizes.append(size)
        return QSStubDownscaledImage()
    }
}

private func qsAsset(_ id: String) -> LibraryAsset {
    LibraryAsset(
        id: id,
        kind: .photo,
        pixelSize: PixelSize(width: 4000, height: 3000),   // originale grande: full-res sarebbe enorme
        creationDate: nil,
        subtypes: []
    )
}

final class QualityScorerDownscaledSizeTests: XCTestCase {

    #if canImport(Vision) && canImport(Photos) && canImport(ImageIO) && canImport(CoreGraphics)
    func testQualityScorerRequestsSmallDeclaredSize() throws {
        let provider = QSRecordingProvider()
        let scorer = VisionQualityScorer(imageProvider: provider)

        _ = try scorer.score(for: qsAsset("A"))

        // Chiede la taglia piccola dichiarata (≈224px), una sola volta, mai il full-res.
        XCTAssertEqual(provider.requestedSizes, [.featurePrint])
        XCTAssertEqual(LogicalImageSize.featurePrint.longestSide, 224)
        XCTAssertTrue(
            provider.requestedSizes.allSatisfy { $0.longestSide <= 224 },
            "il quality scorer non chiede mai una taglia più grande della piccola dichiarata"
        )
    }

    // Nessun pixel producibile (immagine opaca senza CGImage) → punteggio neutro
    // esplicito, mai un crash né un valore fabbricato (onestà: non residente = neutro).
    func testQualityScorerWithoutPixelsIsNeutral() throws {
        let provider = QSRecordingProvider()
        let scorer = VisionQualityScorer(imageProvider: provider)

        let score = try scorer.score(for: qsAsset("A"))

        XCTAssertEqual(score, QualityScore(sharpness: 0, faceQuality: nil, aesthetics: nil))
    }
    #endif
}
