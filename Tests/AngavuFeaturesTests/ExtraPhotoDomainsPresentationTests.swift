import XCTest
import AngavuDomain
@testable import AngavuFeatures

// Guscio UI — schermata contatti/calendari: l'ORACOLO di presentazione è puro e
// testato qui (la resa SwiftUI resta compilata-ma-non-testata, L-COL-006).
// Verifica: righe corrette, stati vuoti onesti, i calendari locali non compaiono
// mai, e i messaggi d'esito.

final class ExtraPhotoDomainsPresentationTests: XCTestCase {

    private func contact(id: String, given: String, family: String) -> ContactEntry {
        ContactEntry(id: id, givenName: given, familyName: family,
                     phoneNumbers: ["+39 333 1234567"], emailAddresses: [])
    }

    // MARK: Contatti

    func test_emptyContacts_showsHonestEmptyState() {
        let pres = ExtraPhotoDomainsPresentation(
            contactProposals: [],
            calendarProposal: SpamCalendarRemovalProposal(removable: [])
        )
        XCTAssertTrue(pres.contactsEmpty)
        XCTAssertTrue(pres.contactRows.isEmpty)
        XCTAssertFalse(pres.contactsEmptyMessage.isEmpty)
    }

    func test_contactRow_mapsNameCountAndDetail() {
        let primary = contact(id: "a", given: "Mario", family: "Rossi")
        let dup = contact(id: "b", given: "Mario", family: "Rossi")
        let proposal = ContactMergeProposal(primary: primary, duplicates: [dup])

        let pres = ExtraPhotoDomainsPresentation(
            contactProposals: [proposal],
            calendarProposal: SpamCalendarRemovalProposal(removable: [])
        )

        XCTAssertFalse(pres.contactsEmpty)
        XCTAssertEqual(pres.contactRows.count, 1)
        let row = pres.contactRows[0]
        XCTAssertEqual(row.primaryId, "a")
        XCTAssertEqual(row.displayName, "Mario Rossi")
        XCTAssertEqual(row.duplicateCount, 1)
        XCTAssertEqual(row.detail, "1 duplicato da fondere")
    }

    func test_contactRow_pluralDetailForManyDuplicates() {
        let primary = contact(id: "a", given: "Ada", family: "Bianchi")
        let proposal = ContactMergeProposal(
            primary: primary,
            duplicates: [contact(id: "b", given: "Ada", family: "Bianchi"),
                         contact(id: "c", given: "Ada", family: "Bianchi")]
        )
        let row = ExtraPhotoDomainsPresentation.contactRow(for: proposal)
        XCTAssertEqual(row.duplicateCount, 2)
        XCTAssertEqual(row.detail, "2 duplicati da fondere")
    }

    func test_namelessContact_getsHonestFallbackName() {
        let primary = ContactEntry(id: "a", givenName: " ", familyName: "")
        let proposal = ContactMergeProposal(
            primary: primary,
            duplicates: [ContactEntry(id: "b", givenName: "", familyName: "")]
        )
        let row = ExtraPhotoDomainsPresentation.contactRow(for: proposal)
        XCTAssertEqual(row.displayName, "Contatto senza nome")
    }

    // MARK: Calendari — i locali non compaiono mai

    func test_calendars_onlySuspiciousSubscriptionsAppear_neverLocals() {
        let calendars = [
            CalendarEntry(id: "local", title: "Il mio calendario", kind: .local),
            CalendarEntry(id: "sub", title: "Offerte lampo", kind: .subscription),
            CalendarEntry(id: "work", title: "Lavoro", kind: .calDAV)
        ]
        let proposal = SpamCalendarRemovalComposer.propose(calendars)

        let pres = ExtraPhotoDomainsPresentation(
            contactProposals: [],
            calendarProposal: proposal
        )

        XCTAssertEqual(pres.calendarRows.count, 1)
        XCTAssertEqual(pres.calendarRows[0].id, "sub")
        XCTAssertEqual(pres.calendarRows[0].title, "Offerte lampo")
        XCTAssertFalse(pres.calendarRows.contains { $0.title == "Il mio calendario" })
    }

    func test_emptyCalendars_showsHonestEmptyState() {
        let pres = ExtraPhotoDomainsPresentation(
            contactProposals: [],
            calendarProposal: SpamCalendarRemovalProposal(removable: [])
        )
        XCTAssertTrue(pres.calendarsEmpty)
        XCTAssertTrue(pres.calendarRows.isEmpty)
        XCTAssertFalse(pres.calendarsEmptyMessage.isEmpty)
    }

    // MARK: Esiti e nota di sicurezza

    func test_outcomeMessage_nilWhenNoAction() {
        let pres = ExtraPhotoDomainsPresentation(
            contactProposals: [],
            calendarProposal: SpamCalendarRemovalProposal(removable: [])
        )
        XCTAssertNil(pres.outcomeMessage)
    }

    func test_outcomeMessages_mapEachOutcome() {
        let empty = SpamCalendarRemovalProposal(removable: [])
        let applied = ExtraPhotoDomainsPresentation(
            contactProposals: [], calendarProposal: empty, lastOutcome: .applied
        )
        let cancelled = ExtraPhotoDomainsPresentation(
            contactProposals: [], calendarProposal: empty, lastOutcome: .cancelled
        )
        let failed = ExtraPhotoDomainsPresentation(
            contactProposals: [], calendarProposal: empty, lastOutcome: .failed(reason: "boom")
        )
        XCTAssertEqual(applied.outcomeMessage, "Fatto.")
        XCTAssertEqual(cancelled.outcomeMessage, "Annullato — nessuna modifica.")
        XCTAssertEqual(failed.outcomeMessage, "Non riuscito: boom")
    }

    func test_safetyNote_isPresentAndMentionsConfirmation() {
        let pres = ExtraPhotoDomainsPresentation(
            contactProposals: [],
            calendarProposal: SpamCalendarRemovalProposal(removable: [])
        )
        XCTAssertTrue(pres.safetyNote.lowercased().contains("conferma"))
    }
}
