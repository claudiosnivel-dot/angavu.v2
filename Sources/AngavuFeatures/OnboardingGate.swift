// OnboardingGate — decisione PURA "mostrare l'onboarding-manifesto?" e chiave di
// persistenza dell'onboarding completato. R-00: l'onboarding deve comparire UNA
// SOLA VOLTA per installazione. La persistenza reale vive in `@AppStorage`
// (App/ContentView.swift); questo tipo è l'ORACOLO della scelta e la fonte unica
// del nome della chiave, così View e test non divergono. Nessun import SwiftUI:
// verificabile su Linux (L-COL-006).

/// La logica di gating dell'onboarding, indipendente dalla piattaforma.
public enum OnboardingGate {
    /// Chiave di persistenza del flag "onboarding completato". Unica fonte del
    /// nome: `@AppStorage` e i test la riusano invece di ripetere il letterale.
    public static let didFinishStorageKey = "didFinishOnboarding"

    /// Decisione PURA: mostrare l'onboarding-manifesto? Sì finché non è stato
    /// completato (persistito) almeno una volta. Prima di R-00 il flag era
    /// `@State`, azzerato a ogni cold-launch → l'onboarding ricompariva a ogni
    /// avvio; ora la persistenza lo rende un evento unico per installazione.
    public static func shouldPresentOnboarding(hasFinishedOnboarding: Bool) -> Bool {
        !hasFinishedOnboarding
    }
}
