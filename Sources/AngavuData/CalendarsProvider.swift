import AngavuDomain

// T-091 / T-092 (Data) — Enumerazione e rimozione dei calendari via `EventKit`.
//
// Il port `CalendarsProviding` è dichiarato QUI nel Data layer (DoD T-091): fornisce
// al Domain i `CalendarEntry` puri su cui applicare l'euristica spam.
// `SystemCalendarSubscriptionRemover` implementa il port `CalendarSubscriptionRemoving`
// del Domain (T-092): rimuove la sottoscrizione reale solo dietro conferma.
//
// Privacy (00-INDEX §3): nessun dato calendario lascia il device (zero rete);
// l'accesso è coperto da `NSCalendarsFullAccessUsageDescription`. La rimozione è
// distruttiva, quindi mai automatica — solo dietro conferma esplicita (L-COL-005).

/// Port di enumerazione dei calendari. Implementazione reale sotto (guardata
/// `canImport(EventKit)`); sostituibile con un fake in test/anteprima.
public protocol CalendarsProviding {
    /// I calendari degli eventi, normalizzati a `CalendarEntry`.
    func fetchCalendars() throws -> [CalendarEntry]
}

#if canImport(EventKit)
import EventKit

/// Adapter reale: elenca i calendari degli eventi e ne normalizza il tipo.
public struct SystemCalendarsProvider: CalendarsProviding {
    private let store: EKEventStore

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    public func fetchCalendars() throws -> [CalendarEntry] {
        store.calendars(for: .event).map(Self.map)
    }

    /// Mappa un `EKCalendar` sul modello di dominio puro.
    static func map(_ calendar: EKCalendar) -> CalendarEntry {
        CalendarEntry(id: calendar.calendarIdentifier, title: calendar.title, kind: kind(for: calendar.type))
    }

    /// Normalizza `EKCalendarType` su `CalendarKind` (la sottoscrizione è il segnale spam).
    static func kind(for type: EKCalendarType) -> CalendarKind {
        switch type {
        case .local: return .local
        case .calDAV: return .calDAV
        case .exchange: return .exchange
        case .subscription: return .subscription
        case .birthday: return .birthday
        @unknown default: return .other
        }
    }
}

/// Adapter reale della rimozione (port `CalendarSubscriptionRemoving`). Rimuove il
/// calendario sottoscritto. Chiamato SOLO dopo il gate di conferma (T-092).
public struct SystemCalendarSubscriptionRemover: CalendarSubscriptionRemoving {
    private let store: EKEventStore

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    public func removeSubscription(_ calendar: CalendarEntry) async -> ExtraActionOutcome {
        guard let target = store.calendar(withIdentifier: calendar.id) else {
            return .failed(reason: "Calendario non trovato.")
        }
        do {
            try store.removeCalendar(target, commit: true)
            return .applied
        } catch {
            return .failed(reason: (error as NSError).localizedDescription)
        }
    }
}
#endif
