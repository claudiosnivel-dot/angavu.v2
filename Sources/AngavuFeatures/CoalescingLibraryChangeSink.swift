import AngavuData
import AngavuDomain
import Foundation

// FSE-K4 (hardening dell'observer, censimento C4) — Coalescenza dei cambi libreria.
//
// PhotoKit notifica a raffica: un'importazione, una sincronizzazione iCloud o una nostra
// stessa eliminazione producono N `photoLibraryDidChange` ravvicinati, ciascuno con pochi
// id. Inoltrarli uno a uno al sink (FSE-J5) significa N potature separate, N scritture
// write-through (FSE-K1) e N invalidazioni degli aggregati — e, dal thread di PhotoKit,
// N mutazioni off-main dello store osservabile. Questo decoratore raccoglie i delta in una
// finestra di debounce (~0,5 s, guida Apple: «coalesce change notifications») e inoltra a
// valle UN solo delta = UNIONE degli id (AC-FSE-K4-1), sul main actor.
//
// Una notifica di solo riordino (`hasMoves` senza inserted/removed/changed) arriva qui
// come delta VUOTO: è ignorata del tutto — nessuna finestra aperta, nessuna
// invalidazione, cache e persistenza intatte (AC-FSE-K4-2).
//
// La FUSIONE dei delta è pura e deterministica (`merge`, oracolo in CI); la
// schedulazione è iniettabile (`FlushScheduling`) così i test la pilotano a mano, senza
// attese di tempo reale. Il default (`MainActorFlushScheduler`) usa un `Task` cancellabile
// che consegna sul main actor: lo store `@Observable` è mutato dove SwiftUI lo legge.

/// Pianifica l'esecuzione differita di un lavoro, cancellabile. Iniettabile nei test.
public protocol FlushScheduling {
    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> any ScheduledFlush
}

/// Handle di un flush pianificato: `cancel()` è idempotente.
public protocol ScheduledFlush: AnyObject {
    func cancel()
}

/// Scheduler di produzione: dopo `seconds` esegue il lavoro sul main actor (un `Task`
/// cancellabile). Cancellato prima della scadenza → il lavoro non parte.
public struct MainActorFlushScheduler: FlushScheduling {
    public init() {}

    public func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> any ScheduledFlush {
        let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            work()
        }
        return TaskFlush(task: task)
    }

    private final class TaskFlush: ScheduledFlush {
        private let task: Task<Void, Never>
        init(task: Task<Void, Never>) { self.task = task }
        func cancel() { task.cancel() }
    }
}

/// Decoratore di `LibraryChangeSink` che coalesce i delta ravvicinati in uno solo.
/// Thread-safe: `didObserve` può arrivare dal thread di PhotoKit; il flush è consegnato
/// dallo scheduler (in produzione sul main actor).
public final class CoalescingLibraryChangeSink: LibraryChangeSink {
    /// Finestra di debounce di produzione (~0,5 s): abbastanza da assorbire una raffica di
    /// notifiche, abbastanza breve da non lasciare numeri stantìi a schermo.
    public static let defaultDebounce: TimeInterval = 0.5

    private let downstream: any LibraryChangeSink
    private let debounce: TimeInterval
    private let scheduler: any FlushScheduling
    private let lock = NSLock()
    private var pending: IndexDelta?
    private var scheduled: (any ScheduledFlush)?

    public init(
        downstream: any LibraryChangeSink,
        debounce: TimeInterval = CoalescingLibraryChangeSink.defaultDebounce,
        scheduler: any FlushScheduling = MainActorFlushScheduler()
    ) {
        self.downstream = downstream
        self.debounce = debounce
        self.scheduler = scheduler
    }

    /// Accumula il delta e (ri)apre la finestra di debounce. Un delta vuoto (solo
    /// riordino) è ignorato: nessuna finestra, nessuna invalidazione.
    public func didObserve(_ delta: IndexDelta) {
        guard !delta.isEmpty else { return }
        lock.lock()
        pending = pending.map { Self.merge($0, delta) } ?? delta
        scheduled?.cancel()
        scheduled = scheduler.schedule(after: debounce) { [weak self] in self?.flush() }
        lock.unlock()
    }

    /// Consegna a valle il delta accumulato (se c'è) e azzera la finestra.
    private func flush() {
        lock.lock()
        let delta = pending
        pending = nil
        scheduled = nil
        lock.unlock()
        guard let delta else { return }
        downstream.didObserve(delta)
    }

    // MARK: - Fusione pura (oracolo)

    /// Fonde `next` in `accumulated` (ordine temporale). Regole, per id:
    ///  • `removed` vince: un id rimosso sparisce da `added`/`changed` (una potatura a
    ///    valle è sempre corretta anche se l'id poi ricompare: si ricompone);
    ///  • un id già `added` che cambia resta `added` (con i metadati più recenti);
    ///  • un id aggiunto DOPO essere stato rimosso è sia `removed` sia `added`
    ///    (delete+insert: l'indice applica remove → upsert, come `IncrementalIndex`);
    ///  • `changed` più recente vince sullo stesso id.
    /// Output deterministico: liste ordinate per id.
    public static func merge(_ accumulated: IndexDelta, _ next: IndexDelta) -> IndexDelta {
        var added = Dictionary(accumulated.added.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        var changed = Dictionary(accumulated.changed.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        var removed = Set(accumulated.removed)

        for id in next.removed {
            removed.insert(id)
            added.removeValue(forKey: id)
            changed.removeValue(forKey: id)
        }
        for asset in next.added {
            added[asset.id] = asset
            changed.removeValue(forKey: asset.id)
        }
        for asset in next.changed {
            if added[asset.id] != nil {
                added[asset.id] = asset
            } else {
                changed[asset.id] = asset
            }
        }
        return IndexDelta(
            added: added.values.sorted { $0.id < $1.id },
            removed: removed.sorted(),
            changed: changed.values.sorted { $0.id < $1.id }
        )
    }
}

extension IndexDelta {
    /// Vero per una notifica senza inserimenti/rimozioni/cambi (es. solo riordino).
    var isEmpty: Bool { added.isEmpty && removed.isEmpty && changed.isEmpty }
}
