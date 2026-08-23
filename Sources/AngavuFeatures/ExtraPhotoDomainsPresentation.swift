import AngavuDomain
import Foundation

// Guscio UI — Contatti e calendari: presentazione PURA dei domini extra-foto.
//
// Mappa le proposte dei rilevatori extra-foto (contatti duplicati T-090, calendari
// -spam T-091) e l'esito dell'ultima azione (T-092) nelle decisioni osservabili
// della schermata: righe presentabili, stati vuoti onesti, nota della rete di
// sicurezza (azioni human-gated) ed esito dell'ultima operazione. Platform-puro
// (nessun import SwiftUI): è l'ORACOLO testabile della logica di presentazione, così
// la resa SwiftUI resta il solo strato «compilato-ma-non-testato» (L-COL-006).
//
// Invarianti di onestà riflesse qui: i calendari LOCALI non compaiono mai (la
// proposta li esclude già a monte, T-091); nessuna azione è descritta come
// automatica — richiede sempre la conferma dell'utente.

/// Modello di presentazione della schermata contatti/calendari.
public struct ExtraPhotoDomainsPresentation: Equatable, Sendable {

    /// Riga presentabile di un merge di contatti duplicati.
    public struct ContactRow: Equatable, Sendable {
        /// Id del contatto primario (quello conservato): chiave stabile per l'azione.
        public let primaryId: String
        /// Nome visualizzato del primario, con fallback se privo di nome.
        public let displayName: String
        /// Quanti duplicati verrebbero fusi nel primario (>= 1 per costruzione).
        public let duplicateCount: Int
        /// Dettaglio onesto ("2 duplicati da fondere").
        public let detail: String

        public init(primaryId: String, displayName: String, duplicateCount: Int, detail: String) {
            self.primaryId = primaryId
            self.displayName = displayName
            self.duplicateCount = duplicateCount
            self.detail = detail
        }
    }

    /// Riga presentabile di una sottoscrizione calendario rimovibile.
    public struct CalendarRow: Equatable, Sendable {
        public let id: String
        public let title: String

        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    public let contactsTitle: String
    public let contactsSubtitle: String
    public let contactRows: [ContactRow]
    public let contactsEmpty: Bool
    public let contactsEmptyMessage: String

    public let calendarsTitle: String
    public let calendarsSubtitle: String
    public let calendarRows: [CalendarRow]
    public let calendarsEmpty: Bool
    public let calendarsEmptyMessage: String

    /// Nota della rete di sicurezza: nulla parte da solo, i locali non si toccano.
    public let safetyNote: String
    /// Messaggio dell'esito dell'ultima azione, se una è stata eseguita.
    public let outcomeMessage: String?

    /// Deriva la presentazione dalle proposte correnti e dall'ultimo esito.
    /// Deterministica e totale: ogni ingresso ha una e una sola presentazione.
    public init(
        contactProposals: [ContactMergeProposal],
        calendarProposal: SpamCalendarRemovalProposal,
        lastOutcome: ExtraActionOutcome? = nil
    ) {
        let contacts = contactProposals.map(Self.contactRow(for:))
        let calendars = calendarProposal.removable.map(Self.calendarRow(for:))

        self.contactsTitle = "Contatti duplicati"
        self.contactsSubtitle = "Stesso nome e un recapito in comune. Fondere tiene un "
            + "contatto e vi unisce gli altri — solo su tua conferma."
        self.contactRows = contacts
        self.contactsEmpty = contacts.isEmpty
        self.contactsEmptyMessage = "Nessun contatto duplicato trovato."

        self.calendarsTitle = "Calendari sospetti"
        self.calendarsSubtitle = "Solo sottoscrizioni sospette (file .ics). I calendari "
            + "locali non compaiono e non si toccano mai."
        self.calendarRows = calendars
        self.calendarsEmpty = calendars.isEmpty
        self.calendarsEmptyMessage = "Nessuna sottoscrizione sospetta."

        self.safetyNote = "Niente parte da solo: fondere un contatto o rimuovere una "
            + "sottoscrizione richiede la tua conferma."
        self.outcomeMessage = lastOutcome.map(Self.message(for:))
    }

    /// Riga presentabile per una singola proposta di merge (usata anche dalla View
    /// per legare l'azione alla proposta senza accoppiamenti fragili per indice).
    public static func contactRow(for proposal: ContactMergeProposal) -> ContactRow {
        let count = proposal.duplicates.count
        return ContactRow(
            primaryId: proposal.primary.id,
            displayName: displayName(for: proposal.primary),
            duplicateCount: count,
            detail: count == 1 ? "1 duplicato da fondere" : "\(count) duplicati da fondere"
        )
    }

    /// Riga presentabile per una singola sottoscrizione calendario.
    public static func calendarRow(for calendar: CalendarEntry) -> CalendarRow {
        CalendarRow(id: calendar.id, title: calendar.title)
    }

    /// Nome visualizzato di un contatto: "Nome Cognome" potato; se vuoto, un
    /// fallback onesto (mai una stringa vuota nella UI).
    private static func displayName(for contact: ContactEntry) -> String {
        let joined = "\(contact.givenName) \(contact.familyName)"
        let trimmed = joined.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Contatto senza nome" : trimmed
    }

    /// Mappa l'esito dell'azione in un messaggio onesto per la UI.
    private static func message(for outcome: ExtraActionOutcome) -> String {
        switch outcome {
        case .applied: return "Fatto."
        case .cancelled: return "Annullato — nessuna modifica."
        case .failed(let reason): return "Non riuscito: \(reason)"
        }
    }
}
