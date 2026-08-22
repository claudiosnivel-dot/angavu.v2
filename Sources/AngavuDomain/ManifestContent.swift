import Foundation

// T-100 — Contenuto del manifesto e della schermata "cosa NON facciamo" come DATI.
//
// La voce dell'app è modellata come dominio puro, non annegata nello styling
// SwiftUI (out_of_scope, 11-ui-shell.md): così il contenuto è testabile e
// resta coerente col VISION-AND-CONSTRAINTS §4. Due invarianti di onestà —
// conformità App Store (Guideline 2.3.x), nessun claim ingannevole:
//   • ogni non-goal è una RINUNCIA dichiarata, mai la promessa di una capacità
//     (AC-100-2): non si spaccia per fattibile ciò che il sandbox iOS vieta;
//   • ogni promessa positiva è mantenibile ON-DEVICE (AC-100-2): si promette
//     solo ciò che iOS permette davvero.
// L'insieme dei non-goals include, per nome stabile, le rinunce cardine del
// manifesto Android portato su iOS (AC-100-1).

// MARK: - Non-goals ("cosa NON facciamo")

/// Identità stabile di un non-goal. Il test asserisce l'appartenenza per `id`,
/// non per prosa: rinominare il testo non rompe l'oracolo, toglierne uno sì.
public enum NonGoalID: String, Sendable, Equatable, CaseIterable, Codable {
    /// "Pulizia cache di sistema / file temporanei / junk di altre app" — impossibile nel sandbox.
    case systemCacheCleaning
    /// Media di cartelle di altre app (WhatsApp/Telegram) o extra via SAF — non accessibili su iOS.
    case otherAppFolders
    /// RAM/CPU/battery booster — placebo.
    case resourceBooster
    /// "Antivirus" — non fattibile.
    case antivirus
    /// Ads, notifiche promo, scare tactics, numeri gonfiati — mai.
    case noAds
    /// Backend / sync cloud — zero server, tutto on-device.
    case zeroBackend
    /// IAP / Angavu Pro in v1 (DI-002) — si lancia tutto-free.
    case iapInV1
    /// Vault cifrato, widget, App Intents/Shortcuts, iPad/macOS dedicati — v2+.
    case advancedFeaturesDeferred
}

/// Una voce di "cosa NON facciamo". È una **rinuncia**, mai una capacità offerta:
/// `claimsCapability` è falso per costruzione del contenuto canonico (AC-100-2).
public struct NonGoal: Equatable, Sendable, Identifiable {
    public let id: NonGoalID
    /// Testo mostrato all'utente (schermata "cosa NON facciamo").
    public let text: String
    /// Il perché: onestà, non scusa. Rende il limite un segnale di fiducia.
    public let rationale: String
    /// Vero SOLO se la voce promette una capacità invece di rinunciarvi. Il
    /// contenuto canonico lo tiene sempre falso: un non-goal non è un claim.
    public let claimsCapability: Bool

    public init(id: NonGoalID, text: String, rationale: String, claimsCapability: Bool = false) {
        self.id = id
        self.text = text
        self.rationale = rationale
        self.claimsCapability = claimsCapability
    }
}

// MARK: - Promesse del manifesto (cosa facciamo, e possiamo davvero)

/// Identità stabile di una promessa del manifesto.
public enum ManifestPromiseID: String, Sendable, Equatable, CaseIterable, Codable {
    case offline
    case noAds
    case realNumbers
    case safetyNet
    case onePayment
}

/// Una promessa positiva del manifesto. `achievableOnDevice` è vero per il
/// contenuto canonico: si promette solo ciò che iOS permette senza server.
public struct ManifestPromise: Equatable, Sendable, Identifiable {
    public let id: ManifestPromiseID
    public let text: String
    /// Vero se la promessa è mantenibile interamente on-device, senza backend.
    public let achievableOnDevice: Bool

    public init(id: ManifestPromiseID, text: String, achievableOnDevice: Bool = true) {
        self.id = id
        self.text = text
        self.achievableOnDevice = achievableOnDevice
    }
}

