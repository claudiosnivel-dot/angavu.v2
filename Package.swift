// swift-tools-version: 5.9
// Angavu iOS — package multi-modulo con altitudine imposta dal grafo dei target.
// Regola-killer: AngavuDomain non dichiara dipendenze verso AngavuData/AngavuFeatures,
// così un import proibito dal Domain non compila (oracolo di altitudine, 00-INDEX §7).
import PackageDescription

// Gate di build: i warning sono errori sui moduli del package (T-003, sostituzione
// dell'oracolo knip). Applicato a tutti i target sorgente via swiftSettings.
let warningsAsErrors: [SwiftSetting] = [
    .unsafeFlags(["-warnings-as-errors"])
]

let package = Package(
    name: "Angavu",
    // Deployment target unico dei moduli: iOS 17.0 (DI-003). Nessun target sotto 17.0.
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "AngavuDomain", targets: ["AngavuDomain"]),
        .library(name: "AngavuData", targets: ["AngavuData"]),
        .library(name: "AngavuFeatures", targets: ["AngavuFeatures"])
    ],
    targets: [
        // Domain PURO: nessuna dipendenza verso altri moduli, nessun framework di
        // piattaforma (PhotoKit/Vision/AVFoundation). Testabile senza device.
        .target(
            name: "AngavuDomain",
            dependencies: [],
            swiftSettings: warningsAsErrors
        ),
        // Data: adatta la piattaforma al Domain. Dipende solo dal Domain (verso il basso).
        .target(
            name: "AngavuData",
            dependencies: ["AngavuDomain"],
            swiftSettings: warningsAsErrors
        ),
        // Features: presentazione. Dipende da Domain e Data (verso il basso).
        .target(
            name: "AngavuFeatures",
            dependencies: ["AngavuDomain", "AngavuData"],
            swiftSettings: warningsAsErrors
        ),
        // Test del Domain puro (oracolo logico, gira anche fuori da Apple).
        .testTarget(
            name: "AngavuDomainTests",
            dependencies: ["AngavuDomain"]
        ),
        // Test di fondazione: struttura package, grafo di altitudine, oracolo lint.
        .testTarget(
            name: "AngavuFoundationTests",
            dependencies: ["AngavuDomain", "AngavuData", "AngavuFeatures"]
        )
    ]
)
