// DashboardView — la schermata «Numeri veri» (guscio UI, schermata 2).
//
// Presenta la dashboard cablata coi dati veri (`DashboardViewModel`, T-112): righe
// per categoria coi byte reali (exact/estimated SEPARATI, la stima marcata), spazio
// recuperabile con la distinzione libreria vs device ORA (caveat iCloud), banner
// accesso limited col totale dichiarato parziale, e lo stato d'errore con motivo
// esplicito + "Riprova". Nessun numero gonfiato.
//
// Le decisioni di presentazione vivono in `DashboardPresentation` (puro, testato);
// qui c'è solo il rendering SwiftUI, guardato `#if canImport(SwiftUI)` — l'unico
// strato compilato-ma-non-testato (L-COL-006). Il view-model arriva già cablato
// dall'`AppEnvironment` iniettato: nessun singleton nascosto.
#if canImport(SwiftUI)
import AngavuDomain
import SwiftUI

/// Formatta i byte in stile file (KB/MB/GB), rispettando la locale.
private func formatDashboardBytes(_ bytes: Int64) -> String {
    bytes.formatted(.byteCount(style: .file))
}

public struct DashboardView: View {
    @State var vm: DashboardViewModel
    // Conservato per costruire le schermate a valle (review categorie) con lo
    // stesso grafo di dipendenze iniettato: nessun singleton nascosto. Interno
    // (non private) così le sezioni in `DashboardView+Sections.swift` vi accedono.
    let environment: AppEnvironment
    // P0-1: cache dei risultati posseduta SOPRA la view (da `App/`). Interna così le
    // sezioni (report) possono propagarla alle schermate a valle.
    let store: AnalysisResultsStore

    public init(environment: AppEnvironment, store: AnalysisResultsStore) {
        self.environment = environment
        self.store = store
        _vm = State(initialValue: DashboardViewModel(environment: environment))
    }

    var presentation: DashboardPresentation {
        DashboardPresentation(state: vm.state)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AuroraBrand.glow.ignoresSafeArea())
        .navigationTitle("Numeri veri")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            // P0-1: cache SOPRA la view. Se il risultato è già stato calcolato
            // (navigazione/back o ritorno dal background), lo si applica senza
            // ricalcolare; altrimenti si legge FUORI dal main thread e si memorizza.
            // «Riprova»/ricalcolo espliciti invalidano la cache a monte.
            if case .idle = vm.state {
                if let cached: DashboardScreen = store.value(for: .dashboard) {
                    vm.present(cached)
                } else if case .ready(let screen) = await vm.load() {
                    store.set(screen, for: .dashboard)
                }
            }

            // FSE-G1 (strategia B) — RESIDENZA DIFFERITA. La scansione atterra col
            // caveat device (la misura per-asset è I/O pesante, fuori dal percorso
            // obbligatorio). Se la cifra device è ancora un caveat (optimize-storage
            // attivo, misura non ancora fatta), la si misura ORA in background e si
            // aggiorna la dashboard col numero reale, ricachandolo — così tornare sulla
            // schermata mostra il numero, non di nuovo il caveat. `measureResidency` gira
            // off-main a blocchi cancellabili (nessun freeze). Copertura (L-COL-006):
            // l'aggregazione è coperta dall'oracolo; il probe PhotoKit reale è device-only.
            if case .ready(let screen) = vm.state, screen.reclaimable.deviceSpaceIsIndeterminate {
                if case .ready(let updated) = await vm.measureResidency() {
                    store.set(updated, for: .dashboard)
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation.title)
                .font(.largeTitle.weight(.bold))
                // R-09 parsimonia: un solo gradiente per schermata → la cifra-hero
                // vince, il titolo passa al colore di testo primario.
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            if let detail = presentation.detail, presentation.kind != .failed {
                Text(detail)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 12)
    }

    // MARK: Contenuto per classe di stato

    @ViewBuilder
    private var content: some View {
        let pres = presentation
        switch pres.kind {
        case .idle:
            ProgressView("Calcolo dei numeri veri…").progressViewStyle(.circular)
        case .ready:
            if pres.showsLimitedBanner { limitedBanner }
            if let reclaimable = pres.reclaimable { reclaimableCard(reclaimable) }
            categoriesList(pres.categoryRows)
            cleanupSection
            compressionSection
            extraDomainsSection
            reportSection
        case .failed:
            failedCard(pres)
        }
    }

