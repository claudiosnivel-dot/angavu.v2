import AngavuDomain
import Foundation

// FSE-K1 — Decisione di cache della review di categoria.
//
// Estratto dalla `CategoryReviewView` (View-level, non testabile) il PUNTO DI
// DECISIONE «servita dalla cache o composta dal rilevatore»: qui è puro e oracolabile
// (AC-FSE-K1-2: uno store idratato dalla persistenza serve la categoria con 0
// invocazioni dei rilevatori). La View usa `cached(for:in:)` per il cache hit e
// compone (off-main, `composeReviewData`) solo sul miss; l'oracolo
// (`StoreHydrationTests`) rispecchia lo stesso cache-aside con un rilevatore-spia.

extension CategoryReviewSource {
    /// Cache hit tipizzato per la categoria, se presente nello store; `nil` sul miss.
    static func cached(for category: CleanupCategory, in store: AnalysisResultsStore) -> CategoryReviewData? {
        store.value(for: .category(category.rawValue))
    }
}
