import AngavuDomain

// Tema: mapping della scelta pura del Domain al `ColorScheme` di SwiftUI, chiave
// di persistenza condivisa e schermata di selezione. Guardato `canImport(SwiftUI)`.

/// Chiave di persistenza della preferenza tema (UserDefaults / @AppStorage).
public enum ThemePreference {
    public static let storageKey = "angavu.theme"
}

#if canImport(SwiftUI)
import SwiftUI

extension ThemeChoice {
    /// `nil` = segui il sistema; altrimenti forza chiaro o scuro.
    public var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Etichetta localizzata (IT) per la UI.
    public var label: String {
        switch self {
        case .system: return "Sistema"
        case .light: return "Chiaro"
        case .dark: return "Scuro"
        }
    }

    /// SF Symbol rappresentativo.
    public var symbolName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

/// Schermata di selezione del tema (Sistema / Chiaro / Scuro).
public struct ThemeSettingsView: View {
    @Binding private var choice: ThemeChoice

    public init(choice: Binding<ThemeChoice>) {
        self._choice = choice
    }

    public var body: some View {
        Form {
            Section {
                Picker("Aspetto", selection: $choice) {
                    ForEach(ThemeChoice.allCases, id: \.self) { option in
                        Label(option.label, systemImage: option.symbolName).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Aspetto")
            } footer: {
                Text("«Sistema» segue l'impostazione di iOS. Il tema Aurora si adatta a "
                    + "chiaro e scuro con gli stessi colori d'identità.")
            }
        }
        .navigationTitle("Tema")
    }
}
#endif
