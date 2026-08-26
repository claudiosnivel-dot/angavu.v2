// E-3 (resa) — Coriandoli leggeri per la schermata di successo, SwiftUI puro (Canvas
// + TimelineView), zero dipendenze, offline. Gated su Reduce Motion: con motion
// ridotto NIENTE particelle in movimento, ma un equivalente statico (uno scoppio di
// stelline) che conserva il segnale "festa" senza moto (coerente con R-06).
// Decorativo: `accessibilityHidden`, `allowsHitTesting(false)`. View-level (L-COL-006).
#if canImport(SwiftUI)
import CoreGraphics
import Foundation
import SwiftUI

struct ConfettiView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Deck deterministico (nessuna sorgente casuale di sistema): posizioni stabili,
    // calcolate una volta. Il moto è funzione del solo tempo (TimelineView).
    private let pieces = ConfettiPiece.deck(count: 60)

    var body: some View {
        if reduceMotion {
            Image(systemName: "sparkles")
                .font(.system(size: 84, weight: .semibold))
                .foregroundStyle(AuroraBrand.gradient)
                .accessibilityHidden(true)
        } else {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    draw(in: context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func draw(in context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let cycle = 2.8
        for piece in pieces {
            let raw = ((time * piece.speed) + piece.phase).truncatingRemainder(dividingBy: cycle)
            let fall = raw / cycle                              // 0…1 lungo la caduta
            let posY = CGFloat(fall) * (size.height + 40) - 20
            let posX = CGFloat(piece.x) * size.width
                + CGFloat(sin(fall * .pi * 2 + piece.phase)) * piece.drift

            var layer = context
            layer.opacity = 1.0 - fall * 0.25
            layer.translateBy(x: posX, y: posY)
            layer.rotate(by: .radians(fall * piece.spin))
            let rect = CGRect(x: -piece.size / 2, y: -piece.size / 2,
                              width: piece.size, height: piece.size * 1.6)
            layer.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(piece.color))
        }
    }
}

/// Un pezzo di coriandolo: ancora orizzontale, dimensione, velocità, fase, deriva,
/// rotazione e colore. Generato deterministicamente (LCG), niente RNG di sistema.
private struct ConfettiPiece {
    let x: Double
    let size: CGFloat
    let speed: Double
    let phase: Double
    let drift: CGFloat
    let spin: Double
    let color: Color

    static func deck(count: Int) -> [ConfettiPiece] {
        let palette: [Color] = [
            AuroraBrand.accentViola, AuroraBrand.accentBlu,
            AuroraBrand.accentFucsia, AuroraBrand.accentAzzurro
        ]
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(UInt64(1) << 53)
        }
        return (0..<count).map { idx in
            ConfettiPiece(
                x: next(),
                size: CGFloat(6 + next() * 8),
                speed: 0.6 + next() * 0.8,
                phase: next() * 2.8,
                drift: CGFloat(next() * 40 - 20),
                spin: next() * 12 - 6,
                color: palette[idx % palette.count]
            )
        }
    }
}
#endif
