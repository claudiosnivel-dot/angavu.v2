import AngavuDomain
import Foundation

// T-101 — Navigazione dell'app che rispetta il gate di anteprima (T-050).
//
// La rete di sicurezza vale in OGNI sezione: nessun percorso di navigazione
// raggiunge l'eliminazione saltando l'anteprima. Qui non si reinventa il gate —
// c'è UN solo ingresso all'eliminazione, `DeletionEntryPoint`, che pilota il
// `DeletionFlow` condiviso (Domain, T-050). Le sezioni che eliminano asset
// passano tutte da lì; non esiste una scorciatoia per-sezione.
//
// Modellato nel Features layer (vede il Domain), platform-puro e testabile senza
// device: l'oracolo (AC-101-1/2) misura la sequenza di stati attraversata.

/// Le sezioni dell'app.
public enum AppSection: String, Sendable, Equatable, CaseIterable {
    case dashboard
    case exactDuplicates
    case similarPhotos
    case largeOldMedia
    case blurryPhotos
    case videoCompression
    case extraDomains

    /// Vero se la sezione può eliminare asset FOTO/VIDEO passando dalla rete di
    /// sicurezza (T-050). La dashboard è di sola lettura; `extraDomains` agisce
    /// su contatti/calendario dietro il proprio gate di conferma (T-092), non
    /// dalla rete di sicurezza foto.
    public var deletesAssetsViaSafetyNet: Bool {
        switch self {
        case .exactDuplicates, .similarPhotos, .largeOldMedia, .blurryPhotos, .videoCompression:
            return true
        case .dashboard, .extraDomains:
            return false
        }
    }

    /// Le sezioni che portano a un'eliminazione di asset (per l'enumerazione AC-101-2).
    public static var assetDeletingSections: [AppSection] {
        allCases.filter(\.deletesAssetsViaSafetyNet)
    }
}

/// Traccia della sequenza di stati che un percorso di eliminazione attraversa.
/// È l'oracolo osservabile del gate: prova che `previewing` precede `confirmed`.
public struct DeletionRouteTrace: Equatable, Sendable {
    /// Gli stati del `DeletionFlow`, in ordine, a partire da `idle`.
    public let states: [DeletionFlow.State]

    public init(states: [DeletionFlow.State]) {
        self.states = states
    }

    /// Vero se il percorso ha attraversato uno stato `previewing`.
    public var passedThroughPreviewing: Bool {
        states.contains { if case .previewing = $0 { return true } else { return false } }
    }

    /// Vero se ha raggiunto `confirmed`.
    public var reachedConfirmed: Bool {
        states.contains { if case .confirmed = $0 { return true } else { return false } }
    }

    /// Vero se ha raggiunto `deleting`.
    public var reachedDeleting: Bool {
        states.contains { if case .deleting = $0 { return true } else { return false } }
    }

    /// Vero se il primo `previewing` precede il primo `confirmed` — il gate è
    /// rispettato (non si conferma senza prima aver previewato).
    public var previewingPrecededConfirmed: Bool {
        guard let confirmedAt = indexOfFirstConfirmed else { return passedThroughPreviewing }
        guard let previewingAt = indexOfFirstPreviewing else { return false }
        return previewingAt < confirmedAt
    }

    private var indexOfFirstPreviewing: Int? {
        states.firstIndex { if case .previewing = $0 { return true } else { return false } }
    }

    private var indexOfFirstConfirmed: Int? {
        states.firstIndex { if case .confirmed = $0 { return true } else { return false } }
    }
}

/// L'unico ingresso all'eliminazione: pilota il `DeletionFlow` condiviso.
/// Qualsiasi sezione che elimina asset passa da qui — nessun bypass del gate.
public enum DeletionEntryPoint {
    /// Percorre il flusso completo fino all'eliminazione per gli asset selezionati,
    /// registrando ogni stato legale raggiunto (a partire da `idle`). La conferma
    /// è possibile solo dopo un'anteprima mostrata E accettata (gate T-050): la
    /// traccia lo riflette per costruzione, non per convenzione.
    public static func route(selecting ids: [String]) -> DeletionRouteTrace {
        var flow = DeletionFlow()
        var states: [DeletionFlow.State] = [flow.state]

        guard flow.presentPreview(for: ids) else {
            return DeletionRouteTrace(states: states)
        }
        states.append(flow.state)

        guard flow.acceptPreview() else {
            return DeletionRouteTrace(states: states)
        }
        states.append(flow.state)

        guard flow.confirm() else {
            return DeletionRouteTrace(states: states)
        }
        states.append(flow.state)

        if flow.beginDeleting() {
            states.append(flow.state)
        }
        return DeletionRouteTrace(states: states)
    }
}

/// Navigatore delle sezioni: mappa una sezione al suo percorso di eliminazione,
/// se ne ha uno. Le sezioni di sola lettura restituiscono `nil`.
public enum SectionNavigator {
    /// Il percorso di eliminazione di una sezione, o `nil` se la sezione non
    /// elimina asset dalla rete di sicurezza. Tutte le sezioni che eliminano
    /// usano lo stesso `DeletionEntryPoint`: nessun percorso salta l'anteprima.
    public static func deletionRoute(for section: AppSection, selecting ids: [String]) -> DeletionRouteTrace? {
        guard section.deletesAssetsViaSafetyNet else { return nil }
        return DeletionEntryPoint.route(selecting: ids)
    }
}
