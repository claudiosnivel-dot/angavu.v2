import Foundation

// T-102 — Report onesto: numeri veri + caveat, mai un totale gonfiato.
//
// Compone i pezzi già esistenti senza coniarne di nuovi (altitudine e riuso):
//   • `DashboardAggregate` (T-020) — byte per categoria, exact separato da estimated;
//   • `ReclaimableSpace` (T-021) — spazio libreria vs device ORA, caveat iCloud;
//   • `PhotoAccessDecision` (T-010) — conteggio parziale con accesso limited.
//
// Invarianti di onestà (manifesto + Guideline App Store 2.3.x):
//   • quando esiste una porzione stimata, NON si offre un unico totale "esatto"
//     (`singleExactTotalBytes == nil`): la stima resta marcata come stima (AC-102-1);
//   • il caveat iCloud è riportato quando presente (AC-102-1);
//   • con accesso limited i conteggi sono marcati parziali e si invita
//     all'accesso completo (AC-102-2).

/// Report onesto: aggregati veri con i loro caveat dichiarati. Solo dati; il
/// rendering grafico è out_of_scope (11-ui-shell.md).
public struct HonestReport: Equatable, Sendable {
    /// Byte per categoria (exact/estimated separati), in ordine stabile.
    public let categories: [CategoryBytes]
    /// Spazio recuperabile con la distinzione libreria vs device ORA.
    public let reclaimable: ReclaimableSpace
    /// Decisione d'accesso: porta il flag di conteggio parziale.
    public let access: PhotoAccessDecision

    public init(
        categories: [CategoryBytes],
        reclaimable: ReclaimableSpace,
        access: PhotoAccessDecision
    ) {
        self.categories = categories
        self.reclaimable = reclaimable
        self.access = access
    }

    /// Somma dei soli byte exact su tutte le categorie.
    public var totalExactBytes: Int64 {
        categories.reduce(Int64(0)) { $0 + $1.exactBytes }
    }

    /// Somma dei soli byte estimated su tutte le categorie. Resta marcata: stima.
    public var totalEstimatedBytes: Int64 {
        categories.reduce(Int64(0)) { $0 + $1.estimatedBytes }
    }

    /// Vero se una parte dei byte è stimata: il totale non è interamente esatto.
    public var hasEstimatedPortion: Bool { totalEstimatedBytes > 0 }

    /// Un unico numero presentabile come "esatto" SOLO quando nulla è stimato;
    /// altrimenti `nil` — la stima non si fonde mai in un totale spacciato per esatto.
    public var singleExactTotalBytes: Int64? {
        hasEstimatedPortion ? nil : totalExactBytes
    }

    /// Vero quando parte dello spazio libreria non si libera sul device ora
    /// (originali in iCloud): sempre dichiarato.
    public var iCloudCaveat: Bool { reclaimable.iCloudCaveat }

    /// Vero quando i conteggi sono parziali (accesso limited): non un totale.
    public var countsArePartial: Bool { access.isPartialCount }

    /// Vero quando ha senso invitare l'utente ad abilitare l'accesso completo.
    public var invitesFullAccess: Bool { access.access == .limited }
}

/// Composizione pura del report onesto dai pezzi di dominio esistenti.
public enum HonestReportComposer {
    /// Compone lo `HonestReport`. I caveat sono **derivati** dagli input, mai
    /// dichiarati a mano: stima marcata se qualche categoria ha byte estimated,
    /// caveat iCloud dallo spazio recuperabile, parzialità dall'accesso.
    public static func compose(
        aggregate: DashboardAggregate,
        reclaimable: ReclaimableSpace,
        access: PhotoAccess
    ) -> HonestReport {
        HonestReport(
            categories: aggregate.categories,
            reclaimable: reclaimable,
            access: PhotoAccessPolicy.decide(for: access)
        )
    }
}
