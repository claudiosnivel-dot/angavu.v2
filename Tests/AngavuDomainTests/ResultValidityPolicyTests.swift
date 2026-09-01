import Foundation
import XCTest
@testable import AngavuDomain

// FSE-K2 — Oracolo della `ResultValidityPolicy` pura (AC-FSE-K2-1/2/3/4).
//
// Il bug ricorrente («le categorie pesanti riscansionano all'ingresso») si chiude solo
// se, al rilancio, si sa COSA è cambiato senza riscansionare: qui si prova, su logica
// PURA (nessun PhotoKit), che (1) a token uguale o delta vuoto TUTTE le categorie sono
// servite; (2) un delta che tocca id di una sola categoria ricompone SOLO quella (mai
// una ricomposizione globale); (3) token scaduto o assente → scansione completa
// DICHIARATA, mai un risultato stantìo servito in silenzio; (4) un id in `deleted` E
// in `inserted` è delete+insert (potato, ricomposto), mai un match per nome.

private let tokenA = Data("token-A".utf8)
private let tokenB = Data("token-B".utf8)

private func saved(_ kind: String, _ ids: Set<String>, token: Data? = tokenA) -> SavedCategoryResult {
    SavedCategoryResult(kind: kind, ids: ids, token: token)
}

final class ResultValidityPolicyTests: XCTestCase {

    private let dup = saved("exactDuplicates", ["D1", "D2"])
    private let sim = saved("similarPhotos", ["S1", "S2", "S3"])
    private let blur = saved("blurryPhotos", ["B1"])

    // AC-FSE-K2-1 — token uguale: tutte `.serve`, qualunque sia l'esito (non consultato).
    func test_sameToken_servesEveryCategory() {
        let decisions = ResultValidityPolicy.decide(
            saved: [dup, sim, blur], current: tokenA, outcome: .unavailable
        )
        XCTAssertEqual(decisions, [
            "exactDuplicates": .serve, "similarPhotos": .serve, "blurryPhotos": .serve
        ])
    }

    // AC-FSE-K2-1 — token diverso ma delta VUOTO da T: tutte `.serve` (nessun rilevatore).
    func test_emptyDelta_servesEveryCategory() {
        let decisions = ResultValidityPolicy.decide(
            saved: [dup, sim, blur], current: tokenB, outcome: .delta(LibraryChangeDelta())
        )
        XCTAssertEqual(decisions.values.filter { $0 == .serve }.count, 3)
    }

    // AC-FSE-K2-2 — delta che tocca id presenti SOLO in una categoria: quella →
    // `.recompose` con gli id toccati; le altre → `.serve` (mai globale).
    func test_deltaTouchingOneCategory_recomposesOnlyThat() {
        let delta = LibraryChangeDelta(updated: ["S2"], deleted: ["S3", "UNRELATED"])
        let decisions = ResultValidityPolicy.decide(
            saved: [dup, sim, blur], current: tokenB, outcome: .delta(delta)
        )
        XCTAssertEqual(decisions["similarPhotos"], .recompose(touchedIds: ["S2", "S3"]))
        XCTAssertEqual(decisions["exactDuplicates"], .serve)
        XCTAssertEqual(decisions["blurryPhotos"], .serve)
    }

    // AC-FSE-K2-2 — un delta di soli id estranei (nuove foto non in nessuna categoria)
    // è disgiunto da tutte: tutte `.serve`.
    func test_deltaDisjointFromEveryCategory_servesAll() {
        let delta = LibraryChangeDelta(inserted: ["NEW1", "NEW2"])
        let decisions = ResultValidityPolicy.decide(saved: [dup, sim], current: tokenB, outcome: .delta(delta))
        XCTAssertEqual(decisions, ["exactDuplicates": .serve, "similarPhotos": .serve])
    }

    // AC-FSE-K2-3 — token scaduto: `.fullRescan` DICHIARATO per ogni categoria.
    func test_expiredToken_declaresFullRescan() {
        let decisions = ResultValidityPolicy.decide(saved: [dup, sim], current: tokenB, outcome: .expired)
        XCTAssertEqual(decisions, ["exactDuplicates": .fullRescan, "similarPhotos": .fullRescan])
    }

    // AC-FSE-K2-3 — dettagli non disponibili (nessuna prova): `.fullRescan`, mai un
    // delta vuoto fabbricato che farebbe servire risultati stantìi.
    func test_unavailableDetails_declaresFullRescan() {
        XCTAssertEqual(ResultValidityPolicy.decide(dup, current: tokenB, outcome: .unavailable), .fullRescan)
    }

    // AC-FSE-K2-3 — token salvato ASSENTE (risultato senza prova di validità) o token
    // corrente assente (tracker null-object): `.fullRescan`, anche a delta vuoto.
    func test_missingTokens_declareFullRescan() {
        let untracked = saved("exactDuplicates", ["D1"], token: nil)
        XCTAssertEqual(
            ResultValidityPolicy.decide(untracked, current: tokenA, outcome: .delta(LibraryChangeDelta())),
            .fullRescan
        )
        XCTAssertEqual(
            ResultValidityPolicy.decide(dup, current: nil, outcome: .delta(LibraryChangeDelta())),
            .fullRescan
        )
    }

    // AC-FSE-K2-4 — lo stesso localIdentifier in `deleted` E `inserted` (id cambiato):
    // delete+insert. La categoria che lo conteneva è `.recompose` con quell'id toccato;
    // l'applicazione del delta POTA l'id vecchio (il nuovo entra solo dal rilevatore),
    // nessun match per nome che lo tenga.
    func test_deletedAndInsertedSameId_isDeletePlusInsert() {
        let delta = LibraryChangeDelta(inserted: ["D2"], deleted: ["D2"])
        let decision = ResultValidityPolicy.decide(dup, current: tokenB, outcome: .delta(delta))
        XCTAssertEqual(decision, .recompose(touchedIds: ["D2"]))
        XCTAssertEqual(ResultValidityPolicy.pruned(ids: dup.ids, applying: delta), ["D1"],
                       "l'id vecchio è potato anche se ricompare in inserted")
    }

    // Il delta espone `isEmpty` e l'unione degli id toccati in modo coerente.
    func test_delta_isEmptyAndTouchedIds() {
        XCTAssertTrue(LibraryChangeDelta().isEmpty)
        let delta = LibraryChangeDelta(inserted: ["a1"], updated: ["b1"], deleted: ["c1"])
        XCTAssertFalse(delta.isEmpty)
        XCTAssertEqual(delta.touchedIds, ["a1", "b1", "c1"])
    }

    // Il null-object non fabbrica mai un delta: nessun token, esito `.unavailable`.
    func test_nullTracker_reportsUnavailableNeverAnEmptyDelta() {
        let tracker = NoLibraryChangeTracker()
        XCTAssertNil(tracker.currentToken())
        XCTAssertEqual(tracker.changes(since: tokenA), .unavailable)
    }
}
