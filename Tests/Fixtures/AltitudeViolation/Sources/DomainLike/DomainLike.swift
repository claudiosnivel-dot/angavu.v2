// Modulo "Domain-like" senza dipendenza dichiarata verso DataLike.
// L'import qui sotto è PROIBITO dall'altitudine: la build deve fallire.
import DataLike

public enum DomainLike {
    public static let seen = DataLike.marker
}
