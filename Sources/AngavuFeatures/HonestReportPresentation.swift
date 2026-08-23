import AngavuDomain

// Guscio UI — Report onesto: presentazione PURA dello stato del report.
//
// Mappa `HonestReportState` (T-114) nelle decisioni osservabili della schermata:
// la cifra-hero (esatta SOLO quando nulla è stimato, altrimenti marcata come
// stima), le righe per categoria (con la marca della quota stimata), lo spazio
// recuperabile (libreria vs device ORA + caveat iCloud) e il banner del conteggio
// parziale (accesso limited) con l'invito all'accesso completo. Platform-puro
// (nessun import SwiftUI): è l'ORACOLO testabile della logica di presentazione,
// così la resa SwiftUI resta il solo strato "compilato-ma-non-testato" (L-COL-006).
//
// Invarianti di onestà (T-102), per costruzione: mai un unico totale "esatto"
// quando c'è una porzione stimata; il caveat iCloud è esposto quando il device
// libera meno della libreria; il conteggio parziale è dichiarato e invita
// all'accesso completo. I caveat sono DERIVATI dal report di dominio, mai a mano.

/// Modello di presentazione del report onesto, derivato dallo stato del view-model.
public struct HonestReportPresentation: Equatable, Sendable {
    /// La classe di stato che il report sta mostrando: instrada il contenuto.
    public enum Kind: Equatable, Sendable {
        /// Report non ancora composto: la schermata lo carica alla comparsa.
        case idle
        /// Numeri veri disponibili: hero, righe, spazio recuperabile, caveat.
        case ready
        /// Composizione fallita (es. lettura indice): motivo esplicito, mai muto.
        case failed
    }

    /// La cifra-hero del report. `isExact == false` significa che va mostrata
    /// come stima (mai spacciata per un totale esatto quando qualcosa è stimato).
    public struct Hero: Equatable, Sendable {
        /// Byte da mostrare in evidenza.
        public let bytes: Int64
        /// Vero SOLO quando nulla è stimato: allora è un totale esatto.
        public let isExact: Bool

        public init(bytes: Int64, isExact: Bool) {
            self.bytes = bytes
            self.isExact = isExact
        }
    }

    /// Riga di una categoria, pronta per la View. La marca `isEstimated`
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
        /// Byte liberabili nella libreria (sorgente piena).
        public let libraryBytes: Int64
        /// Byte realmente liberabili sul device ORA (mai promessi oltre il reale).
        public let deviceBytesNow: Int64
        /// Vero quando parte dello spazio non si libera sul device ora (iCloud).
        public let iCloudCaveat: Bool

        public init(libraryBytes: Int64, deviceBytesNow: Int64, iCloudCaveat: Bool) {
            self.libraryBytes = libraryBytes
            self.deviceBytesNow = deviceBytesNow
            self.iCloudCaveat = iCloudCaveat
        }
    }

    /// La classe di stato corrente.
    public let kind: Kind
    /// Titolo breve dello stato.
    public let title: String
    /// Dettaglio opzionale (sottotitolo / messaggio d'errore).
    public let detail: String?
    /// La cifra-hero, presente solo nello stato `ready`.
    public let hero: Hero?
    /// Righe per categoria, in ordine stabile. Vuoto fuori dallo stato `ready`.
    public let categoryRows: [CategoryRow]
    /// Riepilogo dello spazio recuperabile, presente solo nello stato `ready`.
    public let reclaimable: ReclaimableSummary?
    /// Vero quando i conteggi sono parziali (accesso limited): mostrare il banner.
    public let showsPartialBanner: Bool
    /// Vero quando ha senso invitare all'accesso completo (accesso limited).
    public let invitesFullAccess: Bool
    /// Vero quando parte dello spazio è in iCloud: il caveat va mostrato.
    public let iCloudCaveat: Bool
    /// Vero nello stato `failed`: la UI offre di riprovare la composizione.
    public let showsRetry: Bool

    // Init privato coi default: ogni case di `init(state:)` specifica SOLO ciò che
    // differisce, così le combinazioni restano coerenti per costruzione.
    private init(
        kind: Kind,
        title: String,
        detail: String? = nil,
        hero: Hero? = nil,
        categoryRows: [CategoryRow] = [],
        reclaimable: ReclaimableSummary? = nil,
        showsPartialBanner: Bool = false,
        invitesFullAccess: Bool = false,
        iCloudCaveat: Bool = false,
        showsRetry: Bool = false
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.hero = hero
        self.categoryRows = categoryRows
        self.reclaimable = reclaimable
        self.showsPartialBanner = showsPartialBanner
        self.invitesFullAccess = invitesFullAccess
        self.iCloudCaveat = iCloudCaveat
        self.showsRetry = showsRetry
    }

    /// Deriva la presentazione dallo stato del report. Deterministica e totale:
    /// ogni `HonestReportState` ha una e una sola presentazione.
    public init(state: HonestReportState) {
        switch state {
        case .idle:
            self = .init(
                kind: .idle,
                title: "Report onesto",
                detail: "Angavu riassume i byte reali della tua libreria, coi caveat, tutto sul dispositivo."
            )
        case .ready(let screen):
            let report = screen.report
            self = .init(
                kind: .ready,
                title: "Report onesto",
                hero: Self.hero(for: report),
                categoryRows: report.categories.map(Self.row(for:)),
                reclaimable: ReclaimableSummary(
                    libraryBytes: screen.libraryReclaimable,
                    deviceBytesNow: screen.deviceReclaimableNow,
                    iCloudCaveat: screen.iCloudCaveat
                ),
                showsPartialBanner: report.countsArePartial,
                invitesFullAccess: report.invitesFullAccess,
                iCloudCaveat: report.iCloudCaveat
            )
        case .failed(let message):
            self = .init(
                kind: .failed,
                title: "Impossibile comporre il report",
                detail: message,
                showsRetry: true
            )
        }
    }

    // La cifra-hero: un totale "esatto" SOLO quando nulla è stimato; altrimenti la
    // somma marcata come stima (mai spacciata per esatta). Il boolean `isExact`
    // deriva da `singleExactTotalBytes`, unica fonte dell'invariante di onestà.
    private static func hero(for report: HonestReport) -> Hero {
        if let exact = report.singleExactTotalBytes {
            return Hero(bytes: exact, isExact: true)
        }
        return Hero(bytes: report.totalExactBytes + report.totalEstimatedBytes, isExact: false)
    }

    private static func row(for bytes: CategoryBytes) -> CategoryRow {
        CategoryRow(
            category: bytes.category,
            // Riusa l'unica fonte del titolo localizzato (dalla dashboard).
            title: DashboardPresentation.title(for: bytes.category),
            count: bytes.count,
            totalBytes: bytes.totalBytes,
            isEstimated: bytes.hasEstimatedPortion
        )
    }
}
