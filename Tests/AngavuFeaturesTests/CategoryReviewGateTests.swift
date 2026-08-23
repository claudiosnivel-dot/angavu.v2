import XCTest
import AngavuDomain
import AngavuData
@testable import AngavuFeatures

// Guscio UI — Review di categoria: gate d'anteprima a passi (la UX reale) e
// produttore della review dai dati VERI dell'indice. Il gate resta quello della
// rete di sicurezza (T-050): nessun percorso lo aggira, mai i keep, mai
// un'anteprima vuota.

// MARK: - Fake dei port (riuso del pattern di AppEnvironmentTests)

private struct FakeAuthorizer: PhotoLibraryAuthorizing {
    func currentAccess() -> PhotoAccess { .full }
    func requestAccess() async -> PhotoAccess { .full }
}

private struct FakeEnumerator: PhotoAssetEnumerating {
    func enumerateRawAssets() -> [RawEnumeratedAsset] { [] }
}

private struct StubIndex: AssetIndexReading, AssetIndexWriting {
    let assetsToReturn: [LibraryAsset]
    func assets(matching query: AssetQuery) throws -> [LibraryAsset] { assetsToReturn }
    func count() throws -> Int { assetsToReturn.count }
    func upsert(_ assets: [LibraryAsset]) throws {}
    func remove(ids: [String]) throws {}
}

private struct ThrowingIndex: AssetIndexReading, AssetIndexWriting {
    struct Boom: Error {}
    func assets(matching query: AssetQuery) throws -> [LibraryAsset] { throw Boom() }
    func count() throws -> Int { throw Boom() }
    func upsert(_ assets: [LibraryAsset]) throws {}
    func remove(ids: [String]) throws {}
}

private struct FakeByteResolver: AssetByteSizeResolving {
    func byteSize(forLocalIdentifier localIdentifier: String, fallbackEstimate: Int64) -> ByteSize {
        .estimated(bytes: fallbackEstimate)
    }
}

private struct FakeDeviceStorage: DeviceStorageInspecting {
    func optimizeStorageStatus() -> ICloudOptimizeStorage { .disabled }
    func deviceResidentBytes(forLocalIdentifier id: String, libraryBytes: Int64) -> Int64 { libraryBytes }
}

private func makeEnvironment<Index: AssetIndexReading & AssetIndexWriting>(index: Index) -> AppEnvironment {
    AppEnvironment(
        authorizer: FakeAuthorizer(),
        enumerator: FakeEnumerator(),
        indexReader: index,
        indexWriter: index,
        byteResolver: FakeByteResolver(),
        deviceStorage: FakeDeviceStorage(),
        videoExporter: NoopVideoExporter(),
        videoSpecProvider: NoopVideoSpecProvider()
    )
}

private func photo(_ id: String, subtypes: Set<AssetSubtype> = []) -> LibraryAsset {
    LibraryAsset(
        id: id,
        kind: .photo,
        pixelSize: PixelSize(width: 10, height: 10),
        creationDate: nil,
        subtypes: subtypes
    )
}

// MARK: - Gate d'anteprima a passi (VM)

final class CategoryReviewGateTests: XCTestCase {

    // Apri anteprima → conferma: arriva a confirmed ESATTAMENTE sui removable, mai i keep.
    func test_previewThenConfirm_confirmsExactlyRemovable() {
        let vm = CategoryReviewViewModel(review: CategoryReview(keepIds: ["K1"], removableIds: ["R1", "R2"]))

        XCTAssertTrue(vm.presentDeletionPreviewForAllRemovable())
        XCTAssertEqual(vm.flow.state, .previewing(assets: ["R1", "R2"], accepted: false))

        XCTAssertTrue(vm.confirmDeletion())
        XCTAssertEqual(vm.flow.state, .confirmed(assets: ["R1", "R2"]))
        XCTAssertFalse(vm.flow.pendingAssets.contains("K1"))
    }

    // La selezione mista filtra i keep prima di aprire l'anteprima.
    func test_preview_filtersKeepFromMixedSelection() {
        let vm = CategoryReviewViewModel(review: CategoryReview(keepIds: ["K1"], removableIds: ["R1", "R2"]))

        XCTAssertTrue(vm.presentDeletionPreview(of: ["K1", "R1"]))
        XCTAssertEqual(vm.flow.state, .previewing(assets: ["R1"], accepted: false))
    }

    // Selezione vuota (o di soli keep) ⇒ nessuna anteprima aperta (nessuna anteprima vuota).
    func test_preview_emptyOrKeepOnly_isRejected() {
        let vm = CategoryReviewViewModel(review: CategoryReview(keepIds: ["K1"], removableIds: ["R1"]))

        XCTAssertFalse(vm.presentDeletionPreview(of: []))
        XCTAssertFalse(vm.presentDeletionPreview(of: ["K1"]))
        XCTAssertEqual(vm.flow.state, .idle)
    }

    // Conferma senza anteprima aperta ⇒ rifiutata (gate obbligatorio).
    func test_confirm_withoutPreview_isRejected() {
        let vm = CategoryReviewViewModel(review: CategoryReview(keepIds: [], removableIds: ["R1"]))
        XCTAssertFalse(vm.confirmDeletion())
        XCTAssertEqual(vm.flow.state, .idle)
    }

    // Annulla azzera il gate: si torna a rivedere, nessuna eliminazione.
    func test_cancel_resetsGateToIdle() {
        let vm = CategoryReviewViewModel(review: CategoryReview(keepIds: [], removableIds: ["R1"]))
        XCTAssertTrue(vm.presentDeletionPreviewForAllRemovable())
        vm.cancelDeletion()
        XCTAssertEqual(vm.flow.state, .idle)
    }

    // MARK: - Produttore della review dai dati veri dell'indice

    // Screenshot: solo gli asset col sottotipo .screenshot diventano removable
    // (nessun keep), ordine d'ingresso preservato; gli altri esclusi.
    func test_screenshotSource_selectsOnlyScreenshotsAsRemovable() throws {
        let env = makeEnvironment(index: StubIndex(assetsToReturn: [
            photo("S1", subtypes: [.screenshot]),
            photo("P1"),
            photo("S2", subtypes: [.screenshot])
        ]))

        let review = try CategoryReviewSource.review(for: .screenshots, from: env)

        XCTAssertTrue(review.keepIds.isEmpty, "gli screenshot sono a eliminazione diretta: nessun keep")
        XCTAssertEqual(review.removableIds, ["S1", "S2"], "solo gli screenshot, nell'ordine d'ingresso")
    }

    // Nessuno screenshot → review vuota (niente da eliminare), non un errore.
    func test_screenshotSource_emptyWhenNoScreenshots() throws {
        let env = makeEnvironment(index: StubIndex(assetsToReturn: [photo("P1"), photo("P2")]))
        let review = try CategoryReviewSource.review(for: .screenshots, from: env)
        XCTAssertTrue(review.removableIds.isEmpty)
        XCTAssertTrue(review.keepIds.isEmpty)
    }

    // La lettura dell'indice che fallisce si propaga: mai una lista vuota spacciata
    // per «pulito» (L-COL-006).
    func test_screenshotSource_propagatesIndexError() {
        let env = makeEnvironment(index: ThrowingIndex())
        XCTAssertThrowsError(try CategoryReviewSource.review(for: .screenshots, from: env))
    }
}
