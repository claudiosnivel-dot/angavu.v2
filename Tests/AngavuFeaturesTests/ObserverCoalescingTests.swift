import Foundation
import XCTest
@testable import AngavuData
@testable import AngavuDomain
@testable import AngavuFeatures

// FSE-K4 — Oracolo della coalescenza dell'observer dei cambi libreria.
//
// AC-FSE-K4-1: N notifiche ravvicinate con id diversi → UNA sola invalidazione con
// l'UNIONE degli id (mai N potature separate, mai N scritture write-through).
// AC-FSE-K4-2: una notifica di solo riordino (`hasMoves`, nessun inserted/removed/changed
// → delta VUOTO) non produce alcuna invalidazione: cache e persistenza intatte.
//
// Lo scheduler è pilotato a mano (`ManualFlushScheduler`): nessuna attesa di tempo reale,
// verdetto deterministico. La registrazione PhotoKit reale resta device-only (AC-FSE-J5-2,
// non coperta); qui si prova il contratto logico del coordinatore-come-sink.

// MARK: - Doppioni (a livello di file: SwiftLint `nesting`)

/// Handle di un flush pianificato dallo scheduler manuale.
private final class ManualFlushHandle: ScheduledFlush {
    var cancelled = false
    let work: () -> Void
    init(work: @escaping () -> Void) { self.work = work }
    func cancel() { cancelled = true }
}

/// Scheduler manuale: registra ogni flush pianificato; `fire()` esegue quelli non
/// cancellati (con il debounce corretto ce n'è al più UNO vivo per finestra).
private final class ManualFlushScheduler: FlushScheduling {
    private(set) var handles: [ManualFlushHandle] = []
    var scheduledCount: Int { handles.count }
    var liveCount: Int { handles.filter { !$0.cancelled }.count }

    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> any ScheduledFlush {
        let handle = ManualFlushHandle(work: work)
        handles.append(handle)
        return handle
    }

    func fire() {
        for handle in handles where !handle.cancelled {
            handle.cancelled = true
            handle.work()
        }
    }
}

/// Store dei derivati che registra OGNI invocazione di `remove(ids:)` (una per flush).
private final class RecordingDerivedStore: DerivedResultStoring {
    private(set) var removeCalls: [Set<String>] = []
    func loadAll() throws -> [DerivedKey: DerivedRecordValue] { [:] }
    func upsert(_ entries: [DerivedKey: DerivedRecordValue]) throws {}
    func remove(ids: [String]) throws { removeCalls.append(Set(ids)) }
    func removeAll() throws {}
}

/// Persistenza dei risultati per categoria che conta le scritture (write-through K1).
private final class RecordingCategoryStore: CategoryResultStoring {
    private(set) var upsertCount = 0
    private(set) var removeCount = 0
    func loadAll() throws -> [CategoryResultRecordValue] { [] }
    func upsert(_ value: CategoryResultRecordValue) throws { upsertCount += 1 }
    func remove(kind: String) throws { removeCount += 1 }
    func removeAll() throws { removeCount += 1 }
}

private func makeAsset(_ id: String) -> LibraryAsset {
    LibraryAsset(id: id, kind: .photo, pixelSize: PixelSize(width: 10, height: 10),
                 creationDate: Date(timeIntervalSince1970: 1_700_000_000), subtypes: [])
}

private func makeCategoryData(keep: [String], removable: [String]) -> CategoryReviewData {
    let ids = keep + removable
    let assets = Dictionary(uniqueKeysWithValues: ids.map { ($0, makeAsset($0)) })
    return CategoryReviewData(review: CategoryReview(keepIds: keep, removableIds: removable),
                              assets: assets)
}

final class ObserverCoalescingTests: XCTestCase {

    private struct Fixture {
        let store: AnalysisResultsStore
        let persistence: RecordingCategoryStore
        let derived: RecordingDerivedStore
        let scheduler: ManualFlushScheduler
        let coordinator: LibraryObservationCoordinator
    }

