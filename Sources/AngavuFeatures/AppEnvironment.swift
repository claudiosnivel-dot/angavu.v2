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
    /// P0-2: capacità/spazio libero del device per il tetto di realtà (P0-3). Default
    /// `UnknownDeviceCapacity` (nessun tetto) finché il grafo reale non lo cabla.
    public let deviceCapacity: any DeviceCapacityReading
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
        deviceStorage: any DeviceStorageInspecting,
        deviceCapacity: any DeviceCapacityReading = UnknownDeviceCapacity(),
        videoExporter: any VideoExporting,
        videoSpecProvider: any VideoSpecProviding,
        extraDomains: ExtraDomainsPorts? = nil
    ) {
        self.authorizer = authorizer
        self.enumerator = enumerator
        self.indexReader = indexReader
        self.indexWriter = indexWriter
        self.byteResolver = byteResolver
        self.deviceStorage = deviceStorage
        self.deviceCapacity = deviceCapacity
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
            byteResolver: PHAssetByteSizeResolver(),
            deviceStorage: SystemDeviceStorageInspector(),
            deviceCapacity: SystemDeviceCapacityReader(),
            videoExporter: AVFoundationVideoExporter(),
            videoSpecProvider: AVFoundationVideoSpecProvider(),
            extraDomains: liveExtraDomains()
        )
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
