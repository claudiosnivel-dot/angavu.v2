import XCTest
import AngavuDomain

#if canImport(Vision) && canImport(CoreGraphics)
import Vision
import CoreGraphics
#endif

// FSE-C2 (Data) — Oracolo di INVARIANZA DI SCALA del feature print Vision, AC-FSE-C2-2.
//
// FSE-C1 fa decodificare il feature print a taglia piccola (`.featurePrint` ≈224px)
// invece del full-res: è puro risparmio SOLO se la distanza semantica del feature print
// è invariante alla taglia (Vision normalizza internamente il descrittore). Questo
// oracolo lo VERIFICA sul percorso Vision reale, con la STESSA richiesta che usa
// l'adapter (`VNGenerateImageFeaturePrintRequest` su `VNImageRequestHandler(cgImage:)`):
//   • la stessa immagine a due risoluzioni → distanza piccola, decisione «simile» stabile;
//   • un'immagine diversa → distanza nettamente maggiore (l'invarianza non è banale).
//
// Copertura dichiarata (L-COL-006): gira dove Vision+CoreGraphics ci sono (host macOS
// della CI e device); degrada a `throw XCTSkip` altrove. Nessun accesso rete: le
// immagini sono disegnate in memoria, mai lette da PhotoKit/iCloud.
final class FeaturePrintScaleInvarianceTests: XCTestCase {

    #if canImport(Vision) && canImport(CoreGraphics)

    /// Soglia semantica di decisione simile/non-simile: la STESSA dichiarata in
    /// produzione (`CategoryDetectionDefaults.similarity.semantic` = 0.5), riusata qui
    /// dal tipo di Domain così l'oracolo non fissa un magic number a parte.
    private let semanticDecisionThreshold = SimilarityThresholds(semantic: 0.5, hamming: 10).semantic

    func testFeaturePrintDistanceIsStableAcrossResolution() throws {
        let small = try makeFeaturePrint(size: 224) { drawStructuredScene(in: $0, size: 224) }
        let large = try makeFeaturePrint(size: 448) { drawStructuredScene(in: $0, size: 448) }

        var distance = Float(0)
        try small.computeDistance(&distance, to: large)

        XCTAssertTrue(distance.isFinite, "la distanza deve essere finita, mai NaN")
        // Invarianza: la stessa scena a 224 e a 448 resta «la stessa» → la decisione
        // simile/non-simile (distanza < soglia semantica) è stabile rispetto alla taglia.
        XCTAssertLessThan(
            distance, semanticDecisionThreshold,
            "la decisione «simile» non deve dipendere dalla taglia di decodifica (invarianza)"
        )
    }

    func testDifferentSceneIsFartherThanSameSceneRescaled() throws {
        let reference = try makeFeaturePrint(size: 224) { drawStructuredScene(in: $0, size: 224) }
        let rescaled = try makeFeaturePrint(size: 448) { drawStructuredScene(in: $0, size: 448) }
        let different = try makeFeaturePrint(size: 224) { drawContrastingScene(in: $0, size: 224) }

        var sameSceneDistance = Float(0)
        try reference.computeDistance(&sameSceneDistance, to: rescaled)
        var differentSceneDistance = Float(0)
        try reference.computeDistance(&differentSceneDistance, to: different)

        // L'invarianza non è banale: una scena DIVERSA è nettamente più lontana della
        // stessa scena ridimensionata (altrimenti «tutto è vicino» = metrica inutile).
        XCTAssertLessThan(
            sameSceneDistance, differentSceneDistance,
            "la stessa scena ridimensionata deve stare più vicina di una scena diversa"
        )
    }

    // MARK: - Costruzione feature print da CGImage disegnato (nessun PhotoKit)

    private func makeFeaturePrint(
        size: Int,
        draw: (CGContext) -> Void
    ) throws -> VNFeaturePrintObservation {
        let cgImage = try XCTUnwrap(makeCGImage(size: size, draw: draw), "disegno CGImage fallito")
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNGenerateImageFeaturePrintRequest()
        try handler.perform([request])
        guard let observation = request.results?.first else {
            throw XCTSkip("Vision non ha prodotto un feature print in questo ambiente")
        }
        return observation
    }

    private func makeCGImage(size: Int, draw: (CGContext) -> Void) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        draw(context)
        return context.makeImage()
    }

    /// Scena strutturata, disegnata in coordinate proporzionali alla taglia: identica a
    /// ogni risoluzione modulo la scala (è ciò di cui si prova l'invarianza).
    private func drawStructuredScene(in context: CGContext, size: Int) {
        let dimension = CGFloat(size)
        context.setFillColor(red: 0.15, green: 0.20, blue: 0.35, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: dimension, height: dimension))

        context.setFillColor(red: 0.90, green: 0.60, blue: 0.20, alpha: 1)
        context.fillEllipse(in: CGRect(
            x: dimension * 0.20, y: dimension * 0.20,
            width: dimension * 0.4, height: dimension * 0.4
        ))

        context.setFillColor(red: 0.20, green: 0.70, blue: 0.45, alpha: 1)
        context.fill(CGRect(
            x: dimension * 0.55, y: dimension * 0.55,
            width: dimension * 0.35, height: dimension * 0.30
        ))
    }

    /// Scena nettamente diversa (bande a forte contrasto): controllo negativo perché
    /// l'invarianza non degeneri in «ogni immagine è vicina».
    private func drawContrastingScene(in context: CGContext, size: Int) {
        let dimension = CGFloat(size)
        let bands = 8
        let bandHeight = dimension / CGFloat(bands)
        for index in 0..<bands {
            let shade: CGFloat = index.isMultiple(of: 2) ? 0.05 : 0.95
            context.setFillColor(red: shade, green: shade, blue: shade, alpha: 1)
            context.fill(CGRect(
                x: 0, y: CGFloat(index) * bandHeight,
                width: dimension, height: bandHeight
            ))
        }
    }

    #else

    func testFeaturePrintScaleInvarianceRequiresVision() throws {
        throw XCTSkip("Vision/CoreGraphics non disponibili: invarianza di scala non verificabile qui")
    }

    #endif
}
