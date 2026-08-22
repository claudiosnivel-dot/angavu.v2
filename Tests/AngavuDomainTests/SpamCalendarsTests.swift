import XCTest
@testable import AngavuDomain

// T-091 — AC-091-1 / AC-091-2. Calendari-spam e proposta di rimozione (solo dati).
// Tutto Domain puro: gira senza device né framework EventKit.

final class SpamCalendarsTests: XCTestCase {

    private func calendar(_ id: String, _ title: String, _ kind: CalendarKind) -> CalendarEntry {
        CalendarEntry(id: id, title: title, kind: kind)
    }

    // AC-091-1: fra calendari locali e sottoscritti sospetti, la lista spam contiene
    // SOLO i sottoscritti sospetti, mai i calendari locali dell'utente.
    func test_onlySuspiciousSubscribedCalendarsFlaggedNeverLocal() {
        let local = calendar("l", "Personale", .local)
        let calDAV = calendar("d", "Lavoro (iCloud)", .calDAV)
        let spam = calendar("s", "Win a FREE prize", .subscription)
        let heuristic = SpamCalendarHeuristic(suspiciousMarkers: ["free", "prize", "promo"])

        let flagged = SpamCalendarDetection.spamCalendars([local, calDAV, spam], heuristic: heuristic)

        XCTAssertEqual(flagged.map(\.id), ["s"])
        XCTAssertFalse(flagged.contains { $0.kind == .local })
    }

    // Un calendario locale che (per assurdo) contiene un marcatore nel titolo non è
    // mai spam: il tipo `.subscription` è condizione necessaria.
    func test_localCalendarWithMarkerWordIsNeverSpam() {
        let localWithWord = calendar("l", "Offerte del supermercato", .local)
        let heuristic = SpamCalendarHeuristic(suspiciousMarkers: ["offerte"])

        let flagged = SpamCalendarDetection.spamCalendars([localWithWord], heuristic: heuristic)

        XCTAssertTrue(flagged.isEmpty)
    }

    // Senza marcatori, ogni sottoscrizione è candidata alla revisione (segnale
    // conservativo dichiarato); i non sottoscritti restano comunque fuori.
    func test_withoutMarkersAllSubscriptionsAreCandidates() {
        let subA = calendar("a", "Feste italiane", .subscription)
        let subB = calendar("b", "Chissà cosa", .subscription)
        let local = calendar("l", "Personale", .local)

        let flagged = SpamCalendarDetection.spamCalendars([subA, subB, local])

        XCTAssertEqual(Set(flagged.map(\.id)), ["a", "b"])
    }

    // AC-091-2: la proposta di rimozione è SOLO dati — elenca i rimovibili, nessuna
    // sottoscrizione rimossa qui.
    func test_removalProposalIsDataOnly() {
        let spam = calendar("s", "FREE crypto signals", .subscription)
        let local = calendar("l", "Personale", .local)
        let heuristic = SpamCalendarHeuristic(suspiciousMarkers: ["free"])

        let proposal = SpamCalendarRemovalComposer.propose([spam, local], heuristic: heuristic)

        XCTAssertEqual(proposal.removable.map(\.id), ["s"])
    }
}
