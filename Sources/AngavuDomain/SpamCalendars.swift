import Foundation

// T-091 — Rilevamento calendari-spam (Domain PURO).
//
// I calendari-spam sono sottoscrizioni indesiderate iniettate via file `.ics`:
// compaiono come calendari di tipo "subscription", NON come i calendari locali
// dell'utente. Il Domain marca i soli sottoscritti sospetti e propone di rimuovere
// la sottoscrizione, MAI in autonomia. Nessun tipo di piattaforma qui (niente
// `EventKit`): l'enumerazione vive dietro il port `CalendarsProviding` del Data
// layer (altitudine `domain ↛ data`); il Domain riceve `CalendarEntry` puri.

/// Tipo del calendario, normalizzato dal Data layer (in EventKit: `EKCalendarType`).
/// La distinzione chiave per lo spam è `.subscription` — l'unico tipo che una
/// sottoscrizione `.ics` produce; i calendari dell'utente sono `.local`/`.calDAV`.
public enum CalendarKind: String, Equatable, Sendable, Codable {
    case local
    case subscription
    case calDAV
    case exchange
    case birthday
    case other
}

/// Calendario normalizzato e indipendente dalla piattaforma.
public struct CalendarEntry: Equatable, Sendable, Identifiable {
    /// Identificatore stabile (in EventKit: `EKCalendar.calendarIdentifier`).
    public let id: String
    public let title: String
    public let kind: CalendarKind

    public init(id: String, title: String, kind: CalendarKind) {
        self.id = id
        self.title = title
        self.kind = kind
    }
}

/// Euristica DICHIARATA di sospetto sui calendari sottoscritti. Un calendario NON
/// sottoscritto (locale, CalDAV, ecc.) non è MAI sospetto: mai si tocca un
/// calendario dell'utente (AC-091-1). Fra i sottoscritti:
///   • se sono forniti marcatori (`suspiciousMarkers`), è sospetto quello il cui
///     titolo contiene un marcatore (confronto case-insensitive);
///   • se la lista è vuota, ogni sottoscrizione è candidata alla revisione (una
///     sottoscrizione che l'utente non ricorda di aver voluto è già il segnale).
public struct SpamCalendarHeuristic: Sendable {
    public let suspiciousMarkers: [String]

    public init(suspiciousMarkers: [String] = []) {
        self.suspiciousMarkers = suspiciousMarkers
    }

    /// Vero se il calendario è una sottoscrizione giudicata sospetta.
    public func isSuspect(_ calendar: CalendarEntry) -> Bool {
        guard calendar.kind == .subscription else { return false }
        guard !suspiciousMarkers.isEmpty else { return true }
        let title = calendar.title.lowercased()
        return suspiciousMarkers.contains { !$0.isEmpty && title.contains($0.lowercased()) }
    }
}

/// Rilevamento puro dei calendari-spam.
public enum SpamCalendarDetection {
    /// I soli calendari sottoscritti giudicati sospetti dall'euristica, nell'ordine
    /// d'ingresso. I calendari locali dell'utente non compaiono mai (AC-091-1).
    public static func spamCalendars(
        _ calendars: [CalendarEntry],
        heuristic: SpamCalendarHeuristic = SpamCalendarHeuristic()
    ) -> [CalendarEntry] {
        calendars.filter(heuristic.isSuspect)
    }
}

/// Proposta di rimozione delle sottoscrizioni sospette. È SOLO dati — nessuna
/// sottoscrizione viene rimossa qui (AC-091-2); l'applicazione confermata è di T-092.
public struct SpamCalendarRemovalProposal: Equatable, Sendable {
    /// Calendari sottoscritti di cui si propone la rimozione (mai rimossi qui).
    public let removable: [CalendarEntry]

    public init(removable: [CalendarEntry]) {
        self.removable = removable
    }
}

/// Composizione pura della proposta di rimozione.
public enum SpamCalendarRemovalComposer {
    /// Proposta di rimozione a partire dai calendari-spam individuati.
    public static func propose(
        _ calendars: [CalendarEntry],
        heuristic: SpamCalendarHeuristic = SpamCalendarHeuristic()
    ) -> SpamCalendarRemovalProposal {
        SpamCalendarRemovalProposal(removable: SpamCalendarDetection.spamCalendars(calendars, heuristic: heuristic))
    }
}
