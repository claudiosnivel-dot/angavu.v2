// CompressionView+Sections — sezioni di rendering della schermata «Comprimi video».
//
// Estensione di `CompressionView` (guscio UI): solo SwiftUI, guardata
// `#if canImport(SwiftUI)`. Separata dal core (`CompressionView.swift`) per tenere
// ogni file leggibile; nessuna logica — le decisioni stanno in
// `CompressionPresentation` (puro, testato). Strato compilato-ma-non-testato (L-COL-006).
#if canImport(SwiftUI)
import AngavuDomain
import SwiftUI

extension CompressionView {

    // MARK: Scelta del preset

    var presetPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Qualità della ricodifica")
                .font(.headline)
            Picker("Preset", selection: $preset) {
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

    // MARK: Lista dei video candidati (dati veri dall'indice)

    func candidateList(_ candidates: [CompressionCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Video nella libreria")
                .font(.headline)
            if let notice = specNotice {
                Label {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle").foregroundStyle(AuroraBrand.accentAzzurro)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: .rect(cornerRadius: 12))
            }
            VStack(spacing: 0) {
                ForEach(candidates) { candidate in
                    Button {
                        estimate(for: candidate)
                    } label: {
                        CompressionCandidateRow(candidate: candidate)
                    }
                    .buttonStyle(.plain)
                    if candidate.id != candidates.last?.id { Divider() }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: .rect(cornerRadius: 12))
        }
    }

    // MARK: Stima del risparmio (marcata stima)

    func estimateCard(_ pres: CompressionPresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("~ \(formatCompressionBytes(pres.estimatedSavingBytes ?? 0))")
                .auroraHeroNumber()
                .foregroundStyle(AuroraBrand.gradient)
            Text("risparmio stimato")
                .font(.headline)
                .foregroundStyle(.secondary)
            if let detail = pres.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if pres.offersConsent {
                Button {
                    grantConsent()
                } label: {
                    Text("Acconsento a comprimere")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AuroraBrand.gradient, in: .capsule)
                        .foregroundStyle(.white)
                }
                .padding(.top, 4)
            }
            Button("Scegli un altro video") { reset() }
                .font(.subheadline)
                .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }

    // MARK: Consenso registrato → avvio (dietro anteprima)

    func consentedCard(_ pres: CompressionPresentation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(pres.title).font(.headline)
            } icon: {
                Image(systemName: "checkmark.circle").foregroundStyle(AuroraBrand.accentAzzurro)
            }
            if let detail = pres.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if pres.offersCompression {
                Button {
                    pendingConfirmation = selected
                } label: {
                    Text("Comprimi ora")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AuroraBrand.gradient, in: .capsule)
                        .foregroundStyle(.white)
                }
            }
            Button("Annulla") { reset() }
                .font(.subheadline)
                .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }

    // MARK: Lavorazione in corso (annullabile)

    func workingCard(_ pres: CompressionPresentation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ProgressView().progressViewStyle(.circular)
                Text(pres.title).font(.headline)
            }
            if let detail = pres.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                cancellation.cancel()
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

    // MARK: Completato

    func doneCard(_ pres: CompressionPresentation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(pres.title).font(.headline)
            } icon: {
                Image(systemName: "checkmark.seal").foregroundStyle(AuroraBrand.accentAzzurro)
            }
            if let output = pres.compressedOutputBytes {
                Text("Versione compressa: \(formatCompressionBytes(output))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let note = pres.safetyNote {
                Label {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .foregroundStyle(AuroraBrand.accentAzzurro)
                }
            }
            Button {
                reset()
            } label: {
                Label("Comprimi un altro video", systemImage: "plus.circle")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }

    // MARK: Stati terminali (annullato / fallito)

    func terminalCard(
        _ pres: CompressionPresentation,
        symbol: String,
        tint: Color,
        retry: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(pres.detail ?? pres.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            HStack(spacing: 12) {
                if retry, let candidate = selected {
                    Button {
                        estimate(for: candidate)
                    } label: {
                        Label("Riprova", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
                Button("Scegli un altro video") { reset() }
                    .font(.subheadline)
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }

    // MARK: Stati «nessun video» e errore d'indice

    var noVideosCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Nessun video da comprimere")
                    .font(.headline)
            } icon: {
                Image(systemName: "film").foregroundStyle(AuroraBrand.accentAzzurro)
            }
            Text("La tua libreria indicizzata non contiene video. Se hai appena concesso "
                + "l'accesso, esegui prima un'analisi dalla Home.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }

    func indexFailedCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(AuroraBrand.accentFucsia)
            }
            Button {
                loadPhase = .loading
                loadIfNeeded(force: true)
            } label: {
                Label("Riprova", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }
}

/// Riga di un video candidato: id e byte reali (marcati se stima).
private struct CompressionCandidateRow: View {
    let candidate: CompressionCandidate

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "film")
                .foregroundStyle(AuroraBrand.accentViola)
            Text(candidate.id)
                .font(.body.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(candidate.isSizeEstimated
                    ? "~ \(formatCompressionBytes(candidate.originalBytes))"
                    : formatCompressionBytes(candidate.originalBytes))
                    .font(.body.monospacedDigit())
                if candidate.isSizeEstimated {
                    Text("stima").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
#endif
