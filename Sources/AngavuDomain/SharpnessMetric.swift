import Foundation

// FSE-C2 (Domain) — Matematica PURA della nitidezza, estratta dal Data layer.
//
// La nitidezza (varianza del Laplaciano su una griglia in scala di grigi, passata in
// una curva saturante `v / (v + k)`) è aritmetica pura: non dipende da CoreGraphics né
// da Photos, solo dai byte già in scala di grigi. Portandola qui:
//   • il Data layer (`SharpnessKernel`) tiene SOLO l'estrazione pixel (CoreGraphics) e
//     delega il calcolo — una sola fonte di verità per il kernel;
//   • un oracolo di Domain può costruire griglie sintetiche di nitidezza NOTA
//     (scacchiera ad alta frequenza = nitida; piatta/rampa = sfocata) e provare la
//     SOGLIA ri-tarata (FSE-C2, AC-FSE-C2-1) con la STESSA matematica di produzione —
//     nessun numero inventato, nessuna circolarità.
//
// Onestà (00-INDEX §6): il valore assoluto è un'euristica, sensibile alla RISOLUZIONE
// di decodifica. La taglia di riferimento è dichiarata (`referenceGridSide`, alimentata
// dalla taglia logica `.sharpness` ≈64px, FSE-C1): la soglia di sfocatura ha senso solo
// a questa scala e va ri-dichiarata se la taglia cambia (vedi `BlurThreshold`).

/// Metrica di nitidezza pura (varianza del Laplaciano normalizzata 0…1).
public enum SharpnessMetric {
    /// Lato della griglia in scala di grigi su cui si calcola il Laplaciano. È la
    /// RISOLUZIONE DI RIFERIMENTO della metrica: la soglia di sfocatura è tarata a
    /// questa scala (48×48, ricampionata da un originale ≈64px `.sharpness`, FSE-C1).
    public static let referenceGridSide = 48

    /// Costante di saturazione della curva `v / (v + k)` (euristica dichiarata).
    /// Al variare della taglia il valore grezzo della varianza scala: `saturation` e la
    /// soglia sono coppie dichiarate a `referenceGridSide`, non costanti universali.
    public static let saturation = 500.0

    /// Nitidezza normalizzata 0…1 (più alto = più nitido) da una griglia in scala di
    /// grigi `side`×`side`, o `nil` se il buffer è troppo piccolo per la taglia
    /// dichiarata (mai un valore fabbricato su dati insufficienti).
    ///
    /// Regola dei bordi: il Laplaciano si calcola sui soli pixel INTERNI (1..<side-1);
    /// una griglia con lato < 3 non ha pixel interni → `0` (nessun dettaglio misurabile),
    /// coerente col comportamento storico del kernel.
    public static func normalizedSharpness(grayscale: [UInt8], side: Int) -> Double? {
        guard side >= 1, grayscale.count >= side * side else { return nil }
        var sum = 0.0
        var sumOfSquares = 0.0
        var count = 0
        var row = 1
        while row < side - 1 {
            var column = 1
            while column < side - 1 {
                let center = Double(grayscale[row * side + column])
                let up = Double(grayscale[(row - 1) * side + column])
                let down = Double(grayscale[(row + 1) * side + column])
                let left = Double(grayscale[row * side + column - 1])
                let right = Double(grayscale[row * side + column + 1])
                let laplacian = up + down + left + right - 4 * center
                sum += laplacian
                sumOfSquares += laplacian * laplacian
                count += 1
                column += 1
            }
            row += 1
        }
        guard count > 0 else { return 0 }
        let mean = sum / Double(count)
        let variance = max(0, sumOfSquares / Double(count) - mean * mean)
        return variance / (variance + saturation)
    }
}
