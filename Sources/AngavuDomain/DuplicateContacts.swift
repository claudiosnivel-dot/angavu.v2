import Foundation

// T-090 — Rilevamento contatti duplicati (Domain PURO).
//
// Estende l'onestà di Angavu al dominio contatti: individua i duplicati e
// propone un merge, MAI eseguito in autonomia. Nessun tipo di piattaforma qui
// (niente `Contacts`): l'enumerazione vive dietro il port `ContactsProviding`
// del Data layer (00-INDEX §1bis, altitudine `domain ↛ data`); il Domain riceve
// solo `ContactEntry` puri e ci ragiona.
//
// Regola di duplicazione (dichiarata): due contatti sono duplicati quando
// condividono lo STESSO nome normalizzato E almeno un punto di contatto
// (numero o email) normalizzato in comune. Il nome da solo non basta — persone
// diverse con lo stesso nome non vanno mai fuse (nessun falso "via libera").

/// Contatto normalizzato e indipendente dalla piattaforma. L'adapter del Data
/// layer estrae questi valori dai `CNContact` senza far entrare `Contacts` nel Domain.
public struct ContactEntry: Equatable, Sendable, Identifiable {
    /// Identificatore stabile del contatto (in Contacts: `CNContact.identifier`).
    public let id: String
    public let givenName: String
    public let familyName: String
    public let phoneNumbers: [String]
    public let emailAddresses: [String]

    public init(
        id: String,
        givenName: String,
        familyName: String,
        phoneNumbers: [String] = [],
        emailAddresses: [String] = []
    ) {
        self.id = id
        self.givenName = givenName
        self.familyName = familyName
        self.phoneNumbers = phoneNumbers
        self.emailAddresses = emailAddresses
    }
}

/// Normalizzazione pura dei campi contatto, così che varianti "cosmetiche"
/// coincidano senza far coincidere persone diverse.
enum ContactNormalization {
    /// Nome normalizzato: `given + family` in minuscolo, spazi collassati e
    /// potati. Due voci con nome/cognome scritti con spaziatura o maiuscole
    /// diverse condividono lo stesso nome normalizzato.
    static func name(given: String, family: String) -> String {
        let joined = "\(given) \(family)"
        let parts = joined.lowercased().split(whereSeparator: { $0.isWhitespace })
        return parts.joined(separator: " ")
    }

    /// Numero normalizzato: sole cifre; se più lungo di 10, si tengono le ultime
    /// 10 (collassa i prefissi internazionali del solito numero). Vuoto → scartato.
    static func phone(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return digits.count > 10 ? String(digits.suffix(10)) : digits
    }

    /// Email normalizzata: minuscolo e potata. Vuota → scartata.
    static func email(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Chiavi normalizzate di un contatto, usate per decidere la duplicazione.
private struct ContactKeys {
    let normalizedName: String
    let phones: Set<String>
    let emails: Set<String>

    init(_ contact: ContactEntry) {
        normalizedName = ContactNormalization.name(given: contact.givenName, family: contact.familyName)
        phones = Set(contact.phoneNumbers.compactMap(ContactNormalization.phone))
        emails = Set(contact.emailAddresses.compactMap(ContactNormalization.email))
    }

    /// Duplicati se stesso nome normalizzato (non vuoto) E un punto di contatto
    /// condiviso. Un nome vuoto non fa mai da chiave (nessun cluster "senza nome").
    func isDuplicate(of other: ContactKeys) -> Bool {
        guard !normalizedName.isEmpty, normalizedName == other.normalizedName else { return false }
        return !phones.isDisjoint(with: other.phones) || !emails.isDisjoint(with: other.emails)
    }
}

/// Cluster di contatti giudicati duplicati fra loro (>= 2 per costruzione).
public struct DuplicateContactCluster: Equatable, Sendable {
    public let contacts: [ContactEntry]

    public init(contacts: [ContactEntry]) {
        self.contacts = contacts
    }
}

/// Rilevamento puro dei duplicati.
public enum DuplicateContactDetection {
    /// Raggruppa i contatti duplicati in cluster. Passaggio greedy deterministico:
    /// i contatti sono ordinati per `id` e ciascuno entra nel primo cluster il cui
    /// rappresentante (primo membro) lo giudica duplicato; altrimenti apre un nuovo
    /// cluster. Solo i cluster con >= 2 membri sono restituiti (un contatto senza
    /// duplicati non è un cluster, AC-090-1).
    public static func clusters(_ contacts: [ContactEntry]) -> [DuplicateContactCluster] {
        let ordered = contacts.sorted { $0.id < $1.id }

        var clusters: [[ContactEntry]] = []
        var clusterKeys: [ContactKeys] = []

        for contact in ordered {
            let keys = ContactKeys(contact)
            if let index = clusterKeys.firstIndex(where: { keys.isDuplicate(of: $0) }) {
                clusters[index].append(contact)
            } else {
                clusters.append([contact])
                clusterKeys.append(keys)
            }
        }

        return clusters.compactMap { members in
            members.count > 1 ? DuplicateContactCluster(contacts: members) : nil
        }
    }
}

/// Proposta di merge per un cluster di duplicati: un contatto "primario" da tenere
/// e gli altri da fondervi. È SOLO dati — nessun contatto viene fuso qui (AC-090-2);
/// l'applicazione confermata è di T-092.
public struct ContactMergeProposal: Equatable, Sendable {
    /// Contatto che si propone di conservare (deterministico: `id` minore).
    public let primary: ContactEntry
    /// Contatti che si propone di fondere nel primario (mai fusi qui).
    public let duplicates: [ContactEntry]

    public init(primary: ContactEntry, duplicates: [ContactEntry]) {
        self.primary = primary
        self.duplicates = duplicates
    }
}

/// Composizione pura delle proposte di merge.
public enum ContactMergeProposalComposer {
    /// Proposta per un cluster: primario = `id` minore (arbitrario ma stabile), gli
    /// altri marcati come da fondere. `nil` per un cluster degenere senza contatti.
    public static func propose(for cluster: DuplicateContactCluster) -> ContactMergeProposal? {
        let ordered = cluster.contacts.sorted { $0.id < $1.id }
        guard let primary = ordered.first else { return nil }
        return ContactMergeProposal(primary: primary, duplicates: Array(ordered.dropFirst()))
    }

    /// Comodità: una proposta per ogni cluster (i degeneri sono omessi).
    public static func proposals(for clusters: [DuplicateContactCluster]) -> [ContactMergeProposal] {
        clusters.compactMap { propose(for: $0) }
    }
}
