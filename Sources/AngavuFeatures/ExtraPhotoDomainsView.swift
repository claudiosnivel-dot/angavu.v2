// ExtraPhotoDomainsView — la schermata «Contatti e calendari» (guscio UI).
//
// Presenta i due domini extra-foto cablati (`ContactsReviewViewModel` /
// `CalendarsReviewViewModel`, T-115): contatti duplicati da fondere e sottoscrizioni
// calendario sospette da rimuovere. Ogni azione è HUMAN-GATED (T-092): un tap apre
// una conferma esplicita e SOLO dopo la conferma l'adapter viene invocato; l'esito
// reale (applicato/annullato/fallito) è mostrato onestamente. I calendari locali non
// compaiono mai (la proposta li esclude a monte, T-091).
//
// Le decisioni di presentazione vivono in `ExtraPhotoDomainsPresentation` (puro,
// testato); qui c'è solo il rendering SwiftUI, guardato `#if canImport(SwiftUI)` —
// l'unico strato compilato-ma-non-testato (L-COL-006). Le porte arrivano
// dall'`AppEnvironment` iniettato (`ExtraDomainsPorts`): nessun singleton nascosto.
#if canImport(SwiftUI)
import AngavuDomain
import SwiftUI

public struct ExtraPhotoDomainsView: View {
    @State private var contactsVM: ContactsReviewViewModel
    @State private var calendarsVM: CalendarsReviewViewModel
    @State private var loadError: String?
    @State private var lastOutcome: ExtraActionOutcome?
    @State private var pendingContact: ContactMergeProposal?
    @State private var pendingCalendar: CalendarEntry?
    @State private var didLoad = false

    public init(ports: ExtraDomainsPorts) {
        _contactsVM = State(initialValue: ContactsReviewViewModel(
            provider: ports.contactsProvider, merger: ports.contactMerger
        ))
        _calendarsVM = State(initialValue: CalendarsReviewViewModel(
            provider: ports.calendarsProvider, remover: ports.calendarRemover
        ))
    }

    private var presentation: ExtraPhotoDomainsPresentation {
        ExtraPhotoDomainsPresentation(
            contactProposals: contactsVM.proposals,
            calendarProposal: calendarsVM.proposal,
            lastOutcome: lastOutcome
        )
    }

    public var body: some View {
        listContent
            .navigationTitle("Contatti e calendari")
            .onAppear(perform: loadOnce)
            .confirmationDialog(
            "Fondere i contatti duplicati?",
            isPresented: contactDialogBinding,
            presenting: pendingContact
        ) { proposal in
            Button("Fondi \(proposal.duplicates.count + 1) contatti", role: .destructive) {
                applyContact(proposal)
            }
            Button("Annulla", role: .cancel) {}
        } message: { _ in
            Text("Tieni il primario e vi unisci i duplicati. Reversibile solo a mano.")
        }
        .confirmationDialog(
            "Rimuovere la sottoscrizione?",
            isPresented: calendarDialogBinding,
            presenting: pendingCalendar
        ) { calendar in
            Button("Rimuovi «\(calendar.title)»", role: .destructive) {
                applyCalendar(calendar)
            }
            Button("Annulla", role: .cancel) {}
        } message: { _ in
            Text("Rimuove solo la sottoscrizione .ics, non i tuoi calendari.")
        }
    }

    private var listContent: some View {
        List {
            if let message = presentation.outcomeMessage { outcomeRow(message) }
            if let error = loadError { errorSection(error) }
            contactsSection
            calendarsSection
            safetySection
        }
    }

    private func loadOnce() {
        guard !didLoad else { return }
        didLoad = true
        load()
    }

    // MARK: Contatti

    private var contactsSection: some View {
        Section {
            if presentation.contactsEmpty {
                Text(presentation.contactsEmptyMessage).foregroundStyle(.secondary)
            } else {
                ForEach(contactsVM.proposals, id: \.primary.id) { proposal in
                    contactRow(ExtraPhotoDomainsPresentation.contactRow(for: proposal)) {
                        pendingContact = proposal
                    }
                }
            }
        } header: {
            Text(presentation.contactsTitle)
        } footer: {
            Text(presentation.contactsSubtitle)
        }
    }

    private func contactRow(
        _ row: ExtraPhotoDomainsPresentation.ContactRow,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName).font(.body)
                Text(row.detail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Fondi", action: action)
                .buttonStyle(.borderless)
                .foregroundStyle(AuroraBrand.accentViola)
        }
    }

    // MARK: Calendari

    private var calendarsSection: some View {
        Section {
            if presentation.calendarsEmpty {
                Text(presentation.calendarsEmptyMessage).foregroundStyle(.secondary)
            } else {
                ForEach(calendarsVM.proposal.removable, id: \.id) { calendar in
                    calendarRow(ExtraPhotoDomainsPresentation.calendarRow(for: calendar)) {
                        pendingCalendar = calendar
                    }
                }
            }
        } header: {
            Text(presentation.calendarsTitle)
        } footer: {
            Text(presentation.calendarsSubtitle)
        }
    }

    private func calendarRow(
        _ row: ExtraPhotoDomainsPresentation.CalendarRow,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(row.title).font(.body)
            Spacer()
            Button("Rimuovi", role: .destructive, action: action)
                .buttonStyle(.borderless)
        }
    }

    // MARK: Rete di sicurezza + esito + errore

    private var safetySection: some View {
        Section {
            Label(presentation.safetyNote, systemImage: "hand.raised")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func outcomeRow(_ message: String) -> some View {
        Label(message, systemImage: "checkmark.seal")
            .font(.subheadline)
            .foregroundStyle(AuroraBrand.accentAzzurro)
    }

    private func errorSection(_ message: String) -> some View {
        Section {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(AuroraBrand.accentFucsia)
            Button("Riprova") { load() }
        }
    }

    // MARK: Binding dei dialoghi

    private var contactDialogBinding: Binding<Bool> {
        Binding(get: { pendingContact != nil }, set: { if !$0 { pendingContact = nil } })
    }

    private var calendarDialogBinding: Binding<Bool> {
        Binding(get: { pendingCalendar != nil }, set: { if !$0 { pendingCalendar = nil } })
    }

    // MARK: Azioni

    private func load() {
        var failed: [String] = []
        do { try contactsVM.load() } catch { failed.append("contatti") }
        do { try calendarsVM.load() } catch { failed.append("calendari") }
        loadError = failed.isEmpty ? nil : "Accesso non riuscito: \(failed.joined(separator: ", "))."
    }

    private func applyContact(_ proposal: ContactMergeProposal) {
        Task {
            lastOutcome = await contactsVM.applyMerge(proposal, confirmed: true)
            load()
        }
    }

    private func applyCalendar(_ calendar: CalendarEntry) {
        Task {
            lastOutcome = await calendarsVM.applyRemoval(calendar, confirmed: true)
            load()
        }
    }
}
#endif
