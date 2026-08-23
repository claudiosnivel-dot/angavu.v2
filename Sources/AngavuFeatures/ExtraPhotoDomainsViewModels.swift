import AngavuDomain
import AngavuData
import Observation

// T-115 (wiring) — Domini extra-foto: contatti duplicati e calendari-spam.
//
// Presenta le proposte dei rilevatori extra-foto come righe confermabili e
// instrada l'applicazione dal gate `proposed → confirmed` (T-092): senza conferma
// nessun effetto (.cancelled), con conferma delega ai port async e propaga
// l'esito reale. Invariante di prodotto: i calendari LOCALI non sono mai toccati
// (la proposta li esclude già a monte). Nessuna logica di dominio nuova.

// MARK: - Contatti duplicati

/// Riga presentabile di un merge di contatti: il primario più gli id dei duplicati.
public struct ContactMergeRow: Equatable, Sendable {
    public let primaryId: String
    public let duplicateIds: [String]

    public init(primaryId: String, duplicateIds: [String]) {
        self.primaryId = primaryId
        self.duplicateIds = duplicateIds
    }
}

@Observable
public final class ContactsReviewViewModel {
    public private(set) var proposals: [ContactMergeProposal] = []

    private let provider: any ContactsProviding
    private let merger: any ContactMerging

    public init(provider: any ContactsProviding, merger: any ContactMerging) {
        self.provider = provider
        self.merger = merger
    }

    /// Carica i contatti e ne deriva le proposte di merge (cluster di duplicati).
    /// Può lanciare: l'accesso alla rubrica non va mascherato con un verde finto.
    public func load() throws {
        let contacts = try provider.fetchContacts()
        proposals = ContactMergeProposalComposer.proposals(
            for: DuplicateContactDetection.clusters(contacts)
        )
    }

    /// Righe presentabili (primario + duplicati) per le proposte correnti.
    public var rows: [ContactMergeRow] {
        proposals.map { ContactMergeRow(primaryId: $0.primary.id, duplicateIds: $0.duplicates.map(\.id)) }
    }

    /// Applica il merge SOLO dopo conferma esplicita (gate T-092). Senza conferma
    /// l'adapter non è mai invocato (esito `.cancelled`); con conferma delega e
    /// propaga l'esito reale (`applied | cancelled | failed`).
    @discardableResult
    public func applyMerge(_ proposal: ContactMergeProposal, confirmed: Bool) async -> ExtraActionOutcome {
        var confirmation = ExtraActionConfirmation()
        if confirmed { confirmation.confirm() }
        return await ExtraActionApplicator.applyContactMerge(proposal, confirmation: confirmation, via: merger)
    }
}

// MARK: - Calendari-spam

/// Riga presentabile di una rimozione di calendario sottoscritto.
public struct CalendarRemovalRow: Equatable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

@Observable
public final class CalendarsReviewViewModel {
    public private(set) var proposal: SpamCalendarRemovalProposal = SpamCalendarRemovalProposal(removable: [])

    private let provider: any CalendarsProviding
    private let remover: any CalendarSubscriptionRemoving
    private let heuristic: SpamCalendarHeuristic

    public init(
        provider: any CalendarsProviding,
        remover: any CalendarSubscriptionRemoving,
        heuristic: SpamCalendarHeuristic = SpamCalendarHeuristic()
    ) {
        self.provider = provider
        self.remover = remover
        self.heuristic = heuristic
    }

    /// Carica i calendari e ne deriva la proposta di rimozione: SOLO le
    /// sottoscrizioni sospette, mai i calendari locali (AC-115-2). Può lanciare.
    public func load() throws {
        let calendars = try provider.fetchCalendars()
        proposal = SpamCalendarRemovalComposer.propose(calendars, heuristic: heuristic)
    }

    /// Righe presentabili: le sole sottoscrizioni rimovibili.
    public var rows: [CalendarRemovalRow] {
        proposal.removable.map { CalendarRemovalRow(id: $0.id, title: $0.title) }
    }

    /// Rimuove una sottoscrizione SOLO dopo conferma esplicita (gate T-092). Senza
    /// conferma nessun effetto (`.cancelled`); con conferma delega e propaga l'esito.
    @discardableResult
    public func applyRemoval(_ calendar: CalendarEntry, confirmed: Bool) async -> ExtraActionOutcome {
        var confirmation = ExtraActionConfirmation()
        if confirmed { confirmation.confirm() }
        return await ExtraActionApplicator.applyCalendarRemoval(calendar, confirmation: confirmation, via: remover)
    }
}
