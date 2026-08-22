import XCTest
@testable import AngavuDomain

// T-090 — AC-090-1 / AC-090-2. Duplicati contatti e proposta di merge (solo dati).
// Tutto Domain puro: gira senza device né framework Contacts.

final class DuplicateContactsTests: XCTestCase {

    private func contact(
        _ id: String,
        given: String,
        family: String,
        phones: [String] = [],
        emails: [String] = []
    ) -> ContactEntry {
        ContactEntry(id: id, givenName: given, familyName: family, phoneNumbers: phones, emailAddresses: emails)
    }

    // AC-090-1: due voci con stesso nome E stesso numero formano un cluster; una
    // terza voce distinta (altro nome/numero) resta fuori.
    func test_sameNameAndNumberClusterThirdDistinctExcluded() {
        let dupA = contact("a", given: "Mario", family: "Rossi", phones: ["+39 333 1234567"])
        let dupB = contact("b", given: "mario", family: "rossi", phones: ["3331234567"])
        let distinct = contact("c", given: "Luca", family: "Bianchi", phones: ["3339999999"])

        let clusters = DuplicateContactDetection.clusters([dupA, dupB, distinct])

        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(Set(clusters.first?.contacts.map(\.id) ?? []), ["a", "b"])
        XCTAssertFalse(clusters.first?.contacts.contains { $0.id == "c" } ?? true)
    }

    // Stesso nome ma NESSUN punto di contatto condiviso → non sono duplicati:
    // persone omonime distinte non vanno mai fuse (nessun falso "via libera").
    func test_sameNameDifferentContactPointsAreNotDuplicates() {
        let annaA = contact("a", given: "Anna", family: "Verdi", phones: ["3331111111"])
        let annaB = contact("b", given: "Anna", family: "Verdi", phones: ["3332222222"])

        let clusters = DuplicateContactDetection.clusters([annaA, annaB])

        XCTAssertTrue(clusters.isEmpty)
    }

    // Email condivisa (senza numero condiviso) basta, insieme al nome, a duplicare.
    func test_sharedEmailWithSameNameClusters() {
        let saraA = contact("a", given: "Sara", family: "Neri", emails: ["Sara.Neri@Example.com"])
        let saraB = contact("b", given: "Sara", family: "Neri", emails: ["sara.neri@example.com"])

        let clusters = DuplicateContactDetection.clusters([saraA, saraB])

        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(Set(clusters.first?.contacts.map(\.id) ?? []), ["a", "b"])
    }

    // AC-090-2: la proposta di merge è SOLO dati — primario deterministico (id
    // minore) e duplicati marcati, nessun contatto fuso.
    func test_mergeProposalIsDataWithDeterministicPrimary() {
        let primary = contact("a", given: "Mario", family: "Rossi", phones: ["3331234567"])
        let duplicate = contact("b", given: "Mario", family: "Rossi", phones: ["3331234567"])
        let clusters = DuplicateContactDetection.clusters([duplicate, primary]) // ordine invertito

        guard let proposal = ContactMergeProposalComposer.proposals(for: clusters).first else {
            return XCTFail("attesa una proposta di merge")
        }
        XCTAssertEqual(proposal.primary.id, "a") // id minore, stabile
        XCTAssertEqual(proposal.duplicates.map(\.id), ["b"])
    }
}
