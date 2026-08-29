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
    /// FSE-H2: dHash percettivo per-asset (miniatura C1). È il percorso PRINCIPALE dei
    /// simili (memoria O(1) per foto); il feature print resta conferma opzionale. Default
    /// `NoPerceptualHasher` (nessun dHash → nessun raggruppamento) finché `live()` non
    /// cabla l'adapter reale.
    public let perceptualHasher: any AssetPerceptualHashing
    public let qualityScorer: any QualityScoring
    public let sharpnessScorer: any SharpnessScoring
    /// FSE-J1 (censimento C1): eliminazione reale delle foto. Default null-object
    /// `NoAssetDeleter` (mai un falso successo) finché `live()` non cabla
    /// `SystemAssetDeleter` (PhotoKit → «Eliminati di recente») che allinea l'indice.
    public let assetDeleter: any AssetDeleting
    /// FSE-J3 (censimento C2): sostituzione compressa reale. Default null-object
    /// `NoCompressedInstaller` (mai un falso successo) finché `live()` non cabla
    /// `SystemCompressedAssetInstaller` (`PHAssetCreationRequest` per salvare + il
    /// deleter di J1 per eliminare l'originale, solo dopo un salvataggio verificato).
    public let compressedInstaller: any CompressedAssetInstalling
    /// FSE-J6 (censimento C3): persistenza dei derivati fra i lanci. Default null-object
    /// `NoDerivedResultStore` (nessun derivato persistito → la scansione ricalcola sempre)
    /// finché `live()` non cabla `SwiftDataDerivedStore(container:)`.
    public let derivedStore: any DerivedResultStoring
    /// FSE-J6: cache in memoria dei derivati sopra lo store persistito, CONDIVISA dalla
    /// scansione (get-or-compute del digest via `CachingContentDigests`) e dall'observer
    /// dei cambi libreria (FSE-J5, invalidazione per-asset). `nil` finché `live()` non la
    /// costruisce: senza cache la scansione ricalcola e l'observer non ha nulla da potare.
    public let derivedCache: DerivedResultCache?
    /// FSE-J6: risolutore PURO della versione del contenuto per chiavare i derivati. È la
    /// STESSA istanza che alimenta sia il decoratore della scansione sia il `warm` della
    /// cache, così le chiavi combaciano. `nil` quando la cache non è cablata.
    public let derivedVersioning: (any AssetContentVersioning)?
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
        perceptualHasher: any AssetPerceptualHashing = NoPerceptualHasher(),
        qualityScorer: any QualityScoring = NoQualityScorer(),
        sharpnessScorer: any SharpnessScoring = NoSharpnessScorer(),
        assetDeleter: any AssetDeleting = NoAssetDeleter(),
        compressedInstaller: any CompressedAssetInstalling = NoCompressedInstaller(),
        derivedStore: any DerivedResultStoring = NoDerivedResultStore(),
        derivedCache: DerivedResultCache? = nil,
        derivedVersioning: (any AssetContentVersioning)? = nil,
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
        self.perceptualHasher = perceptualHasher
        self.qualityScorer = qualityScorer
        self.sharpnessScorer = sharpnessScorer
        self.assetDeleter = assetDeleter
        self.compressedInstaller = compressedInstaller
        self.derivedStore = derivedStore
        self.derivedCache = derivedCache
        self.derivedVersioning = derivedVersioning
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
        // FSE-J1/J3: lo stesso deleter reale (struct value, con lo stesso indice condiviso)
        // alimenta sia l'eliminazione delle categorie (`assetDeleter`) sia la sostituzione
        // compressa (l'installer elimina l'originale con lo STESSO deleter → «Eliminati di
        // recente», indice allineato). Un'unica definizione, nessuna divergenza.
        let deleter = IndexAligningDeleter(base: SystemAssetDeleter(), index: index)
        // FSE-J6 (censimento C3): persistenza dei derivati cablata nel grafo reale.
        // Un'UNICA cache in memoria (`DerivedResultCache`) sopra lo store SwiftData:
        // la scansione la consulta (get-or-compute del digest, sotto) e l'observer dei
        // cambi libreria (FSE-J5) la invalida per-asset. Devono essere la STESSA istanza
        // — costruita qui una volta, condivisa a valle — o l'invalidazione non toccherebbe
        // la cache che la scansione legge. Il versioning è puro (nessun fetch): la stessa
        // istanza chiava il decoratore e il `warm`.
        let derivedStore = SwiftDataDerivedStore(container: container)
        let derivedCache = DerivedResultCache(store: derivedStore)
        let derivedVersioning = AssetFieldContentVersioning()
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
            // FSE-J6: get-or-compute del digest sopra la cache persistita. Il rilevatore
            // dei duplicati esatti chiede il digest a QUESTO adapter → una seconda scansione
            // riusa i digest persistiti (0 riletture/ri-hash), mai un digest fabbricato.
            contentHasher: CachingContentDigests(
                base: liveContentHasher(),
                cache: derivedCache,
                versioning: derivedVersioning
            ),
            featurePrinter: liveFeaturePrinter(),
            perceptualHasher: livePerceptualHasher(),
            qualityScorer: liveQualityScorer(),
            sharpnessScorer: liveSharpnessScorer(),
            // FSE-J1: eliminazione reale (PhotoKit → «Eliminati di recente») che allinea
            // l'indice all'esito. NON il null-object → l'app elimina davvero (censimento C1).
            assetDeleter: deleter,
            // FSE-J3: sostituzione compressa reale — orchestrazione pura che salva il
            // compresso (`PHAssetCreationSaver` → `PHAssetCreationRequest`) e, solo dopo un
            // salvataggio verificato, elimina l'originale con lo stesso deleter di J1. NON il
            // null-object → l'app libera davvero spazio (censimento C2).
            compressedInstaller: SafeCompressedAssetInstaller(
                saver: PHAssetCreationSaver(), deleter: deleter
            ),
            // FSE-J6: store reale + cache/versioning condivisi esposti a valle (scansione
            // per il `warm`, observer FSE-J5 per l'invalidazione per-asset). NON i default
            // null-object → i derivati sopravvivono ai lanci (censimento C3).
            derivedStore: derivedStore,
            derivedCache: derivedCache,
            derivedVersioning: derivedVersioning,
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

    /// FSE-H2 — dHash percettivo reale dalla miniatura C1 quando i framework grafici
    /// sono disponibili; altrimenti il null-object (nessun dHash, nessun raggruppamento).
    /// La guardia ricalca quella del `PerceptualDHashAdapter`.
    private static func livePerceptualHasher() -> any AssetPerceptualHashing {
        #if canImport(Photos) && canImport(ImageIO) && canImport(CoreGraphics)
        return DownscaledPerceptualHasher()
        #else
        return NoPerceptualHasher()
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
