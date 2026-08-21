// swift-tools-version: 5.9
// Fixture dell'oracolo negativo di altitudine (AC-002-2), fedele alla topologia
// reale: DataLike dipende da DomainLike (direzione consentita, verso il basso).
// Un file di DomainLike importa però DataLike (direzione PROIBITA, verso l'alto):
// SwiftPM lo rifiuta in modo deterministico come dipendenza circolare, provando
// che l'altitudine è imposta dal grafo dei target, non da una convenzione.
import PackageDescription

let package = Package(
    name: "AltitudeViolation",
    targets: [
        // Direzione consentita, dichiarata: Data → Domain.
        .target(name: "DataLike", dependencies: ["DomainLike"]),
        // DomainLike NON dichiara dipendenze; l'import verso DataLike nel sorgente
        // è la violazione che rompe la build.
        .target(name: "DomainLike", dependencies: [])
    ]
)
