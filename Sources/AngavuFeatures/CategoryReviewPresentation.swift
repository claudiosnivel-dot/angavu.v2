import AngavuDomain

// Guscio UI — Review di categoria: presentazione PURA dello stato di review.
//
// Mappa una `CategoryReview` (righe keep/removable, T-113) più lo stato del
// `DeletionFlow` (gate d'anteprima, T-050) nelle decisioni osservabili della
// schermata: fase corrente del gate, righe da tenere vs eliminabili, se l'azione
// «Elimina» è disponibile, l'insieme in anteprima e la nota della rete di
// sicurezza. Platform-puro (nessun import SwiftUI): è l'ORACOLO testabile della
// logica di presentazione, così la resa SwiftUI resta il solo strato
// «compilato-ma-non-testato» (L-COL-006).
//
// Invarianti di onestà, per costruzione: l'azione d'eliminazione è offerta SOLO
// mentre si rivede (mai durante l'anteprima o dopo la conferma) e SOLO se c'è
// almeno un removable; l'anteprima non è mai vuota; i keep non compaiono mai
// nell'insieme eliminabile.

/// Modello di presentazione della review, derivato da `CategoryReview` + stato del gate.
public struct CategoryReviewPresentation: Equatable, Sendable {

    /// Fase del gate d'anteprima, dal punto di vista della schermata.
    public enum Phase: Equatable, Sendable {
        /// Si rivede la lista: l'azione «Elimina» è offerta (se c'è del removable).
        case reviewing
        /// Anteprima mostrata, in attesa dell'assenso esplicito dell'utente.
        case previewing
        /// Eliminazione autorizzata: l'esecuzione reale è della rete di sicurezza.
        case confirmed
    }

    /// Riga presentabile: un asset e la sua disposizione (tenere / eliminabile).
    ///
    /// A-3: porta i metadati umani (categoria + data) quando disponibili, così la
    /// riga mostra «Screenshot · 14 mar 2024» invece del `localIdentifier` grezzo.
    /// A-2: porta lo stato di selezione (solo i removable sono selezionabili).
    public struct Row: Equatable, Sendable {
        public let id: String
        public let disposition: CategoryDisposition
        /// Categoria dell'asset (Foto/Video/Screenshot) per l'etichetta umana; `nil`
        /// quando i metadati non sono forniti (riga costruita dal solo id).
        public let category: DashboardCategory?
        /// Data di creazione, per l'etichetta umana. `nil` = sconosciuta.
        public let creationDate: Date?
        /// A-2: vero se selezionata per l'eliminazione (mai i keep).
        public let isSelected: Bool

        public init(
            id: String,
            disposition: CategoryDisposition,
            category: DashboardCategory? = nil,
            creationDate: Date? = nil,
            isSelected: Bool = false
        ) {
            self.id = id
            self.disposition = disposition
            self.category = category
            self.creationDate = creationDate
            self.isSelected = isSelected
        }

        /// A-2: solo i removable sono selezionabili; i keep sono protetti.
        public var isSelectable: Bool { disposition == .removable }

        /// Nome umano del tipo (Foto/Video/Screenshot), o `nil` senza metadati.
        /// Riusa l'unica fonte del titolo localizzato (dalla dashboard).
        public var kindLabel: String? {
            category.map { DashboardPresentation.title(for: $0) }
        }

        /// Titolo VISIBILE della riga: «Screenshot · <data>» quando i metadati ci
        /// sono, altrimenti solo il tipo, altrimenti «Elemento». La View passa la
        /// data già formattata (unica fonte del formato locale).
        public func displayTitle(formattedDate: String?) -> String {
            let base = kindLabel ?? "Elemento"
            if let formattedDate { return "\(base) · \(formattedDate)" }
            return base
        }

        /// Etichetta VoiceOver UMANA della riga. L'`id` è un `localIdentifier`
        /// PhotoKit (rumore per chi ascolta): resta visibile a schermo ma NON va
        /// mai letto ad alta voce. Con i metadati annuncia il tipo (e la data via
        /// `accessibilityLabel(formattedDate:)`); senza, un generico «Elemento».
        public var accessibilityLabel: String { kindLabel ?? "Elemento" }

        /// Etichetta VoiceOver col tipo e la data (quando disponibile), mai l'id grezzo.
        public func accessibilityLabel(formattedDate: String?) -> String {
            displayTitle(formattedDate: formattedDate)
        }

        /// Valore VoiceOver: la disposizione in parole umane.
        public var accessibilityValue: String {
            switch disposition {
            case .keep: return "da tenere"
            case .removable: return "da eliminare"
            }
        }
    }

