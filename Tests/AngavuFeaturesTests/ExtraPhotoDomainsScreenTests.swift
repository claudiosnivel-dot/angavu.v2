import XCTest
import AngavuDomain
import AngavuData
@testable import AngavuFeatures

// T-115 — AC-115-1 / AC-115-2. Domini extra-foto: proposte confermabili e
// applicazione dietro il gate confirmed (T-092), mai i calendari locali.

private struct StubContactsProvider: ContactsProviding {
    let contacts: [ContactEntry]
    func fetchContacts() throws -> [ContactEntry] { contacts }
}

private struct StubCalendarsProvider: CalendarsProviding {
    let calendars: [CalendarEntry]
    func fetchCalendars() throws -> [CalendarEntry] { calendars }
}

private final class FakeContactMerger: ContactMerging {
    private let result: ExtraActionOutcome
    private(set) var mergedProposals: [ContactMergeProposal] = []
    init(result: ExtraActionOutcome) { self.result = result }
    func merge(_ proposal: ContactMergeProposal) async -> ExtraActionOutcome {
        mergedProposals.append(proposal)
        return result
    }
}

private final class FakeCalendarRemover: CalendarSubscriptionRemoving {
    private let result: ExtraActionOutcome
    private(set) var removed: [CalendarEntry] = []
    init(result: ExtraActionOutcome) { self.result = result }
    func removeSubscription(_ calendar: CalendarEntry) async -> ExtraActionOutcome {
        removed.append(calendar)
        return result
    }
}

final class ExtraPhotoDomainsScreenTests: XCTestCase {

    // Due "Mario Rossi" con un telefono condiviso: duplicati per la detection.
    private func duplicateContacts() -> [ContactEntry] {
        [
            ContactEntry(
                id: "1", givenName: "Mario", familyName: "Rossi",
                phoneNumbers: ["+39 333 111"], emailAddresses: []
            ),
            ContactEntry(
                id: "2", givenName: "Mario", familyName: "Rossi",
                phoneNumbers: ["+39 333 111"], emailAddresses: []
            )
        ]
    }

    // AC-115-1: cluster di duplicati → conferma → l'azione passa dal gate confirmed
    // e produce il piano di merge (delega all'adapter).
    func test_contactMergeConfirmedPassesGateAndProducesPlan() async throws {
        let merger = FakeContactMerger(result: .applied)
        let vm = ContactsReviewViewModel(provider: StubContactsProvider(contacts: duplicateContacts()), merger: merger)

        try vm.load()
        XCTAssertEqual(vm.proposals.count, 1)
        let proposal = vm.proposals[0]
        XCTAssertEqual(proposal.primary.id, "1")
        XCTAssertEqual(proposal.duplicates.map(\.id), ["2"])

        let outcome = await vm.applyMerge(proposal, confirmed: true)
        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(merger.mergedProposals.count, 1, "con conferma l'adapter è delegato")
    }

    // Senza conferma: nessun merge, l'adapter non è mai invocato (gate T-092).
    func test_contactMergeWithoutConfirmationIsRefused() async throws {
        let merger = FakeContactMerger(result: .applied)
        let vm = ContactsReviewViewModel(provider: StubContactsProvider(contacts: duplicateContacts()), merger: merger)

        try vm.load()
        let outcome = await vm.applyMerge(vm.proposals[0], confirmed: false)

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertTrue(merger.mergedProposals.isEmpty)
    }

    // AC-115-2: sottoscrizioni sospette accanto a calendari locali → solo le
    // sottoscrizioni entrano nel piano, mai i locali; conferma → rimozione delegata.
    func test_calendarRemovalTargetsOnlySubscriptionsNeverLocal() async throws {
        let calendars = [
            CalendarEntry(id: "local", title: "I miei eventi", kind: .local),
            CalendarEntry(id: "spam", title: "Offerte imperdibili", kind: .subscription)
        ]
        let remover = FakeCalendarRemover(result: .applied)
        let vm = CalendarsReviewViewModel(provider: StubCalendarsProvider(calendars: calendars), remover: remover)

        try vm.load()

        XCTAssertEqual(vm.proposal.removable.map(\.id), ["spam"])
        XCTAssertFalse(vm.proposal.removable.contains { $0.kind == .local }, "un calendario locale non va mai rimosso")

        let outcome = await vm.applyRemoval(vm.proposal.removable[0], confirmed: true)
        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(remover.removed.map(\.id), ["spam"])
    }

    // Senza conferma: nessuna rimozione, l'adapter non è mai invocato (gate T-092).
    func test_calendarRemovalWithoutConfirmationIsRefused() async throws {
        let calendars = [CalendarEntry(id: "spam", title: "Spam", kind: .subscription)]
        let remover = FakeCalendarRemover(result: .applied)
        let vm = CalendarsReviewViewModel(provider: StubCalendarsProvider(calendars: calendars), remover: remover)

        try vm.load()
        let outcome = await vm.applyRemoval(vm.proposal.removable[0], confirmed: false)

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertTrue(remover.removed.isEmpty)
    }
}
