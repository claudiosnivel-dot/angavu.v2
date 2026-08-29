import XCTest
import AngavuDomain

// FSE-H2 — AC-FSE-H2-2. Raggruppamento burst nativo (Tier 0): gli asset con lo stesso
// `burstIdentifier` finiscono nello stesso cluster, SENZA alcun calcolo Vision/dHash; id
// unici o `nil` restano singleton. Il keep segue il pick nativo (`.userPick`/`.autoPick`).
// Logica PURA, id finti — testabile su Linux.

private func asset(_ id: String) -> LibraryAsset {
    LibraryAsset(id: id, kind: .photo, pixelSize: PixelSize(width: 10, height: 10), creationDate: nil, subtypes: [])
}

private func burst(_ id: String, _ burstIdentifier: String?, _ selection: BurstSelection = .none) -> BurstAsset {
    BurstAsset(asset: asset(id), burstIdentifier: burstIdentifier, selection: selection)
}

private func ids(_ clusters: [BurstCluster]) -> [[String]] {
    clusters.map { $0.members.map(\.asset.id) }
}

final class BurstGroupingTests: XCTestCase {

    // AC-FSE-H2-2: stesso burstIdentifier ⇒ stesso cluster; unico o nil ⇒ singleton.
    func test_sameBurstIdentifier_groupsTogether_uniqueAndNilAreSingletons() {
        let groups = BurstGrouping.groups(of: [
            burst("B1", "raffica-1"),
            burst("B2", "raffica-1"),
            burst("S1", "raffica-2"),   // identificatore unico → singleton
            burst("N1", nil)            // nessuna raffica → singleton
        ])

        XCTAssertEqual(ids(groups), [["B1", "B2"], ["S1"], ["N1"]])
    }

    // Ordine deterministico: cluster per prima apparizione, indipendente dall'ordine con
    // cui i membri di una raffica si presentano rispetto ad altri asset intercalati.
    func test_order_isByFirstAppearance_membersInInputOrder() {
        let groups = BurstGrouping.groups(of: [
            burst("A", "a"),
            burst("B", "b"),
            burst("A2", "a"),   // torna alla raffica "a"
            burst("C", nil),
            burst("B2", "b")
        ])
        // "a" appare per prima (indice 0), "b" per seconda (indice 1), poi C (indice 3).
        XCTAssertEqual(ids(groups), [["A", "A2"], ["B", "B2"], ["C"]])
    }

    // Il keep segue il pick NATIVO: userPick batte autoPick, che batte il primo d'ingresso.
    func test_keep_followsUserPickThenAutoPickThenFirst() {
        let userWins = BurstCluster(members: [
            burst("X1", "r", .autoPick),
            burst("X2", "r", .userPick)
        ])
        XCTAssertEqual(userWins.keep?.asset.id, "X2", "userPick batte autoPick")
        XCTAssertEqual(userWins.removable.map(\.asset.id), ["X1"])

        let autoWins = BurstCluster(members: [
            burst("Y1", "r", .none),
            burst("Y2", "r", .autoPick)
        ])
        XCTAssertEqual(autoWins.keep?.asset.id, "Y2", "autoPick batte nessuna scelta")

        let firstWins = BurstCluster(members: [
            burst("Z1", "r", .none),
            burst("Z2", "r", .none)
        ])
        XCTAssertEqual(firstWins.keep?.asset.id, "Z1", "senza pick, il primo d'ingresso")
    }

    // La proposta porta il keep NATIVO e i removable senza dHash (il keep di un burst non
    // è per vicinanza percettiva). Nessuna eliminazione qui.
    func test_proposal_keepIsNativePick_removableTheRest_noDHash() {
        let cluster = BurstCluster(members: [
            burst("K", "r", .userPick),
            burst("R1", "r"),
            burst("R2", "r")
        ])
        let proposal = BurstGrouping.proposal(for: cluster)

        XCTAssertEqual(proposal?.keep.asset.id, "K")
        XCTAssertNil(proposal?.keep.dHash, "il keep di un burst è nativo, non porta dHash")
        XCTAssertEqual(proposal?.removable.map(\.asset.id), ["R1", "R2"])
        XCTAssertEqual(proposal?.removable.allSatisfy { $0.dHash == nil }, true)
    }

    // Una raffica di un solo scatto: keep = quello scatto, removable vuoto.
    func test_singleMemberBurst_keepOnly_noRemovable() {
        let cluster = BurstCluster(members: [burst("Solo", "r", .autoPick)])
        XCTAssertEqual(cluster.keep?.asset.id, "Solo")
        XCTAssertTrue(cluster.removable.isEmpty)
        XCTAssertEqual(BurstGrouping.proposal(for: cluster)?.removable.isEmpty, true)
    }

    // Input vuoto ⇒ nessun cluster.
    func test_empty_isEmpty() {
        XCTAssertTrue(BurstGrouping.groups(of: []).isEmpty)
    }
}