    private func makeFixture() -> Fixture {
        let persistence = RecordingCategoryStore()
        let store = AnalysisResultsStore(persistence: persistence)
        store.set(makeCategoryData(keep: ["k1"], removable: ["r1", "r2"]),
                  for: .category("exactDuplicates"), at: Date())
        store.set(makeCategoryData(keep: ["k9"], removable: ["r9"]),
                  for: .category("similarPhotos"), at: Date())
        store.set(999, for: .dashboard)
        let derived = RecordingDerivedStore()
        let scheduler = ManualFlushScheduler()
        let coordinator = LibraryObservationCoordinator(
            store: store,
            derivedCache: DerivedResultCache(store: derived),
            scheduler: scheduler
        )
        return Fixture(store: store, persistence: persistence, derived: derived,
                       scheduler: scheduler, coordinator: coordinator)
    }

    // MARK: - AC-FSE-K4-1 — raffica → UNA invalidazione con l'unione degli id

    func test_burstOfNotifications_yieldsOneInvalidationWithUnionOfIds() {
        let fx = makeFixture()
        let writesAfterSetup = fx.persistence.upsertCount

        fx.coordinator.didObserve(IndexDelta(removed: ["r1"]))
        fx.coordinator.didObserve(IndexDelta(changed: [makeAsset("r9")]))
        fx.coordinator.didObserve(IndexDelta(added: [makeAsset("new")]))

        // Dentro la finestra: NULLA è ancora invalidato (né cache, né derivati, né
        // persistenza) e c'è UNA sola finestra viva (le precedenti sono state cancellate).
        let dupBefore: CategoryReviewData? = fx.store.value(for: .category("exactDuplicates"))
        XCTAssertEqual(dupBefore?.review.removableIds, ["r1", "r2"], "nessuna potatura prima del flush")
        XCTAssertEqual(fx.derived.removeCalls, [], "nessuna invalidazione dei derivati prima del flush")
        XCTAssertEqual(fx.persistence.upsertCount, writesAfterSetup, "nessuna scrittura prima del flush")
        XCTAssertEqual(fx.scheduler.scheduledCount, 3, "ogni notifica riapre la finestra")
        XCTAssertEqual(fx.scheduler.liveCount, 1, "una sola finestra viva: le precedenti cancellate")

        fx.scheduler.fire()

        // UNA invalidazione con l'UNIONE degli id toccati (changed ∪ removed), mai tre.
        XCTAssertEqual(fx.derived.removeCalls, [Set(["r1", "r9"])], "una sola potatura dei derivati, id uniti")
        let dup: CategoryReviewData? = fx.store.value(for: .category("exactDuplicates"))
        XCTAssertEqual(dup?.review.removableIds, ["r2"], "r1 potato dalla categoria toccata")
        let similar: CategoryReviewData? = fx.store.value(for: .category("similarPhotos"))
        XCTAssertEqual(similar?.review.removableIds, [], "r9 (cambiato) potato dall'altra categoria")
        let dash: Int? = fx.store.value(for: .dashboard)
        XCTAssertNil(dash, "aggregati invalidati una volta")
        // Write-through: UNA scrittura per categoria potata (2), non una per notifica (N·2).
        XCTAssertEqual(fx.persistence.upsertCount - writesAfterSetup, 2, "una ripersistenza per categoria toccata")
        XCTAssertEqual(fx.scheduler.liveCount, 0, "finestra chiusa dopo il flush")
    }

    func test_afterFlush_nextNotificationOpensFreshWindow_withoutStaleIds() {
        let fx = makeFixture()
        fx.coordinator.didObserve(IndexDelta(removed: ["r1"]))
        fx.scheduler.fire()
        XCTAssertEqual(fx.derived.removeCalls, [Set(["r1"])])

        fx.coordinator.didObserve(IndexDelta(removed: ["r9"]))
        fx.scheduler.fire()

        // La seconda finestra porta SOLO i suoi id: niente accumulo stantìo.
        XCTAssertEqual(fx.derived.removeCalls, [Set(["r1"]), Set(["r9"])])
    }

