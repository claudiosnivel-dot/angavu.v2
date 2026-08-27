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
    /// FSE-B1: risolutore batch dei PHAsset, riusabile da tutti gli adapter per la
    /// durata della scansione (fine dei fetch singoli per asset). Default
    /// `EmptyAssetHandleResolver` (nessun handle) finché `live()` non inietta
    /// `PHAssetBatchResolver`. Il cablaggio attraverso le fasi della scansione è FSE-F.
    public let handleResolver: any AssetHandleResolving
    public let deviceStorage: any DeviceStorageInspecting
    /// P0-2: capacità/spazio libero del device per il tetto di realtà (P0-3). Default
    /// `UnknownDeviceCapacity` (nessun tetto) finché il grafo reale non lo cabla.
    public let deviceCapacity: any DeviceCapacityReading
    /// P0-2b: probe della residenza per-asset reale. Default `AssumeResidentResidencyProbe`
    /// (segnaposto inerte) finché `live()` non inietta l'adapter PhotoKit reale: la
    /// dashboard mostra un numero device solo da una misura reale e completa.
    public let residencyProbe: any AssetResidencyProbing
    /// A-1: miniature reali degli asset. Default `NoThumbnailProvider` (placeholder)
    /// finché il grafo reale non inietta l'adapter PhotoKit.
    public let thumbnailProvider: any AssetThumbnailProviding
    /// C-1: port dei rilevatori delle categorie foto (duplicati esatti, foto simili,
    /// sfocate). Default null-object — una categoria senza il rilevatore reale resta
    /// vuota, mai numeri finti — finché `live()` non cabla gli adapter reali.
    public let contentHasher: any AssetContentHashing
    public let featurePrinter: any FeaturePrinting
    public let qualityScorer: any QualityScoring
    public let sharpnessScorer: any SharpnessScoring
    public let videoExporter: any VideoExporting
    public let videoSpecProvider: any VideoSpecProviding
    /// Porte dei domini extra-foto (contatti, calendari). `nil` finché non cablate
    /// dal grafo reale: capacità permission-gated ASSENTE, mai un fake nascosto.
    public let extraDomains: ExtraDomainsPorts?

    public init(
        authorizer: any PhotoLibraryAuthorizing,
        enumerator: any PhotoAssetEnumerating,
        indexReader: any AssetIndexReading,
        indexWriter: any AssetIndexWriting,
        byteResolver: any AssetByteSizeResolving,
        handleResolver: any AssetHandleResolving = EmptyAssetHandleResolver(),
        deviceStorage: any DeviceStorageInspecting,
        deviceCapacity: any DeviceCapacityReading = UnknownDeviceCapacity(),
        residencyProbe: any AssetResidencyProbing = AssumeResidentResidencyProbe(),
        thumbnailProvider: any AssetThumbnailProviding = NoThumbnailProvider(),
        contentHasher: any AssetContentHashing = NoContentHasher(),
        featurePrinter: any FeaturePrinting = NoFeaturePrinter(),
        qualityScorer: any QualityScoring = NoQualityScorer(),
        sharpnessScorer: any SharpnessScoring = NoSharpnessScorer(),
        videoExporter: any VideoExporting,
        videoSpecProvider: any VideoSpecProviding,
        extraDomains: ExtraDomainsPorts? = nil
    ) {
        self.authorizer = authorizer
        self.enumerator = enumerator
        self.indexReader = indexReader
        self.indexWriter = indexWriter
        self.byteResolver = byteResolver
        self.handleResolver = handleResolver
        self.deviceStorage = deviceStorage
        self.deviceCapacity = deviceCapacity
        self.residencyProbe = residencyProbe
        self.thumbnailProvider = thumbnailProvider
        self.contentHasher = contentHasher
        self.featurePrinter = featurePrinter
        self.qualityScorer = qualityScorer
        self.sharpnessScorer = sharpnessScorer
        self.videoExporter = videoExporter
        self.videoSpecProvider = videoSpecProvider
        self.extraDomains = extraDomains
    }
}

/// Porte dei domini extra-foto raccolte insieme: contatti duplicati (merge) e
/// calendari-spam (rimozione sottoscrizione). Sono capacità permission-gated,
/// presenti solo quando `AppEnvironment.live` le costruisce; l'assenza è esplicita
/// (`AppEnvironment.extraDomains == nil`), mai un fake che finge di funzionare.
public struct ExtraDomainsPorts {
    public let contactsProvider: any ContactsProviding
    public let contactMerger: any ContactMerging
    public let calendarsProvider: any CalendarsProviding
    public let calendarRemover: any CalendarSubscriptionRemoving

