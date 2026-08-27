import Foundation

// FSE-E1 (Domain) — Policy PURA di validità della cache dei derivati (leva 5).
//
// I derivati costosi di una scansione (feature print, hash, nitidezza, residenza) sono
// stabili finché il CONTENUTO dell'asset non cambia. Persisterli fra gli avvii rende
// immediate le scansioni successive — ma solo se sappiamo, in modo deterministico,
// QUANDO un derivato è ancora valido e quando è stantìo (FAST-SCAN-ENGINE-PLAN §1.5).
//
// Questo modulo definisce la CHIAVE di validità e la POLICY, pure e testabili su Linux:
// un derivato è valido SSE la sua chiave (id + versione del contenuto) combacia con
// quella dell'asset corrente. Mai un punteggio stantìo servito per un asset cambiato
// (onestà, 00-INDEX §6). Lo storage concreto (SwiftData) è FSE-E2; il cablaggio
// get-or-compute è FSE-E3. Qui: solo aritmetica di insiemi, zero piattaforma.

/// Chiave di validità di un derivato: l'identità dell'asset PIÙ una versione del suo
/// contenuto (in produzione la `modificationDate`/versione di PhotoKit). Due derivati
/// con la stessa chiave descrivono lo stesso contenuto; una chiave diversa (stesso id,
/// versione nuova) segnala che il contenuto è cambiato → il derivato va ricalcolato.
public struct DerivedKey: Hashable, Sendable {
    /// Identificatore locale stabile dell'asset (`PHAsset.localIdentifier`).
    public let id: String
    /// Versione del contenuto: cambia quando l'asset è modificato (mai riusata a caso).
    public let contentVersion: String

    public init(id: String, contentVersion: String) {
        self.id = id
        self.contentVersion = contentVersion
    }
}

/// Partizione degli asset correnti rispetto ai derivati persistiti.
public struct DerivedPartition: Equatable, Sendable {
    /// Derivati ancora VALIDI (chiave combacia): riusabili senza ricalcolo.
    public let reusable: [DerivedKey]
    /// Asset correnti SENZA un derivato valido (nuovi o stantìi): da (ri)calcolare.
    public let toRecompute: [DerivedKey]
    /// Derivati persistiti per asset NON più presenti: da scartare dalla cache.
    public let removed: [DerivedKey]

    public init(reusable: [DerivedKey], toRecompute: [DerivedKey], removed: [DerivedKey]) {
        self.reusable = reusable
        self.toRecompute = toRecompute
        self.removed = removed
    }
}

/// Policy pura di validità e partizionamento dei derivati.
public enum DerivedResultValidity {
    /// Un derivato persistito è valido per l'asset corrente SSE la chiave combacia
    /// (stesso id E stessa `contentVersion`). Chiave diversa → stantìo, mai valido.
    public static func isValid(persisted: DerivedKey, forCurrent current: DerivedKey) -> Bool {
        persisted == current
    }

    /// Partiziona gli asset correnti e i derivati persistiti in
    /// {riusabili, da-ricalcolare, rimossi}, in modo deterministico:
    ///   • riusabili / da-ricalcolare nell'ordine degli asset CORRENTI;
    ///   • rimossi nell'ordine dei derivati PERSISTITI.
    ///
    /// Regole:
    ///   • un asset corrente con un derivato persistito di pari chiave → riusabile;
    ///   • un asset corrente nuovo, o con versione cambiata → da ricalcolare (mai un
    ///     derivato stantìo spacciato per valido);
    ///   • un derivato persistito per un id non più corrente → rimosso (scartato);
    ///   • `invalidateAll` (dopo un'eliminazione o un cambio libreria totale) forza
    ///     TUTTI i correnti a «da ricalcolare»: nessun persistito è valido.
    public static func partition(
        current: [DerivedKey],
        persisted: [DerivedKey],
        invalidateAll: Bool = false
    ) -> DerivedPartition {
        var persistedByID: [String: DerivedKey] = [:]
        persistedByID.reserveCapacity(persisted.count)
        for key in persisted where persistedByID[key.id] == nil {
            persistedByID[key.id] = key
        }
        let currentIDs = Set(current.map(\.id))

        var reusable: [DerivedKey] = []
        var toRecompute: [DerivedKey] = []
        for key in current {
            if !invalidateAll,
               let stored = persistedByID[key.id],
               isValid(persisted: stored, forCurrent: key) {
                reusable.append(key)
            } else {
                toRecompute.append(key)
            }
        }
        let removed = persisted.filter { !currentIDs.contains($0.id) }

        return DerivedPartition(reusable: reusable, toRecompute: toRecompute, removed: removed)
    }
}