// MARK: - Contenuto del manifesto

/// Contenuto di dominio dell'onboarding-manifesto e della schermata dei non-goals.
public struct ManifestContent: Equatable, Sendable {
    /// Titolo/promessa d'apertura dell'onboarding.
    public let headline: String
    /// Le promesse positive (cosa facciamo).
    public let promises: [ManifestPromise]
    /// Le rinunce dichiarate (cosa NON facciamo).
    public let nonGoals: [NonGoal]

    public init(headline: String, promises: [ManifestPromise], nonGoals: [NonGoal]) {
        self.headline = headline
        self.promises = promises
        self.nonGoals = nonGoals
    }

    /// Gli id dei non-goals presenti. Usato dall'oracolo (AC-100-1).
    public var nonGoalIDs: Set<NonGoalID> { Set(nonGoals.map(\.id)) }

    /// Vero se qualche non-goal promette una capacità invece di rinunciarvi:
    /// deve restare FALSO (AC-100-2, coerenza col manifesto).
    public var anyNonGoalClaimsCapability: Bool {
        nonGoals.contains { $0.claimsCapability }
    }

    /// Vero se ogni promessa positiva è mantenibile on-device (AC-100-2): non si
    /// promette nulla che il sandbox iOS renda impossibile.
    public var allPromisesAchievableOnDevice: Bool {
        promises.allSatisfy(\.achievableOnDevice)
    }
}

// MARK: - Contenuto canonico

public extension ManifestContent {
    /// Il contenuto canonico del manifesto, derivato voce per voce dal
    /// VISION-AND-CONSTRAINTS §4 (non-goals) e dal manifesto (promesse).
    static let angavu = ManifestContent(
        headline: "Numeri veri. Niente trucchi. I tuoi dati restano sul telefono.",
        promises: [
            ManifestPromise(id: .offline, text: "Funziona offline: tutto avviene sul dispositivo."),
            ManifestPromise(id: .noAds, text: "Niente pubblicità, niente notifiche promo."),
            ManifestPromise(id: .realNumbers, text: "Numeri veri, con i caveat quando servono."),
            ManifestPromise(id: .safetyNet, text: "Rete di sicurezza: anteprima obbligatoria prima di eliminare."),
            ManifestPromise(id: .onePayment, text: "In futuro il Pro sarà un pagamento unico, mai un abbonamento.")
        ],
        nonGoals: [
            NonGoal(
                id: .systemCacheCleaning,
                text: "Niente cache di sistema o \"junk\" di altre app",
                rationale: "Il sandbox di iOS non lo permette. Non lo simuliamo: lo diciamo."
            ),
            NonGoal(
                id: .otherAppFolders,
                text: "Niente cartelle di altre app (WhatsApp, Telegram)",
                rationale: "Su iOS quelle cartelle non sono accessibili a nessuna app."
            ),
            NonGoal(
                id: .resourceBooster,
                text: "Niente \"booster\" di RAM, CPU o batteria",
                rationale: "Sarebbe un placebo. Preferiamo essere onesti."
            ),
            NonGoal(
                id: .antivirus,
                text: "Niente \"antivirus\"",
                rationale: "Non è fattibile né utile in questo contesto."
            ),
            NonGoal(
                id: .noAds,
                text: "No ads, no scare tactics, no numeri gonfiati",
                rationale: "La categoria \"cleaner\" ne è piena. Noi no, mai."
            ),
            NonGoal(
                id: .zeroBackend,
                text: "Zero backend: nessun dato lascia il device",
                rationale: "Nessun server, nessuna sync cloud, nessuna telemetria."
            ),
            NonGoal(
                id: .iapInV1,
                text: "Nessun acquisto in-app nella v1",
                rationale: "Si parte tutto-free; il Pro arriva dopo, aggiungendo, mai togliendo."
            ),
            NonGoal(
                id: .advancedFeaturesDeferred,
                text: "Niente vault cifrato, widget o Shortcuts (per ora)",
                rationale: "Arriveranno dopo, sopra basi solide."
            )
        ]
    )
}