    public init(
        contactsProvider: any ContactsProviding,
        contactMerger: any ContactMerging,
        calendarsProvider: any CalendarsProviding,
        calendarRemover: any CalendarSubscriptionRemoving
    ) {
        self.contactsProvider = contactsProvider
        self.contactMerger = contactMerger
        self.calendarsProvider = calendarsProvider
        self.calendarRemover = calendarRemover
    }
}

#if canImport(SwiftData) && canImport(Photos)
import SwiftData

@available(macOS 14, iOS 17, *)
extension AppEnvironment {
    /// Grafo di produzione: adapter reali dietro i port + indice SwiftData.
    /// Riceve il `ModelContainer` (creato dall'app in `.modelContainer`), NON il
    /// contesto principale: l'indice crea un proprio `ModelContext` per operazione,
    /// così la scrittura della scansione (fuori dal main actor) non blocca la UI.
    public static func live(container: ModelContainer) -> AppEnvironment {
        let index = SwiftDataAssetIndex(container: container)
        return AppEnvironment(
            authorizer: SystemPhotoLibraryAuthorizer(),
            enumerator: SystemPhotoAssetEnumerator(),
            indexReader: index,
            indexWriter: index,
            // FSE-B2: la stessa istanza cachante è condivisa da scansione e categorie —
            // i byte si risolvono una volta (fase `resolvingSizes`) e si riusano, invece
            // di ri-risolvere ~25k asset a ogni schermata.
            byteResolver: CachingByteSizeResolver(base: PHAssetByteSizeResolver()),
            handleResolver: PHAssetBatchResolver(),
            deviceStorage: SystemDeviceStorageInspector(),
            deviceCapacity: SystemDeviceCapacityReader(),
            residencyProbe: PHAssetResidencyProbe(),
            thumbnailProvider: liveThumbnailProvider(),
            contentHasher: liveContentHasher(),
            featurePrinter: liveFeaturePrinter(),
            qualityScorer: liveQualityScorer(),
            sharpnessScorer: liveSharpnessScorer(),
            videoExporter: AVFoundationVideoExporter(),
            videoSpecProvider: AVFoundationVideoSpecProvider(),
            extraDomains: liveExtraDomains()
        )
    }

    /// Miniature reali quando PhotoKit+UIKit sono disponibili (iOS); altrimenti il
    /// null-object (build macOS della CI: placeholder, nessuna miniatura).
    private static func liveThumbnailProvider() -> any AssetThumbnailProviding {
        #if canImport(Photos) && canImport(UIKit)
        return PHCachingThumbnailProvider()
        #else
        return NoThumbnailProvider()
        #endif
    }

    /// C-1 — Adapter reali dei rilevatori quando i framework Apple sono disponibili;
    /// altrimenti il null-object (categoria vuota, mai numeri finti). Le guardie
    /// ricalcano ESATTAMENTE quelle dei rispettivi adapter, così la build non rompe su
    /// una piattaforma con Photos ma senza CryptoKit/Vision/CoreImage.

    private static func liveContentHasher() -> any AssetContentHashing {
        #if canImport(Photos) && canImport(CryptoKit)
        return PHAssetContentHasher()
        #else
        return NoContentHasher()
        #endif
    }

    private static func liveFeaturePrinter() -> any FeaturePrinting {
        #if canImport(Vision) && canImport(Photos)
        return VisionFeaturePrinter()
        #else
        return NoFeaturePrinter()
        #endif
    }

    private static func liveQualityScorer() -> any QualityScoring {
        #if canImport(Vision) && canImport(Photos) && canImport(ImageIO) && canImport(CoreGraphics)
        return VisionQualityScorer()
        #else
        return NoQualityScorer()
        #endif
    }

    private static func liveSharpnessScorer() -> any SharpnessScoring {
        #if canImport(Photos) && canImport(ImageIO) && canImport(CoreGraphics)
        return CoreImageSharpnessScorer()
        #else
        return NoSharpnessScorer()
        #endif
    }

    /// Costruisce le porte extra-foto reali quando i framework sono disponibili
    /// (iOS/macOS); altrimenti `nil` — la schermata dichiara la capacità assente.
    private static func liveExtraDomains() -> ExtraDomainsPorts? {
        #if canImport(Contacts) && canImport(EventKit)
        return ExtraDomainsPorts(
            contactsProvider: SystemContactsProvider(),
            contactMerger: SystemContactMerger(),
            calendarsProvider: SystemCalendarsProvider(),
            calendarRemover: SystemCalendarSubscriptionRemover()
        )
        #else
        return nil
        #endif
    }
}
#endif
