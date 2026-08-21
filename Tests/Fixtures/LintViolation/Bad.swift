// Fixture SPORCA di proposito (AC-003-2). Non fa parte del package: sta sotto
// Tests/Fixtures (escluso in .swiftlint.yml). Viola le regole di T-003:
//  • force-unwrap su path critico (force_unwrapping, severity error);
//  • dichiarazione privata non usata (unused_declaration, dead-code).
import Foundation

struct Bad {
    // Dichiarazione non usata: la regola dead-code deve segnalarla.
    private let neverUsed = 42

    func explode(_ value: Int?) -> Int {
        // Force-unwrap proibito.
        return value!
    }
}
