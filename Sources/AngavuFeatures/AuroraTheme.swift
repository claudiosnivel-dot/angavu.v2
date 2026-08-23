// AuroraTheme — i brand token d'IDENTITÀ portati dall'Android, ricostruiti
// nativi per HIG (11-ui-shell.md, promemoria design).
//
// Cosa si porta: il *carattere* del brand — la palette "Aurora" (accenti
// viola/fucsia/blu/azzurro) e il gradiente d'accento blu→viola→fucsia usato con
// parsimonia (wordmark, CTA, cifre-hero), più il bagliore radiale in testa alle
// schermate. Cosa NON si porta: lo scaffolding Material 3 (color scheme roles,
// dynamic color) — su iOS i fondi/superfici sono i colori SEMANTICI di sistema
// (`.background`, `.secondary`, ecc.), che rispettano dark mode e Dynamic Type
// senza reinventarli. Sorgente Android: `ui/theme/Color.kt`.
#if canImport(SwiftUI)
import SwiftUI

/// I colori d'identità del brand Angavu. Solo l'accento è "di brand"; tutto il
/// resto (fondi, testo secondario) resta ai colori semantici di iOS.
public enum AuroraBrand {
    /// Accento primario: viola. Adatta la luminosità al color scheme del sistema.
    public static let accentViola = Color(light: 0x7C5CFC, dark: 0xA78BFF)
    /// Accento secondario: blu.
    public static let accentBlu = Color(light: 0x4C7DFF, dark: 0x7BA3FF)
    /// Accento terziario: fucsia.
    public static let accentFucsia = Color(light: 0xDD4FD5, dark: 0xF07BE4)
    /// Accento di supporto: azzurro.
    public static let accentAzzurro = Color(light: 0x45C6F5, dark: 0x5FD4FA)

    /// Il gradiente d'accento del brand (blu→viola→fucsia). Uso parsimonioso:
    /// wordmark, CTA di conferma, cifra-hero — mai un fondo intero (§Spec Android).
    public static let gradient = LinearGradient(
        colors: [accentBlu, accentViola, accentFucsia],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Bagliore aurora radiale in testa alle schermate principali. Approssima il
    /// `radial-gradient` dell'Android: stesse coppie colore/alpha, tenue.
    public static let glow = RadialGradient(
        colors: [accentViola.opacity(0.30), accentFucsia.opacity(0.10), .clear],
        center: .top,
        startRadius: 0,
        endRadius: 320
    )
}

// MARK: - Cifra-hero (R-01): resa SwiftUI dello stile PURO `AuroraType.heroNumber`

extension AuroraType.HeroNumberStyle {
    /// Traduce il text style semantico in `Font.TextStyle` (scala col Dynamic Type).
    var fontTextStyle: Font.TextStyle {
        switch textStyle {
        case .largeTitle: return .largeTitle
        case .title: return .title
        }
    }

    /// Il `Font` risultante: text style semantico + design arrotondato + peso +
    /// cifre monospaziate. Nessuna dimensione fissa → scala col Dynamic Type.
    var font: Font {
        var font = Font.system(fontTextStyle, design: rounded ? .rounded : .default)
        if bold { font = font.weight(.bold) }
        if monospacedDigit { font = font.monospacedDigit() }
        return font
    }

    /// Il cap superiore del Dynamic Type tradotto in `DynamicTypeSize`.
    var maxDynamicTypeSize: DynamicTypeSize {
        switch dynamicTypeCap {
        case .accessibility3: return .accessibility3
        }
    }
}

/// Modificatore che applica lo stile cifra-hero del brand a un `Text`. La
/// `.contentTransition(.numericText())` (la cifra "scorre" invece di
/// teletrasportare quando cambia a runtime) è **gated su Reduce Motion** (R-06):
/// con Reduce Motion attivo il cambio è netto, senza animazione.
struct AuroraHeroNumberModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// La cifra cambia a runtime (idle→ready): abilita il transition numerico.
    let animatesChange: Bool

    func body(content: Content) -> some View {
        content
            .font(AuroraType.heroNumber.font)
            .dynamicTypeSize(...AuroraType.heroNumber.maxDynamicTypeSize)
            .contentTransition(animatesChange && !reduceMotion ? .numericText() : .identity)
    }
}

public extension View {
    /// Applica lo stile cifra-hero del brand (R-01): text style semantico
    /// scalabile con Dynamic Type, `design: .rounded`, `.bold`, `.monospacedDigit`
    /// e — se `animatesChange` e Reduce Motion è spento — `.contentTransition(.numericText())`.
    /// Sostituisce il `.font(.system(size: 44 …))` fisso su ogni cifra-hero.
    func auroraHeroNumber(animatesChange: Bool = true) -> some View {
        modifier(AuroraHeroNumberModifier(animatesChange: animatesChange))
    }
}

extension Color {
    /// Costruisce un colore che sceglie fra due esadecimali secondo il color
    /// scheme (light/dark) del sistema. Rispetta dark mode senza asset catalog.
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(rgbHex: hex)
        })
        #else
        // Piattaforme senza UIKit (host di build): usa la variante light.
        self.init(rgbHex: light)
        #endif
    }

    /// Colore opaco da un esadecimale RGB a 24 bit (0xRRGGBB).
    init(rgbHex hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

#if canImport(UIKit)
import UIKit

extension UIColor {
    /// `UIColor` opaco da un esadecimale RGB a 24 bit (0xRRGGBB).
    convenience init(rgbHex hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}
#endif
#endif