    // MARK: - AC-FSE-K4-2 — solo riordino → nessuna invalidazione

    func test_movesOnlyNotification_isIgnored_cacheAndPersistenceIntact() {
        let fx = makeFixture()
        let writesAfterSetup = fx.persistence.upsertCount

        // Solo riordino: PhotoKit riporta `hasMoves` senza inserted/removed/changed → il
        // traduttore produce un delta vuoto (e l'observer PhotoKit non lo inoltra nemmeno).
        fx.coordinator.didObserve(IndexDelta())
        fx.scheduler.fire()

        XCTAssertEqual(fx.scheduler.scheduledCount, 0, "nessuna finestra aperta per un delta vuoto")
        let dup: CategoryReviewData? = fx.store.value(for: .category("exactDuplicates"))
        XCTAssertEqual(dup?.review.removableIds, ["r1", "r2"], "cache intatta")
        let dash: Int? = fx.store.value(for: .dashboard)
        XCTAssertEqual(dash, 999, "aggregati intatti")
        XCTAssertEqual(fx.derived.removeCalls, [], "derivati intatti")
        XCTAssertEqual(fx.persistence.upsertCount, writesAfterSetup, "persistenza intatta: nessuna scrittura")
        XCTAssertEqual(fx.persistence.removeCount, 0, "persistenza intatta: nessuna rimozione")
    }

    // MARK: - Fusione pura dei delta

    func test_merge_removedWins_addedThenChangedStaysAdded_orderDeterministic() {
        let first = IndexDelta(added: [makeAsset("b"), makeAsset("a")], changed: [makeAsset("c")])
        let second = IndexDelta(added: [makeAsset("d")], removed: ["c", "a"], changed: [makeAsset("b")])

        let merged = CoalescingLibraryChangeSink.merge(first, second)

        XCTAssertEqual(merged.added.map(\.id), ["b", "d"], "a rimosso sparisce da added; b resta added; ordinato")
        XCTAssertEqual(merged.removed, ["a", "c"], "removed = unione, ordinata")
        XCTAssertEqual(merged.changed, [], "c rimosso sparisce da changed; b cambiato resta added")

        // Rimosso POI riaggiunto: sia removed sia added (delete+insert, come l'indice).
        let readded = CoalescingLibraryChangeSink.merge(IndexDelta(removed: ["x"]), IndexDelta(added: [makeAsset("x")]))
        XCTAssertEqual(readded.removed, ["x"])
        XCTAssertEqual(readded.added.map(\.id), ["x"])
    }
}

// MARK: - Livello A / radice di composizione: il grafo di sessione posseduto dall'App

#if canImport(SwiftData) && canImport(Photos)
@available(macOS 14, iOS 17, *)
final class AppRuntimeCompositionRootTests: XCTestCase {

    /// `AppRuntime` (posseduto da `AngavuApp`) cabla UN solo store, condiviso fra le
    /// schermate e l'observer: un delta osservato dall'observer pota LO STESSO store che
    /// le view leggono, sopra la persistenza reale del grafo `live()`.
    func test_appRuntime_observerPrunesTheSameStoreViewsRead() throws {
        let scheduler = ManualFlushScheduler()
        let runtime = AppRuntime(environment: try LiveCompositionRoot.make(), observerScheduler: scheduler)
        runtime.store.set(makeCategoryData(keep: ["k1"], removable: ["r1"]),
                          for: .category("exactDuplicates"), at: Date())
        XCTAssertNil(runtime.store.lastPersistenceError, "persistenza reale del grafo live")

        runtime.libraryObserver.didObserve(IndexDelta(removed: ["r1"]))
        scheduler.fire()

        let dup: CategoryReviewData? = runtime.store.value(for: .category("exactDuplicates"))
        XCTAssertEqual(dup?.review.removableIds, [], "l'observer pota lo stesso store delle view")
        XCTAssertTrue(runtime.environment.categoryResultStore is SwiftDataCategoryResultStore,
                      "lo store dei risultati nel grafo live() è quello SwiftData reale (K1)")
    }
}
#endif
