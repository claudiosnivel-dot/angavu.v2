import AngavuDomain

// T-090 / T-092 (Data) — Enumerazione e merge dei contatti via framework `Contacts`.
//
// Il port `ContactsProviding` è dichiarato QUI nel Data layer (DoD T-090): fornisce
// al Domain i `ContactEntry` puri su cui calcolare i duplicati. `SystemContactMerger`
// implementa il port di merge `ContactMerging` del Domain (T-092): esegue la fusione
// reale solo quando l'applicatore, superato il gate di conferma, lo invoca.
//
// Privacy (00-INDEX §3): nessun contatto lascia il device (zero rete/telemetria);
// l'accesso è coperto da `NSContactsUsageDescription`. Il merge è distruttivo, quindi
// mai automatico — arriva solo dietro conferma esplicita (L-COL-005).

/// Port di enumerazione dei contatti. L'implementazione reale vive sotto (guardata
/// `canImport(Contacts)`); nei test/anteprima si può sostituire con un fake.
public protocol ContactsProviding {
    /// I contatti della rubrica, normalizzati a `ContactEntry`.
    func fetchContacts() throws -> [ContactEntry]
}

#if canImport(Contacts)
import Contacts

/// Chiavi minime necessarie: identità + punti di contatto per la duplicazione.
private let contactKeys: [CNKeyDescriptor] = [
    CNContactIdentifierKey,
    CNContactGivenNameKey,
    CNContactFamilyNameKey,
    CNContactPhoneNumbersKey,
    CNContactEmailAddressesKey
] as [CNKeyDescriptor]

/// Adapter reale: enumera i contatti in un solo passaggio e li normalizza.
public struct SystemContactsProvider: ContactsProviding {
    public init() {}

    public func fetchContacts() throws -> [ContactEntry] {
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: contactKeys)
        var results: [ContactEntry] = []
        try store.enumerateContacts(with: request) { contact, _ in
            results.append(Self.map(contact))
        }
        return results
    }

    /// Mappa un `CNContact` sul modello di dominio puro.
    static func map(_ contact: CNContact) -> ContactEntry {
        ContactEntry(
            id: contact.identifier,
            givenName: contact.givenName,
            familyName: contact.familyName,
            phoneNumbers: contact.phoneNumbers.map { $0.value.stringValue },
            emailAddresses: contact.emailAddresses.map { $0.value as String }
        )
    }
}

/// Adapter reale del merge (port `ContactMerging`). Fonde i punti di contatto dei
/// duplicati nel primario ed elimina i duplicati, in un'unica `CNSaveRequest`.
/// Chiamato SOLO dopo il gate di conferma (T-092); mai in autonomia.
public struct SystemContactMerger: ContactMerging {
    public init() {}

    public func merge(_ proposal: ContactMergeProposal) async -> ExtraActionOutcome {
        let store = CNContactStore()
        do {
            let primaryContact = try store.unifiedContact(
                withIdentifier: proposal.primary.id,
                keysToFetch: contactKeys
            )
            guard let primary = primaryContact.mutableCopy() as? CNMutableContact else {
                return .failed(reason: "Contatto primario non modificabile.")
            }

            let save = CNSaveRequest()
            var existingPhones = Set(primary.phoneNumbers.map { $0.value.stringValue })
            var existingEmails = Set(primary.emailAddresses.map { $0.value as String })

            for duplicate in proposal.duplicates {
                let dupContact = try store.unifiedContact(
                    withIdentifier: duplicate.id,
                    keysToFetch: contactKeys
                )
                for phone in dupContact.phoneNumbers where existingPhones.insert(phone.value.stringValue).inserted {
                    primary.phoneNumbers.append(phone)
                }
                for email in dupContact.emailAddresses where existingEmails.insert(email.value as String).inserted {
                    primary.emailAddresses.append(email)
                }
                if let mutableDup = dupContact.mutableCopy() as? CNMutableContact {
                    save.delete(mutableDup)
                }
            }

            save.update(primary)
            try store.execute(save)
            return .applied
        } catch {
            return .failed(reason: (error as NSError).localizedDescription)
        }
    }
}
#endif
