import AngavuDomain
import AngavuData

// T-110 (wiring) — Composition root.
//
// AppEnvironment è il contenitore di dipendenze iniettabile: espone i servizi
// SOLO dietro i port (protocolli del Domain/Data), mai i tipi concreti. La
// factory `live(context:)` costruisce il grafo reale (adapter di sistema +
// indice SwiftData); i test iniettano fake. Nessun singleton nascosto: ogni
// feature riceve i servizi da qui.
//
// Cresce coi task del macrotask `wiring`: qui i port del nucleo (scansione +
// dashboard); i successivi (rilevatori, deleter, exporter, extra-foto) si
// aggiungono quando i rispettivi view-model entrano.

public struct AppEnvironment {
    public let authorizer: any PhotoLibraryAuthorizing
    public let enumerator: any PhotoAssetEnumerating
    public let indexReader: any AssetIndexReading
    public let indexWriter: any AssetIndexWriting
    public let byteResolver: any AssetByteSizeResolving
    public let deviceStorage: any DeviceStorageInspecting
    public let videoExporter: any VideoExporting
    public let videoSpecProvider: any VideoSpecProviding

    public init(
        authorizer: any PhotoLibraryAuthorizing,
        enumerator: any PhotoAssetEnumerating,
        indexReader: any AssetIndexReading,
        indexWriter: any AssetIndexWriting,
        byteResolver: any AssetByteSizeResolving,
        deviceStorage: any DeviceStorageInspecting,
        videoExporter: any VideoExporting,
        videoSpecProvider: any VideoSpecProviding
    ) {
        self.authorizer = authorizer
        self.enumerator = enumerator
        self.indexReader = indexReader
        self.indexWriter = indexWriter
        self.byteResolver = byteResolver
        self.deviceStorage = deviceStorage
        self.videoExporter = videoExporter
        self.videoSpecProvider = videoSpecProvider
    }
}

#if canImport(SwiftData) && canImport(Photos)
import SwiftData

@available(macOS 14, iOS 17, *)
extension AppEnvironment {
    /// Grafo di produzione: adapter reali dietro i port + indice SwiftData.
    /// Il `ModelContext` è creato dall'app (WindowGroup) e passato qui.
    public static func live(context: ModelContext) -> AppEnvironment {
        let index = SwiftDataAssetIndex(context: context)
        return AppEnvironment(
            authorizer: SystemPhotoLibraryAuthorizer(),
            enumerator: SystemPhotoAssetEnumerator(),
            indexReader: index,
            indexWriter: index,
            byteResolver: PHAssetByteSizeResolver(),
            deviceStorage: SystemDeviceStorageInspector(),
            videoExporter: AVFoundationVideoExporter(),
            videoSpecProvider: AVFoundationVideoSpecProvider()
        )
    }
}
#endif