    /// Titolo della categoria di pulizia (es. «Screenshot»).
    public let title: String
    /// Sottotitolo onesto: cosa contiene questa categoria.
    public let subtitle: String
    /// Fase corrente del gate d'anteprima.
    public let phase: Phase
    /// Righe da tenere (mai eliminabili), in ordine stabile.
    public let keepRows: [Row]
    /// Righe eliminabili, in ordine stabile.
    public let removableRows: [Row]
    /// Vero quando non c'è nulla da eliminare: la schermata mostra lo stato vuoto.
    public let isEmpty: Bool
    /// Vero SOLO mentre si rivede e c'è almeno un removable: l'unico momento in cui
    /// l'azione «Elimina» è offerta.
    public let canRequestDeletion: Bool
    /// Id in anteprima (in attesa d'assenso). Non vuoto SOLO in fase `previewing`.
    public let previewAssetIds: [String]
    /// Id la cui eliminazione è stata autorizzata. Non vuoto SOLO in fase `confirmed`.
    public let confirmedAssetIds: [String]
    /// Nota della rete di sicurezza: recupero di sistema, mostrata all'anteprima e
    /// alla conferma. Unica fonte del testo (riusata dalla View).
    public let safetyNote: String

    /// Numero di elementi da tenere.
    public var keepCount: Int { keepRows.count }
    /// Numero di elementi eliminabili.
    public var removableCount: Int { removableRows.count }
    /// A-2: numero di eliminabili SELEZIONATI (alimenta la CTA «Elimina N selezionati»).
    public var selectedRemovableCount: Int { removableRows.reduce(0) { $0 + ($1.isSelected ? 1 : 0) } }
    /// A-2: vero se c'è almeno un eliminabile selezionato (la CTA è azionabile).
    public var hasSelection: Bool { selectedRemovableCount > 0 }
    /// Numero di elementi in anteprima.
    public var previewCount: Int { previewAssetIds.count }
    /// Numero di elementi la cui eliminazione è autorizzata.
    public var confirmedCount: Int { confirmedAssetIds.count }

    private init(
        title: String,
        subtitle: String,
        phase: Phase,
        keepRows: [Row],
        removableRows: [Row],
        previewAssetIds: [String],
        confirmedAssetIds: [String]
    ) {
        self.title = title
        self.subtitle = subtitle
        self.phase = phase
        self.keepRows = keepRows
        self.removableRows = removableRows
        self.isEmpty = removableRows.isEmpty && keepRows.isEmpty
        self.canRequestDeletion = (phase == .reviewing) && !removableRows.isEmpty
        self.previewAssetIds = previewAssetIds
        self.confirmedAssetIds = confirmedAssetIds
        self.safetyNote = "Gli elementi finiscono in «Eliminati di recente» e restano "
            + "recuperabili per ~30 giorni: nulla sparisce subito."
    }

    /// Deriva la presentazione da una review e dallo stato del gate. Deterministica
    /// e totale: ogni combinazione ha una e una sola presentazione.
    ///
    /// `assets`/`selection` sono opzionali (default vuoti) per retro-compatibilità:
    /// senza metadati le righe restano generiche («Elemento»); con essi mostrano il
    /// tipo + data (A-3) e lo stato di selezione (A-2).
    public init(
        review: CategoryReview,
        flowState: DeletionFlow.State,
        title: String,
        subtitle: String,
        assets: [String: LibraryAsset] = [:],
        selection: Set<String> = []
    ) {
        let keep = review.keepIds.map {
            Self.enrichedRow(id: $0, disposition: .keep, assets: assets, selection: selection)
        }
        let removable = review.removableIds.map {
            Self.enrichedRow(id: $0, disposition: .removable, assets: assets, selection: selection)
        }

        switch flowState {
        case .idle:
            self = .init(
                title: title, subtitle: subtitle, phase: .reviewing,
                keepRows: keep, removableRows: removable,
                previewAssetIds: [], confirmedAssetIds: []
            )
        case .previewing(let ids, _):
            self = .init(
                title: title, subtitle: subtitle, phase: .previewing,
                keepRows: keep, removableRows: removable,
                previewAssetIds: ids, confirmedAssetIds: []
            )
        case .confirmed(let ids), .deleting(let ids):
            // L'esecuzione reale (`deleting`) è della rete di sicurezza (fuori scope
            // T-113): dal punto di vista della schermata è «autorizzata».
            self = .init(
                title: title, subtitle: subtitle, phase: .confirmed,
                keepRows: keep, removableRows: removable,
                previewAssetIds: [], confirmedAssetIds: ids
            )
        }
    }

    /// Costruisce una `Row` arricchita coi metadati (A-3) e lo stato di selezione
    /// (A-2). Senza metadati (`assets[id] == nil`) la riga resta generica; solo i
    /// removable possono risultare selezionati (i keep sono protetti).
    private static func enrichedRow(
        id: String,
        disposition: CategoryDisposition,
        assets: [String: LibraryAsset],
        selection: Set<String>
    ) -> Row {
        let asset = assets[id]
        return Row(
            id: id,
            disposition: disposition,
            category: asset.map(DashboardCategory.of),
            creationDate: asset?.creationDate,
            isSelected: disposition == .removable && selection.contains(id)
        )
    }
}
