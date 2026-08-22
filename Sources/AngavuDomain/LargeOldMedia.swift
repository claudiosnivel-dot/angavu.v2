import Foundation

// Macrotask `large_old_media` — modello di dominio PURO delle liste ad alto
// ritorno di spazio.
//
// Tre pezzi, uno per task atomico, tutti senza alcun tipo di piattaforma
// (altitudine `domain ↛ data`, 00-INDEX §1bis):
//   • T-060 video grandi E vecchi, ordinati per dimensione/età;
//   • T-061 categorie in blocco: screenshot (subtype indicizzato) e screen
//     recording (euristica dichiarata sui video);
//   • T-062 proposta di eliminazione in blocco che confluisce nel gate di
//     anteprima obbligatoria della rete di sicurezza (T-050).
//
// Riusa i tipi già del cuore-foto: `SizedAsset` (Dashboard) accoppia asset e byte
// reali; `LibraryAsset.subtypes` porta già `.screenshot` dall'indice
// (library_index, T-011); `DeletionFlow` è il gate della safety_net (T-050).
// Nessun nuovo concetto di piattaforma: qui vivono solo filtri, ordinamenti e
// composizioni di dati, testabili su Linux senza device.

// MARK: - T-060 — Video grandi e vecchi

/// Soglie di "grande" e "vecchio" per i video. Le due condizioni sono
/// **congiunte** (AND): un video entra nella lista solo se è insieme grande *e*
/// vecchio. Le due grandezze vivono su scale diverse (byte vs data), quindi hanno
/// soglie separate: mai fuse in un unico numero.
public struct LargeOldThresholds: Equatable, Sendable {
    /// "Grande": dimensione in byte >= `minBytes` (inclusa).
    public let minBytes: Int64
    /// "Vecchio": data di creazione <= `olderThanOrEqualTo` (inclusa). Un asset
    /// senza data di creazione non è mai dichiarato vecchio (nessun falso positivo).
    public let olderThanOrEqualTo: Date

    public init(minBytes: Int64, olderThanOrEqualTo: Date) {
        self.minBytes = max(0, minBytes)
        self.olderThanOrEqualTo = olderThanOrEqualTo
    }
}

/// Selezione pura dei video grandi e vecchi dall'indice.
public enum LargeOldVideoSelection {
    /// Filtra i **video** che superano **entrambe** le soglie (grande *e* vecchio)
    /// e li ordina in modo deterministico: dimensione decrescente, poi età (più
    /// vecchio prima), poi `id` come tie-break stabile.
    ///
    /// Regole di onestà:
    ///  • solo `kind == .video` (foto e screenshot hanno le loro categorie);
    ///  • un video senza `creationDate` non è verificabile come "vecchio" →
    ///    escluso (mai un falso positivo, AC-060-2);
    ///  • la marcatura exact/estimated del `ByteSize` non cambia l'appartenenza:
    ///    conta il numero di byte, qualunque sia il grado di certezza.
    public static func select(
        _ items: [SizedAsset],
        thresholds: LargeOldThresholds
    ) -> [SizedAsset] {
        items
            .filter { $0.asset.kind == .video }
            .filter { $0.size.bytes >= thresholds.minBytes }
            .filter { item in
                guard let created = item.asset.creationDate else { return false }
                return created <= thresholds.olderThanOrEqualTo
            }
            .sorted { lhs, rhs in
                // 1) dimensione decrescente (criterio primario, AC-060-1).
                if lhs.size.bytes != rhs.size.bytes {
                    return lhs.size.bytes > rhs.size.bytes
                }
                // 2) età: il più vecchio (data minore) prima.
                let lhsDate = lhs.asset.creationDate ?? .distantFuture
                let rhsDate = rhs.asset.creationDate ?? .distantFuture
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
                // 3) tie-break stabile per id.
                return lhs.asset.id < rhs.asset.id
            }
    }
}

// MARK: - T-061 — Screenshot e screen recording in blocco

/// Euristica **dichiarata** per riconoscere le screen recording. PhotoKit non
/// espone un sottotipo dedicato per le registrazioni schermo (a differenza degli
/// screenshot, che hanno `.photoScreenshot`), quindi ci si affida a un'euristica
/// esplicita e deterministica sui soli dati che l'indice conosce:
///
///   una screen recording è un **video** le cui dimensioni in pixel coincidono
///   — a meno dell'orientamento — con una delle risoluzioni schermo note
///   iniettate dal chiamante.
///
/// L'insieme delle risoluzioni è passato dall'esterno (il Domain resta puro e
/// l'euristica testabile). È un'euristica, non una certezza: può avere falsi
/// negativi (registrazioni ritagliate) e va dichiarata come tale a valle.
public struct ScreenRecordingHeuristic: Equatable, Sendable {
    /// Risoluzioni schermo note in pixel, confrontate senza tener conto
    /// dell'orientamento (portrait/landscape indifferenti).
    public let screenPixelSizes: [PixelSize]

