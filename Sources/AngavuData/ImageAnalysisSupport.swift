import Foundation
import AngavuDomain

// Supporto condiviso per l'analisi immagine on-device del Data layer.
//
// Il kernel di nitidezza è riusato dagli adapter di scoring (`VisionQualityScorer`
// di `similar_photos` e `CoreImageSharpnessScorer` di `blurry_photos`), così la
// matematica della nitidezza vive in un solo posto (niente duplicazione fra adapter).
// Tutto on-device: nessun byte lascia il device.

// MARK: - Kernel di nitidezza (varianza del Laplaciano)

#if canImport(CoreGraphics)
import CoreGraphics

/// Nitidezza normalizzata 0…1 dai byte di un'immagine: varianza del Laplaciano
/// discreto su una griglia in scala di grigi, passata in una curva saturante
/// `v / (v + k)`. Deterministico e cross-Apple (CoreGraphics puro): compila e gira
/// anche sull'host macOS della CI. Il valore assoluto è un'euristica; il confronto
/// relativo (ranking dentro un cluster, soglia di sfocatura) è ciò che conta.
///
/// FSE-C2: la MATEMATICA (varianza del Laplaciano + curva saturante) vive ora nel
/// Domain (`SharpnessMetric`, pura e provabile senza CoreGraphics); qui resta solo
/// l'estrazione pixel (ricampionamento in scala di grigi). Un solo posto per il kernel.
public enum SharpnessKernel {
    /// Lato della griglia in scala di grigi: è la RISOLUZIONE DI RIFERIMENTO della
    /// metrica, dichiarata nel Domain. La soglia di sfocatura è tarata a questa scala.
    public static let side = SharpnessMetric.referenceGridSide

    /// FSE-C1 — Nitidezza da un `CGImage` già ridimensionato dal provider
    /// (`DownscaledImageProviding`): nessuna decodifica full-res, si ricampiona solo la
    /// griglia `side`×`side`. `nil` se il disegno in scala di grigi fallisce.
    public static func normalizedSharpness(from cgImage: CGImage) -> Double? {
        guard let gray = grayscale(from: cgImage, side: side) else { return nil }
        return SharpnessMetric.normalizedSharpness(grayscale: gray, side: side)
    }

    /// Ridisegna un `CGImage` (già piccolo) a `side`×`side` in scala di grigi a 8 bit.
    private static func grayscale(from cgImage: CGImage, side: Int) -> [UInt8]? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let pixels = context.data else { return nil }

        let buffer = pixels.bindMemory(to: UInt8.self, capacity: side * side)
        return Array(UnsafeBufferPointer(start: buffer, count: side * side))
    }
}
#endif
