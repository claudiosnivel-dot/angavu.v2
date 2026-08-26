import Foundation

// D-1 (Domain puro) — Formattazione della freschezza di un risultato cachato.
//
// Dato l'ETÀ di un dato (secondi trascorsi da quando è stato calcolato), produce
// l'etichetta umana "aggiornato …" per il badge di categoria. È l'ORACOLO
// testabile: nessun `Date.now`, nessun accesso all'orologio — l'età è passata dal
// chiamante (la View calcola `now − timestamp`; quel `Date()` è View-level, non
// coperto, L-COL-006). Onestà (manifesto: numeri veri): un dato non è mai
// spacciato per fresco; oltre il minuto l'età è dichiarata esplicitamente, così
// l'utente sa se ciò che vede è recente o va ri-analizzato.
public enum RelativeFreshness {

    private static let minute: Double = 60
    private static let hour: Double = 3600
    private static let day: Double = 86_400

    /// Etichetta relativa per un'età in secondi. Le età negative (orologio
    /// incoerente, es. cambio di fuso) sono trattate come "ora": mai un numero
    /// assurdo. Granularità crescente: ora → minuti → ore → giorni.
    public static func label(ageSeconds: Double) -> String {
        let age = max(0, ageSeconds)
        if age < minute { return "aggiornato ora" }
        if age < hour {
            let minutes = Int(age / minute)
            return "aggiornato \(minutes) min fa"
        }
        if age < day {
            let hours = Int(age / hour)
            return hours == 1 ? "aggiornato 1 ora fa" : "aggiornato \(hours) ore fa"
        }
        let days = Int(age / day)
        return days == 1 ? "aggiornato 1 giorno fa" : "aggiornato \(days) giorni fa"
    }
}
