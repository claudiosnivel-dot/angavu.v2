import XCTest

#if canImport(Vision) && canImport(CoreGraphics)
import Vision
import CoreGraphics
#endif

// FSE-C2 (Data) — Oracolo di INVARIANZA DI SCALA del feature print Vision, AC-FSE-C2-2.
//
// FSE-C1 fa decodificare il feature print a taglia piccola (`.featurePrint` ≈224px)
// invece del full-res: è puro risparmio SOLO se la decisione simile/non-simile non
// dipende dalla taglia di decodifica. In produzione (`VisionFeaturePrinter`) i due
// operandi di ogni confronto sono SEMPRE decodificati alla stessa `.featurePrint`, quindi
// il rischio si riduce a: la taglia sposta la distanza più di quanto faccia il contenuto?
//
// Questo oracolo prova la proprietà DETERMINISTICA e onesta: un ORDINAMENTO, non una
// soglia assoluta. Sullo stesso percorso Vision dell'adapter
// (`VNGenerateImageFeaturePrintRequest` su `VNImageRequestHandler(cgImage:)`):
//     d(A, A')  <  d(A, A@2x)  <  d(A, B)
// «contenuto identico» più vicino di «stesso contenuto riscalato», a sua volta più vicino
// di «contenuto diverso». Cioè: il feature print discrimina il CONTENUTO più della SCALA —
// perciò decodificare a 224px non ribalta la decisione di similarità.
//
// Onestà/copertura (00-INDEX §6, L-COL-006): il VALORE ASSOLUTO della distanza
// cross-risoluzione non è significativo su immagini sintetiche (Vision è tarato su foto
// reali); la parità di clustering 224px vs full-res su FOTO REALI è device-only (§7),
// coerente col resto del repo (nessuna fixture d'immagine, nessun Vision reale in CI
// altrove). Qui si prova solo l'ordinamento, che è deterministico. Zero rete: le immagini
// sono disegnate in memoria, mai lette da PhotoKit/iCloud.
final class FeaturePrintScaleInvarianceTests: XCTestCase {

    #if canImport(Vision) && canImport(CoreGraphics)

    func testContentDominatesScaleInFeaturePrintDistance() throws {
        // Stessa scena, resa due volte a 224 (contenuto identico), una a 448 (riscalata),
        // e una scena diversa a 224 (contenuto diverso).
        let sceneA = try makeFeaturePrint(size: 224) { drawStructuredScene(in: $0, size: 224) }
        let sceneACopy = try makeFeaturePrint(size: 224) { drawStructuredScene(in: $0, size: 224) }
        let sceneARescaled = try makeFeaturePrint(size: 448) { drawStructuredScene(in: $0, size: 448) }
        let sceneB = try makeFeaturePrint(size: 224) { drawContrastingScene(in: $0, size: 224) }

        let identical = try distance(sceneA, sceneACopy)
        let rescaled = try distance(sceneA, sceneARescaled)
        let different = try distance(sceneA, sceneB)

        XCTAssertTrue(identical.isFinite && rescaled.isFinite && different.isFinite,
                      "le distanze devono essere finite, mai NaN")

        // Contenuto identico è il più vicino possibile (min): più vicino dello stesso
        // contenuto riscalato.
        XCTAssertLessThan(
            identical, rescaled,
            "contenuto identico deve stare più vicino dello stesso contenuto riscalato"
        )
        // Il cuore dell'invarianza: lo STESSO contenuto a un'altra taglia resta più vicino
        // di un contenuto DIVERSO → la taglia non ribalta la decisione simile/non-simile.
        XCTAssertLessThan(
            rescaled, different,
            "stesso contenuto riscalato deve stare più vicino di un contenuto diverso"
        )
    }

    // MARK: - Percorso Vision reale da CGImage disegnato (nessun PhotoKit)

    private func distance(_ lhs: VNFeaturePrintObservation, _ rhs: VNFeaturePrintObservation) throws -> Float {
        var value = Float(0)
        try lhs.computeDistance(&value, to: rhs)
        return value
    }

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
    /// ogni risoluzione modulo la scala (è ciò di cui si prova l'invarianza relativa).
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

    /// Scena nettamente diversa (bande a forte contrasto): contenuto diverso, controllo
    /// perché l'ordinamento non degeneri in «ogni immagine è vicina».
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
