import Foundation

// B-2a — Stima di BATCH del risparmio da compressione HEVC (dominio puro).
//
// Estende `CompressionEstimator` (T-080, single-item) all'aggregazione su una
// lista di video: risparmio per-item + un TOTALE, così la schermata «Comprimi
// video» può offrire una stima sull'intera coda (dove vivono i ~106 GB del
// device-test), non un video alla volta.
//
// ONESTÀ / NUMERI VERI (manifesto): ogni saving è `ByteSize.estimated`, mai
// garantito, e il totale è a sua volta `estimated`. Un video la cui `VideoSpec`
// (durata/bitrate) NON è leggibile off-device è **dichiarato non stimabile** ed
// escluso dal totale — mai riempito con uno 0 o una cifra inventata (il difetto
// «Non riesco a leggere durata/bitrate» resta onesto, non mascherato). Nessun
// import di AVFoundation: la spec arriva già risolta dal port `VideoSpecProviding`.

/// Un video candidato al batch, con la sua `VideoSpec` risolta off-device.
/// `spec == nil` ⇒ non stimabile (dati non leggibili senza rete): dichiarato tale.
public struct BatchCompressionItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let spec: VideoSpec?

    public init(id: String, spec: VideoSpec?) {
        self.id = id
        self.spec = spec
    }
}

/// Esito dell'aggregazione: per-item stimabile, id non stimabili dichiarati, e il
/// totale (sempre stima). L'ordine d'input è preservato (la sorgente ordina già
/// per dimensione desc: i grandi, che liberano più spazio, restano in cima).
public struct BatchCompressionEstimate: Equatable, Sendable {

    /// Risparmio stimato di un singolo video stimabile.
    public struct ItemSaving: Equatable, Sendable, Identifiable {
        public let id: String
        /// Sempre `ByteSize.estimated` (mai esatto): la ricodifica reale può variare.
        public let saving: ByteSize

        public init(id: String, saving: ByteSize) {
            self.id = id
            self.saving = saving
        }
    }

    /// Risparmio stimato per ciascun video con spec nota, in ordine d'input.
    public let perItem: [ItemSaving]
    /// Id dei video la cui spec è assente: dichiarati non stimabili, MAI stimati.
    public let unestimableIds: [String]
    /// Totale del risparmio stimato (somma dei `perItem`), sempre `estimated`.
    public let total: ByteSize

    public init(perItem: [ItemSaving], unestimableIds: [String], total: ByteSize) {
        self.perItem = perItem
        self.unestimableIds = unestimableIds
        self.total = total
    }

    /// Numero di video stimabili (con spec nota).
    public var estimableCount: Int { perItem.count }
    /// Numero di video non stimabili (spec assente), da dichiarare a schermo.
    public var unestimableCount: Int { unestimableIds.count }
}

// MARK: - B-2b — Selezione del sottoinsieme da comprimere (puro)

/// Stato di selezione dei video del batch. Puro e testabile.
///
/// ONESTÀ / OPT-IN (manifesto): la compressione è un'azione **opt-in** —
/// diversamente da screenshot/grandi-vecchi (preselezionati, opt-out), qui il
/// default è **nulla selezionato**: l'utente sceglie esplicitamente cosa
/// comprimere. `canStart` è falso finché la selezione è vuota (nessun avvio
/// silenzioso). L'ordine dell'universo `available` (già ordinato per dimensione
/// desc dalla sorgente) è preservato in `selectedInOrder`.
public struct BatchCompressionSelection: Equatable, Sendable {
    /// Universo dei candidati selezionabili, in ordine stabile.
    private let available: [String]
    private let availableSet: Set<String>
    /// Id attualmente selezionati (sottoinsieme di `available`).
    public private(set) var selected: Set<String>

    /// Default onesto: `selected` vuoto (nulla preselezionato, opt-in).
    public init(available: [String], selected: Set<String> = []) {
        self.available = available
        let universe = Set(available)
        self.availableSet = universe
        // Difesa: ignora id selezionati che non sono tra i candidati.
        self.selected = selected.intersection(universe)
    }

    /// Inverte la selezione di un candidato. Un id fuori dall'universo è ignorato
    /// (non si può selezionare ciò che non è un candidato).
    public mutating func toggle(_ id: String) {
        guard availableSet.contains(id) else { return }
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    /// Seleziona tutti i candidati.
    public mutating func selectAll() {
        selected = availableSet
    }

    /// Deseleziona tutto (torna al default opt-in).
    public mutating func selectNone() {
        selected = []
    }

    /// L'avvio è consentito SOLO con almeno un candidato selezionato.
    public var canStart: Bool { !selected.isEmpty }

    /// Numero di candidati selezionati.
    public var selectedCount: Int { selected.count }

    /// Id selezionati nell'ordine dell'universo (deterministico), non l'ordine
    /// arbitrario del `Set`. È questa la coda passata all'orchestrazione (B-2c).
    public var selectedInOrder: [String] {
        available.filter { selected.contains($0) }
    }
}

/// Aggregatore puro della stima di batch. Deterministico e totale.
public enum BatchCompressionEstimator {
    /// Stima il risparmio su tutta la lista con un unico `preset`. Gli item con
    /// `spec == nil` finiscono in `unestimableIds` (esclusi dal totale, dichiarati);
    /// gli altri contribuiscono col loro saving stimato. Il totale è la somma dei
    /// saving stimabili, marcato `estimated`.
    public static func estimate(
        items: [BatchCompressionItem],
        preset: HEVCPreset
    ) -> BatchCompressionEstimate {
        var perItem: [BatchCompressionEstimate.ItemSaving] = []
        var unestimable: [String] = []
        var totalBytes: Int64 = 0

        for item in items {
            guard let spec = item.spec else {
                unestimable.append(item.id)
                continue
            }
            let saving = CompressionEstimator.estimatedSaving(for: spec, preset: preset)
            perItem.append(.init(id: item.id, saving: saving))
            totalBytes += saving.bytes
        }

        return BatchCompressionEstimate(
            perItem: perItem,
            unestimableIds: unestimable,
            total: .estimated(bytes: totalBytes)
        )
    }
}