    // MARK: Banner accesso limited

    private var limitedBanner: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Conteggio parziale")
                    .font(.headline)
                Text("Hai concesso l'accesso solo ad alcune foto. Abilita l'accesso completo per numeri completi.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(AuroraBrand.accentAzzurro)
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 12))
    }

    // MARK: Spazio recuperabile (libreria vs device ORA)

    private func reclaimableCard(_ summary: DashboardPresentation.ReclaimableSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Hero onesto: la cifra SOLO se la residenza è determinabile; altrimenti
            // un caveat, mai un numero fabbricato (P0-3, manifesto).
            if summary.deviceSpaceIsIndeterminate {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spazio sul telefono: non determinabile ora")
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Angavu non può stimare con onestà quanto si libera subito sul telefono. "
                        + "Vedi lo spazio in libreria qui sotto.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(formatDashboardBytes(summary.deviceBytesNow))
                        .auroraHeroNumber()
                        .foregroundStyle(AuroraBrand.gradient)
                    Text("liberabili sul telefono ora")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("\(formatDashboardBytes(summary.deviceBytesNow)) liberabili sul telefono ora")
            }

            // P0-4: lo "spazio in libreria" (il grande numero che include iCloud) è
            // una riga SEPARATA ed etichettata, non spacciata per spazio-telefono.
            libraryRow(summary)

            if summary.iCloudCaveat {
                Label {
                    Text("Parte degli originali è in iCloud. Eliminando liberi la libreria, "
                        + "non subito lo spazio sul telefono.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "icloud")
                        .foregroundStyle(AuroraBrand.accentBlu)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }

    private func libraryRow(_ summary: DashboardPresentation.ReclaimableSummary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Spazio in libreria (include iCloud)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(formatDashboardBytes(summary.libraryBytes))
                .font(.subheadline.monospacedDigit())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spazio in libreria, include iCloud")
        .accessibilityValue(formatDashboardBytes(summary.libraryBytes))
    }

    // MARK: Righe per categoria

    private func categoriesList(_ rows: [DashboardPresentation.CategoryRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows, id: \.category) { row in
                DashboardCategoryRow(row: row)
            }
        }
    }

    // MARK: Stato d'errore

    private func failedCard(_ pres: DashboardPresentation) -> some View {
        ContentUnavailableView {
            Label("Numeri non disponibili", systemImage: "exclamationmark.triangle")
        } description: {
            Text(pres.detail ?? "Errore sconosciuto.")
        } actions: {
            if pres.showsRetry {
                Button {
                    Task { await vm.load() }
                } label: {
                    Label("Riprova", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

/// Riga di una categoria: conteggio, byte, marcatura della stima se presente.
private struct DashboardCategoryRow: View {
    let row: DashboardPresentation.CategoryRow

    var body: some View {
        // R-08: alle accessibility sizes il layout a due colonne si comprime;
        // ViewThatFits ripiega su una colonna (valore sotto il titolo) prima di
        // troncare. Stessi accessibility modifier in entrambi i branch.
        ViewThatFits(in: .horizontal) {
            HStack {
                titleColumn
                Spacer(minLength: 12)
                valueColumn
            }
            VStack(alignment: .leading, spacing: 4) {
                titleColumn
                valueColumn
            }
        }
        .padding(.vertical, 4)
        // VoiceOver: un solo elemento leggibile (titolo + conteggio/byte/stima),
        // dal layer puro — non i 3-4 frammenti che i figli produrrebbero.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityValue(row.accessibilityValue(formattedBytes: formatDashboardBytes(row.totalBytes)))
    }

    private var titleColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.title).font(.headline)
                .lineLimit(2)
                .allowsTightening(true)
            Text("\(row.count) elementi")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var valueColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.isEstimated
                ? "~ \(formatDashboardBytes(row.totalBytes))"
                : formatDashboardBytes(row.totalBytes))
                .font(.body.monospacedDigit())
                .lineLimit(1)
            if row.isEstimated {
                Text("stima")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
