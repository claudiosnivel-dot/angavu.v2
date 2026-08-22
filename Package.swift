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
    // Deployment target dei moduli: iOS 17.0 (DI-003) è il target di prodotto.
    // macOS 14 è dichiarato SOLO per far girare gli oracoli sull'host in CI
    // (`swift build`/`test` su runner macOS): abilita le API PhotoKit (macOS 11+)
    // e SwiftData (macOS 14+) senza `#available` sparsi. L'app resta iOS-only
    // (target Xcode via App/project.yml).
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
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
        ),
        // Test del Data layer. I test SwiftData (T-012) sono guardati da
        // canImport(SwiftData): girano al confine Apple, degradano a skip altrove.
        .testTarget(
            name: "AngavuDataTests",
            dependencies: ["AngavuDomain", "AngavuData"]
        ),
        // Test del Features layer: navigazione e gate di anteprima (T-101).
        // Platform-puri (pilotano il DeletionFlow del Domain), girano ovunque.
        .testTarget(
            name: "AngavuFeaturesTests",
            dependencies: ["AngavuDomain", "AngavuFeatures"]
        )
    ]
)
