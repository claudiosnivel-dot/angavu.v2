// AngavuDomain — logica pura di Angavu iOS.
//
// Invariante di altitudine (00-INDEX §1bis): questo modulo NON importa
// PhotoKit/Vision/AVFoundation né dipende da AngavuData/AngavuFeatures/App.
// Contiene solo tipi e regole (cluster, scelta, esiti) testabili senza device.

/// Marcatore di modulo: prova osservabile che il target è stato prodotto e
/// linkato. Usato dai test di struttura (AC-001-1) come simbolo di riferimento.
public enum AngavuDomain {
    /// Nome canonico del modulo.
    public static let moduleName = "AngavuDomain"
}
