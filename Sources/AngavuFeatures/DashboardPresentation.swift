import AngavuDomain

// Guscio UI — Dashboard «Numeri veri»: presentazione PURA dello stato dashboard.
//
// Mappa `DashboardState` (T-112) nelle decisioni osservabili della schermata:
// titolo/dettaglio onesti, righe per categoria (con la marcatura della quota
// stimata), riepilogo dello spazio recuperabile (libreria vs device ORA + caveat
// iCloud), banner accesso limited e marca del totale parziale. Platform-puro
// (nessun import SwiftUI): è l'ORACOLO testabile della logica di presentazione,
// così la resa SwiftUI resta il solo strato "compilato-ma-non-testato" (L-COL-006).
//
// Invarianti di onestà, per costruzione: la quota stimata è sempre marcata (mai
// fusa in un "esatto"), il caveat iCloud è esposto quando il device libera meno
// della libreria, e il conteggio parziale (accesso limited) è dichiarato tale.

/// Modello di presentazione della dashboard, derivato dallo stato del view-model.
public struct DashboardPresentation: Equatable, Sendable {
    /// La classe di stato che la dashboard sta mostrando: instrada il contenuto.
    public enum Kind: Equatable, Sendable {
        /// Numeri non ancora caricati: la schermata li carica alla comparsa.
        case idle
        /// Numeri veri disponibili: righe, spazio recuperabile, banner.
        case ready
        /// Lettura dell'indice fallita: motivo esplicito, mai un blocco muto.
        case failed
    }

    /// Riga di una categoria, pronta per la View. La marcatura `isEstimated`
    /// impedisce di presentare come esatto un totale che contiene una stima.
    public struct CategoryRow: Equatable, Sendable {
        public let category: DashboardCategory
        /// Titolo localizzato (Foto / Video / Screenshot).
        public let title: String
        /// Numero di elementi nella categoria.
        public let count: Int
        /// Byte totali (exact + estimated) della categoria.
        public let totalBytes: Int64
        /// Vero se parte del totale è stimata: va marcata, mai spacciata per esatta.
        public let isEstimated: Bool

        public init(category: DashboardCategory, title: String, count: Int, totalBytes: Int64, isEstimated: Bool) {
            self.category = category
            self.title = title
            self.count = count
            self.totalBytes = totalBytes
            self.isEstimated = isEstimated
        }

        /// Etichetta VoiceOver: il titolo di categoria (umano), così la riga è un
        /// solo elemento leggibile invece di 3-4 frammenti separati.
        public var accessibilityLabel: String { title }

        /// Valore VoiceOver: conteggio + byte (formattati dalla View, unica fonte
        /// del formato locale) + la marca di stima quando presente (mai un totale
        /// stimato spacciato per esatto anche all'ascolto).
        public func accessibilityValue(formattedBytes: String) -> String {
            let items = count == 1 ? "1 elemento" : "\(count) elementi"
            let base = "\(items), \(formattedBytes)"
            return isEstimated ? base + ", stima" : base
        }
    }

    /// Riepilogo onesto dello spazio recuperabile: libreria vs device ORA.
    public struct ReclaimableSummary: Equatable, Sendable {
        /// Byte liberabili nella libreria (sorgente piena, «include iCloud»).
        public let libraryBytes: Int64
        /// Byte realmente liberabili sul device ORA. Da mostrare come cifra SOLO se
        /// `deviceSpaceIsIndeterminate == false`; altrimenti la View mostra un caveat.
        public let deviceBytesNow: Int64
        /// Vero quando parte dello spazio non si libera sul device ora (iCloud) o la
        /// residenza è indeterminata.
        public let iCloudCaveat: Bool
        /// P0-3: vero quando la residenza sul device non è determinabile → niente
        /// cifra device, solo caveat (manifesto: mai un numero fabbricato).
        public let deviceSpaceIsIndeterminate: Bool

        public init(
            libraryBytes: Int64,
            deviceBytesNow: Int64,
            iCloudCaveat: Bool,
            deviceSpaceIsIndeterminate: Bool = false
        ) {
            self.libraryBytes = libraryBytes
            self.deviceBytesNow = deviceBytesNow
            self.iCloudCaveat = iCloudCaveat
            self.deviceSpaceIsIndeterminate = deviceSpaceIsIndeterminate
        }
    }

    /// La classe di stato corrente.
    public let kind: Kind
    /// Titolo breve dello stato.
    public let title: String
    /// Dettaglio opzionale (sottotitolo / messaggio d'errore).
    public let detail: String?
    /// Righe per categoria, in ordine stabile. Vuoto fuori dallo stato `ready`.
    public let categoryRows: [CategoryRow]
    /// Riepilogo dello spazio recuperabile, presente solo nello stato `ready`.
    public let reclaimable: ReclaimableSummary?
    /// Vero quando l'accesso è `limited`: mostrare l'invito all'accesso completo.
    public let showsLimitedBanner: Bool
    /// Vero quando il totale mostrato è PARZIALE: va dichiarato, mai spacciato per totale.
    public let isTotalPartial: Bool
    /// Vero nello stato `failed`: la UI offre di riprovare la lettura.
    public let showsRetry: Bool

    // Init privato coi default: ogni case di `init(state:)` specifica SOLO ciò che
    // differisce, così le combinazioni restano coerenti per costruzione.
    private init(
        kind: Kind,
        title: String,
        detail: String? = nil,
        categoryRows: [CategoryRow] = [],
        reclaimable: ReclaimableSummary? = nil,
        showsLimitedBanner: Bool = false,
        isTotalPartial: Bool = false,
        showsRetry: Bool = false
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.categoryRows = categoryRows
        self.reclaimable = reclaimable
        self.showsLimitedBanner = showsLimitedBanner
        self.isTotalPartial = isTotalPartial
        self.showsRetry = showsRetry
    }

    /// Deriva la presentazione dallo stato della dashboard. Deterministica e
    /// totale: ogni `DashboardState` ha una e una sola presentazione.
    public init(state: DashboardState) {
        switch state {
        case .idle:
            self = .init(
                kind: .idle,
                title: "Numeri veri",
                detail: "Angavu calcola i byte reali della tua libreria, tutto sul dispositivo."
            )
        case .ready(let screen):
            self = .init(
                kind: .ready,
                title: "Numeri veri",
                categoryRows: screen.categories.map(Self.row(for:)),
                reclaimable: ReclaimableSummary(
                    libraryBytes: screen.reclaimable.reclaimableLibrarySpace,
                    deviceBytesNow: screen.reclaimable.reclaimableDeviceSpaceNow,
                    iCloudCaveat: screen.reclaimable.iCloudCaveat,
                    deviceSpaceIsIndeterminate: screen.reclaimable.deviceSpaceIsIndeterminate
                ),
                showsLimitedBanner: screen.banner.showLimitedAccessBanner,
                isTotalPartial: screen.isTotalPartial
            )
        case .failed(let message):
            self = .init(
                kind: .failed,
                title: "Impossibile leggere i numeri",
                detail: message,
                showsRetry: true
            )
        }
    }

    /// Titolo localizzato di una categoria. Unica fonte del testo (riusata dalla View).
    public static func title(for category: DashboardCategory) -> String {
        switch category {
        case .photo: return "Foto"
        case .video: return "Video"
        case .screenshot: return "Screenshot"
        }
    }

    private static func row(for bytes: CategoryBytes) -> CategoryRow {
        CategoryRow(
            category: bytes.category,
            title: title(for: bytes.category),
            count: bytes.count,
            totalBytes: bytes.totalBytes,
            isEstimated: bytes.hasEstimatedPortion
        )
    }
}
