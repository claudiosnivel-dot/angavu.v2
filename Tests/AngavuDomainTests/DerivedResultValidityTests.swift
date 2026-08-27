import XCTest
@testable import AngavuDomain

// FSE-E1 — Oracolo della policy PURA di validità dei derivati (AC-FSE-E1-1/2/3).
//
// Un derivato è valido SSE la chiave (id + versione del contenuto) combacia. Mai un
// punteggio stantìo servito per un asset cambiato (onestà, 00-INDEX §6). Tutto puro:
// gira in CI su Linux, nessun device.
final class DerivedResultValidityTests: XCTestCase {

    private func key(_ id: String, _ version: String) -> DerivedKey {
        DerivedKey(id: id, contentVersion: version)
    }

    // MARK: AC-FSE-E1-1 — versione cambiata → stantìo → da ricalcolare

    func test_versionChanged_isStale_andRecomputed() {
        XCTAssertFalse(
            DerivedResultValidity.isValid(persisted: key("A", "1"), forCurrent: key("A", "2")),
            "stesso id ma versione diversa: mai valido"
        )

        let partition = DerivedResultValidity.partition(
            current: [key("A", "2")],
            persisted: [key("A", "1")]
        )
        XCTAssertEqual(partition.reusable, [])
        XCTAssertEqual(partition.toRecompute, [key("A", "2")], "A cambiato → da ricalcolare")
        XCTAssertEqual(partition.removed, [], "A è ancora presente: non rimosso, solo da ricalcolare")
    }

    func test_sameKey_isValid() {
        XCTAssertTrue(
            DerivedResultValidity.isValid(persisted: key("A", "1"), forCurrent: key("A", "1"))
        )
    }

    // MARK: AC-FSE-E1-2 — partizione riusabili / da-ricalcolare / rimossi

    func test_partition_reusableRecomputeRemoved() {
        // Persistiti A,B,C (v1); libreria corrente A(v1), B(v1), D(v1).
        let partition = DerivedResultValidity.partition(
            current: [key("A", "1"), key("B", "1"), key("D", "1")],
            persisted: [key("A", "1"), key("B", "1"), key("C", "1")]
        )
        XCTAssertEqual(partition.reusable, [key("A", "1"), key("B", "1")], "A,B invariati → riusabili")
        XCTAssertEqual(partition.toRecompute, [key("D", "1")], "D nuovo → da ricalcolare")
        XCTAssertEqual(partition.removed, [key("C", "1")], "C non più presente → scartato dalla cache")
    }

    func test_partition_preservesDeterministicOrder() {
        let partition = DerivedResultValidity.partition(
            current: [key("Z", "1"), key("A", "1")],       // ordine dei correnti
            persisted: [key("A", "1"), key("Z", "1")]
        )
        // Riusabili nell'ordine dei CORRENTI (Z prima di A), non dei persistiti.
        XCTAssertEqual(partition.reusable, [key("Z", "1"), key("A", "1")])
    }

    // MARK: AC-FSE-E1-3 — invalidazione totale → nessun valido

    func test_invalidateAll_nothingIsValid() {
        let partition = DerivedResultValidity.partition(
            current: [key("A", "1"), key("B", "1")],
            persisted: [key("A", "1"), key("B", "1")],
            invalidateAll: true
        )
        XCTAssertEqual(partition.reusable, [], "invalidazione totale: nessun derivato valido")
        XCTAssertEqual(partition.toRecompute, [key("A", "1"), key("B", "1")], "tutti da ricalcolare")
    }

    // MARK: Casi limite d'onestà

    func test_newAssetWithNoPersisted_isRecomputed() {
        let partition = DerivedResultValidity.partition(current: [key("N", "1")], persisted: [])
        XCTAssertEqual(partition.toRecompute, [key("N", "1")], "asset nuovo senza cache → calcolato, mai saltato")
        XCTAssertEqual(partition.reusable, [])
    }

    func test_emptyCurrent_allPersistedRemoved() {
        let partition = DerivedResultValidity.partition(
            current: [],
            persisted: [key("A", "1"), key("B", "1")]
        )
        XCTAssertEqual(
            partition.removed, [key("A", "1"), key("B", "1")],
            "libreria vuota → tutti i derivati scartati"
        )
        XCTAssertEqual(partition.reusable, [])
        XCTAssertEqual(partition.toRecompute, [])
    }
}
