// CompressionView+Sections — sezioni di rendering della schermata «Comprimi video»
// (flusso a BATCH, B-2).
//
// Estensione di `CompressionView` (guscio UI): solo SwiftUI, guardata
// `#if canImport(SwiftUI)`. Separata dal core per tenere ogni file leggibile;
// nessuna logica — le decisioni stanno nei layer puri (`BatchCompression*`,
// `BatchCompressionPresentation`, testati). Strato compilato-ma-non-testato (L-COL-006).
#if canImport(SwiftUI)
import AngavuDomain
import AngavuData
import SwiftUI

extension CompressionView {

    // MARK: Selezione (lista + preset + stima + CTA)

    @ViewBuilder
    func selectingSection(_ candidates: [CompressionCandidate]) -> some View {
        presetPicker
        capNotice
        candidateList(candidates)
        selectionSummaryAndCTA
    }

    // MARK: Scelta del preset

    var presetPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Qualità della ricodifica")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Picker("Preset", selection: presetBinding) {
                ForEach(HEVCPreset.allCases, id: \.self) { option in
                    Text(presetLabel(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    func presetLabel(_ preset: HEVCPreset) -> String {
        switch preset {
        case .highQuality: return "Alta qualità"
        case .balanced: return "Bilanciato"
        }
    }

    // MARK: Avviso onesto del cap della stima

    @ViewBuilder
    var capNotice: some View {
        if let notice = BatchCompressionCopy.estimateCapNotice(
            shown: vm.estimatedCount, totalCandidates: vm.totalCandidateCount
        ) {
            Label {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle").foregroundStyle(AuroraBrand.accentAzzurro)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: .rect(cornerRadius: 12))
        }
    }

    // MARK: Lista dei video candidati (dati veri + miniature + selezione)

    func candidateList(_ candidates: [CompressionCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Video nella libreria")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(vm.selection.selectedCount == candidates.count ? "Deseleziona tutto" : "Seleziona tutto") {
                    if vm.selection.selectedCount == candidates.count { vm.selectNone() } else { vm.selectAll() }
                }
                .font(.subheadline)
            }
            VStack(spacing: 0) {
                ForEach(candidates) { candidate in
                    candidateRowButton(candidate)
                    if candidate.id != candidates.last?.id { Divider() }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: .rect(cornerRadius: 12))
        }
    }

    private func candidateRowButton(_ candidate: CompressionCandidate) -> some View {
        Button {
            vm.toggle(candidate.id)
        } label: {
            BatchCandidateRow(
                candidate: candidate,
                isSelected: vm.selection.selected.contains(candidate.id),
                estimatedSaving: savingBytes(for: candidate.id),
                isUnestimable: vm.estimate.unestimableIds.contains(candidate.id),
                thumbnailProvider: environment.thumbnailProvider
            )
            .frame(minHeight: 44)   // tap target ≥44pt sull'intera riga (R-04)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Tocca per selezionare o deselezionare")
    }

    /// Risparmio stimato del video, o `nil` se non stimabile / fuori dal cap.
    private func savingBytes(for id: String) -> Int64? {
        vm.estimate.perItem.first { $0.id == id }?.saving.bytes
    }

    // MARK: Riepilogo selezione + CTA

    var selectionSummaryAndCTA: some View {
        let summary = vm.summary
        return VStack(alignment: .leading, spacing: 12) {
            if summary.selectedEstimatedSavingBytes > 0 {
                Text("~ \(formatCompressionBytes(summary.selectedEstimatedSavingBytes))")
                    .auroraHeroNumber()
                    .foregroundStyle(AuroraBrand.gradient)
                Text("risparmio stimato per i \(summary.selectedCount) selezionati")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            if summary.selectedUnestimableCount > 0 {
                Text("\(summary.selectedUnestimableCount) selezionati senza stima "
                    + "(durata/bitrate non leggibili): compressi comunque, senza numero inventato.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                pendingBatchConfirmation = true
            } label: {
                Text(summary.canStart
                    ? "Comprimi \(summary.selectedCount) selezionati"
                    : "Seleziona i video da comprimere")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AuroraBrand.gradient, in: .capsule)
                    .foregroundStyle(AuroraBrand.onGradient)
            }
            .disabled(!summary.canStart)
            .opacity(summary.canStart ? 1 : 0.5)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }

    // MARK: Esecuzione (progresso determinato + annulla)

    @ViewBuilder
    var runningSection: some View {
        if let run = vm.run {
            let summary = BatchCompressionRunSummary(run: run)
            VStack(alignment: .leading, spacing: 14) {
                Text("Compressione in corso…").font(.headline)
                // Progresso DETERMINATO X/N (mai una rotella indeterminata).
                ProgressView(value: Double(summary.processed), total: Double(max(summary.total, 1))) {
                    Text("\(summary.processed) di \(summary.total)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("Ricodifica HEVC sul dispositivo. Gli originali sono intatti finché "
                    + "non vengono sostituiti; nulla lascia il telefono.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    vm.requestCancel()
                } label: {
                    Label("Annulla", systemImage: "stop.circle")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: .rect(cornerRadius: 16))
        }
    }

    // MARK: Conclusione (esiti aggregati + rete di sicurezza)

    @ViewBuilder
    var doneSection: some View {
        if let run = vm.run {
            let summary = BatchCompressionRunSummary(run: run)
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(summary.succeeded > 0 ? "Compressione completata" : "Nessun video compresso")
                        .font(.headline)
                } icon: {
                    Image(systemName: summary.succeeded > 0 ? "checkmark.seal" : "exclamationmark.triangle")
                        .foregroundStyle(summary.succeeded > 0 ? AuroraBrand.accentAzzurro : AuroraBrand.accentFucsia)
                        .accessibilityHidden(true)
                }
                doneOutcomeLines(summary)
                if summary.succeeded > 0 {
                    safetyNoteLabel
                }
                Button {
                    resetBatch()
                } label: {
                    Label("Torna ai video", systemImage: "chevron.backward")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: .rect(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private func doneOutcomeLines(_ summary: BatchCompressionRunSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if summary.succeeded > 0 {
                Text("\(summary.succeeded) compressi · nuova dimensione totale "
                    + "\(formatCompressionBytes(summary.totalOutputBytes))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if summary.failed > 0 {
                Text("\(summary.failed) non riusciti (originali intatti)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if summary.cancelled > 0 {
                Text("\(summary.cancelled) annullati (non processati)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var safetyNoteLabel: some View {
        Label {
            Text(BatchCompressionCopy.safetyNet)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "arrow.uturn.backward.circle")
                .foregroundStyle(AuroraBrand.accentAzzurro)
                .accessibilityHidden(true)
        }
    }

    // MARK: Stati «nessun video» e errore d'indice

    var noVideosCard: some View {
        ContentUnavailableView(
            "Nessun video da comprimere",
            systemImage: "film",
            description: Text("La tua libreria indicizzata non contiene video. Se hai appena "
                + "concesso l'accesso, esegui prima un'analisi dalla Home.")
        )
    }

    func indexFailedCard(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Analisi non disponibile", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button {
                loadPhase = .loading
                Task { await loadIfNeeded(force: true) }
            } label: {
                Label("Riprova", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }
}

/// Riga di un video candidato al batch: miniatura reale (A-1, «mai alla cieca»),
/// dimensione vera (marcata se stima), risparmio stimato o «non stimabile», e stato
/// di selezione. Il `localIdentifier` non è mai mostrato né letto.
private struct BatchCandidateRow: View {
    let candidate: CompressionCandidate
    let isSelected: Bool
    let estimatedSaving: Int64?
    let isUnestimable: Bool
    let thumbnailProvider: any AssetThumbnailProviding

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? AuroraBrand.accentViola : Color.secondary)
                .imageScale(.large)
                .accessibilityHidden(true)
            RowThumbnailView(
                provider: thumbnailProvider,
                id: candidate.id,
                placeholderSymbol: "film",
                tint: AuroraBrand.accentViola
            )
            VStack(alignment: .leading, spacing: 2) {
                Text("Video").font(.body)
                savingLine
            }
            Spacer()
            Text(candidate.isSizeEstimated
                ? "~ \(formatCompressionBytes(candidate.originalBytes))"
                : formatCompressionBytes(candidate.originalBytes))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(candidate.accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var savingLine: some View {
        if let estimatedSaving {
            Text("~ \(formatCompressionBytes(estimatedSaving)) risparmio stimato")
                .font(.caption).foregroundStyle(.secondary)
        } else if isUnestimable {
            Text("risparmio non stimabile")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var accessibilityValue: String {
        let size = candidate.accessibilityValue(
            formattedBytes: formatCompressionBytes(candidate.originalBytes))
        let saving = estimatedSaving.map { ", risparmio stimato \(formatCompressionBytes($0))" }
            ?? (isUnestimable ? ", risparmio non stimabile" : "")
        return size + saving
    }
}
#endif
