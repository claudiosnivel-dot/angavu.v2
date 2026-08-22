import XCTest
@testable import AngavuDomain

// T-092 — AC-092-1 / AC-092-2. Applicazione confermata (gate + esito onesto).
// I port dei side-effect sono sostituiti da fake che registrano le chiamate: si
// prova che senza conferma l'adapter non viene MAI invocato (nessun effetto).

/// Fake merger: registra i merge richiesti e restituisce un esito prefissato.
private final class FakeContactMerger: ContactMerging {
    private let result: ExtraActionOutcome
    private(set) var mergedProposals: [ContactMergeProposal] = []

    init(result: ExtraActionOutcome) { self.result = result }

    func merge(_ proposal: ContactMergeProposal) async -> ExtraActionOutcome {
        mergedProposals.append(proposal)
        return result
    }
}

/// Fake remover: registra le rimozioni richieste e restituisce un esito prefissato.
private final class FakeCalendarRemover: CalendarSubscriptionRemoving {
    private let result: ExtraActionOutcome
    private(set) var removed: [CalendarEntry] = []

    init(result: ExtraActionOutcome) { self.result = result }

    func removeSubscription(_ calendar: CalendarEntry) async -> ExtraActionOutcome {
        removed.append(calendar)
        return result
    }
}

final class ExtraDomainApplyTests: XCTestCase {

    private func sampleContactProposal() -> ContactMergeProposal {
        let primary = ContactEntry(id: "a", givenName: "Mario", familyName: "Rossi")
        let dup = ContactEntry(id: "b", givenName: "Mario", familyName: "Rossi")
        return ContactMergeProposal(primary: primary, duplicates: [dup])
    }

    // AC-092-1: senza conferma l'applicazione del merge è rifiutata — l'adapter non
    // viene invocato (nessun contatto fuso) e l'esito non è `.applied`.
    func test_contactMergeWithoutConfirmationIsRefused() async {
        let merger = FakeContactMerger(result: .applied)
        let confirmation = ExtraActionConfirmation() // .proposed, non confermata

        let outcome = await ExtraActionApplicator.applyContactMerge(
            sampleContactProposal(),
            confirmation: confirmation,
            via: merger
        )

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertTrue(merger.mergedProposals.isEmpty) // adapter mai chiamato
    }

    // Con conferma, il merge viene delegato e l'esito dell'adapter è propagato.
    func test_contactMergeWithConfirmationIsApplied() async {
        let merger = FakeContactMerger(result: .applied)
        var confirmation = ExtraActionConfirmation()
        XCTAssertTrue(confirmation.confirm())

        let outcome = await ExtraActionApplicator.applyContactMerge(
            sampleContactProposal(),
            confirmation: confirmation,
            via: merger
        )

        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(merger.mergedProposals.count, 1)
    }

    // AC-092-2: rimozione calendario confermata con adapter che riporta success →
    // la sottoscrizione è rimossa e l'esito è `.applied` (applicata).
    func test_calendarRemovalConfirmedWithSuccessIsApplied() async {
        let remover = FakeCalendarRemover(result: .applied)
        let spam = CalendarEntry(id: "s", title: "FREE prize", kind: .subscription)
        var confirmation = ExtraActionConfirmation()
        confirmation.confirm()

        let outcome = await ExtraActionApplicator.applyCalendarRemoval(
            spam,
            confirmation: confirmation,
            via: remover
        )

        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(remover.removed.map(\.id), ["s"])
    }

    // Rimozione confermata ma adapter che fallisce → esito `.failed` propagato
    // onestamente (mai un falso "applicata").
    func test_calendarRemovalConfirmedButAdapterFailsPropagatesFailure() async {
        let remover = FakeCalendarRemover(result: .failed(reason: "EventKit denied"))
        let spam = CalendarEntry(id: "s", title: "spam", kind: .subscription)
        var confirmation = ExtraActionConfirmation()
        confirmation.confirm()

        let outcome = await ExtraActionApplicator.applyCalendarRemoval(
            spam,
            confirmation: confirmation,
            via: remover
        )

        XCTAssertEqual(outcome, .failed(reason: "EventKit denied"))
        XCTAssertEqual(remover.removed.map(\.id), ["s"])
    }

    // Il gate di conferma: `confirm()` una sola volta ha effetto; resta confermato.
    func test_confirmationGateIsIdempotent() {
        var confirmation = ExtraActionConfirmation()
        XCTAssertFalse(confirmation.isConfirmed)
        XCTAssertTrue(confirmation.confirm())
        XCTAssertTrue(confirmation.isConfirmed)
        XCTAssertFalse(confirmation.confirm()) // già confermata: nessun nuovo effetto
        XCTAssertTrue(confirmation.isConfirmed)
    }
}