    public init(screenPixelSizes: [PixelSize]) {
        self.screenPixelSizes = screenPixelSizes
    }

    /// Vero se l'asset è un video le cui dimensioni coincidono (orientamento a
    /// parte) con una risoluzione schermo nota. Falso per qualunque foto.
    public func matches(_ asset: LibraryAsset) -> Bool {
        guard asset.kind == .video else { return false }
        return screenPixelSizes.contains { sameIgnoringOrientation($0, asset.pixelSize) }
    }

    /// Confronto di due dimensioni pixel indipendente dall'orientamento: uguali se
    /// i lati coincidono come insieme non ordinato (WxH == HxW).
    private func sameIgnoringOrientation(_ lhs: PixelSize, _ rhs: PixelSize) -> Bool {
        let lhsPair = (min(lhs.width, lhs.height), max(lhs.width, lhs.height))
        let rhsPair = (min(rhs.width, rhs.height), max(rhs.width, rhs.height))
        return lhsPair == rhsPair
    }
}

/// Categorie a eliminazione diretta di `large_old_media`: filtri puri sull'indice.
public enum ScreenshotCategory {
    /// Gli screenshot: esattamente gli asset marcati col sottotipo `.screenshot`
    /// dall'indice (T-011), nessun altro (AC-061-1). L'ordine d'ingresso è
    /// preservato (deterministico se l'input lo è).
    public static func screenshots(_ assets: [LibraryAsset]) -> [LibraryAsset] {
        assets.filter { $0.subtypes.contains(.screenshot) }
    }

    /// Le screen recording secondo l'euristica dichiarata: solo i video che la
    /// soddisfano (AC-061-2), mai una foto. Ordine d'ingresso preservato.
    public static func screenRecordings(
        _ assets: [LibraryAsset],
        heuristic: ScreenRecordingHeuristic
    ) -> [LibraryAsset] {
        assets.filter { heuristic.matches($0) }
    }
}

// MARK: - T-062 — Proposta di eliminazione in blocco

/// Proposta di eliminazione **in blocco** per le categorie a eliminazione diretta
/// (video grandi/vecchi, screenshot, screen recording). A differenza di duplicati
/// (T-032) e simili (T-043), qui non si "tiene la migliore": ogni asset selezionato
/// è rimovibile e `keep` è **sempre vuoto**. NESSUNA eliminazione qui — è solo dati
/// per la rete di sicurezza (`safety_net`), che passa sempre dall'anteprima
/// obbligatoria (T-050).
public struct BulkDeletionProposal: Equatable, Sendable {
    /// Gli asset selezionati dall'utente da rimuovere in blocco (mai eliminati qui).
    public let removable: [LibraryAsset]

    public init(removable: [LibraryAsset]) {
        self.removable = removable
    }

    /// Sempre vuoto: queste categorie non tengono nulla. Esplicito per il chiamante
    /// (AC-062-1), simmetrico al `keep` delle proposte keep-one/best-of.
    public var keep: [LibraryAsset] { [] }

    /// Id degli asset da rimuovere, nell'ordine di selezione: è l'input del gate di
    /// anteprima obbligatoria della safety_net.
    public var removableIds: [String] { removable.map(\.id) }
}

/// Composizione pura della proposta in blocco e suo ingresso nel gate di anteprima.
public enum BulkDeletionProposalComposer {
    /// Compone la proposta in blocco dagli asset selezionati: tutti rimovibili,
    /// nessun keep (AC-062-1). L'ordine di selezione è preservato.
    public static func compose(from selected: [LibraryAsset]) -> BulkDeletionProposal {
        BulkDeletionProposal(removable: selected)
    }

    /// Fa entrare la proposta nel `DeletionFlow` della safety_net (T-050): la porta
    /// in `previewing`, **non** in `confirmed`. La conferma resta impossibile finché
    /// l'anteprima non è mostrata *e* accettata (gate T-050): l'eliminazione in
    /// blocco non parte mai in autonomia (AC-062-2). Restituisce il flusso così
    /// avviato; una selezione vuota lo lascia in `idle` (nulla da eliminare).
    public static func presentInSafetyNet(_ proposal: BulkDeletionProposal) -> DeletionFlow {
        var flow = DeletionFlow()
        flow.presentPreview(for: proposal.removableIds)
        return flow
    }
}
