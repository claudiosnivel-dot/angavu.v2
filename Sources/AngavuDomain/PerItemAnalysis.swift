import Foundation

// FSE-D2 — Motore d'analisi PER-ITEM iniettabile (seriale | concorrente).
//
// I rilevatori CPU/decodifica-bound hanno una FASE indipendente per elemento
// (nitidezza per foto, digest per candidato, qualità per membro, feature print per
// asset) e una FASE di combinazione ordine-dipendente (clustering greedy,
// raggruppamento per digest). Solo la prima è parallelizzabile senza toccare il
// determinismo; questo tipo la astrae dietro un `map` per-elemento che preserva
// l'ordine d'INPUT, così il risultato è IDENTICO col motore seriale o concorrente
// (parità di comportamento, AC-FSE-D2-1/2).
//
// Tipo CONCRETO di proposito (nessun protocollo esistenziale con metodo generico):
// il modo è un dato, `map` è un metodo generico normale che smista al motore
// seriale (`ChunkedAnalysis`-like) o concorrente (`ConcurrentAnalysis`, FSE-D1).
//
// Default SERIALE ovunque: i rilevatori restano identici finché un chiamante non
// inietta esplicitamente `.concurrent`. L'adozione concorrente in produzione è
// gated dalla validazione Thread Sanitizer on-device (§7): qui si consegna la
// capacità e la prova di parità, non un verde di performance (L-COL-006).
//
// Altitudine: Domain puro — solo Foundation. Nessun import di piattaforma.
public struct PerItemAnalysis {
    private enum Kind {
        case serial(chunkSize: Int)
        case concurrent(concurrency: Int)
    }
    private let kind: Kind

    /// Motore seriale a blocchi cancellabili (comportamento storico dei rilevatori).
    public static func serial(chunkSize: Int = 64) -> PerItemAnalysis {
        PerItemAnalysis(kind: .serial(chunkSize: max(1, chunkSize)))
    }

    /// Motore concorrente (FSE-D1): mappa in parallelo, limitato ai core attivi.
    public static func concurrent(concurrency: Int) -> PerItemAnalysis {
        PerItemAnalysis(kind: .concurrent(concurrency: max(1, concurrency)))
    }

    /// Mappa ogni elemento nel suo output, in ordine d'INPUT (deterministico),
    /// cancellabile, con progresso monotòno. L'esito è sempre esplicito
    /// (`completed | cancelled | failed`) col progresso raggiunto.
    public func map<Element, Output: Equatable>(
        _ items: [Element],
        cancellation: CancellationToken,
        progress: (AnalysisProgress) -> Void = { _ in },
        transform: @escaping (Element) throws -> Output
    ) -> AnalysisOutcome<[Output]> {
        switch kind {
        case .serial(let chunkSize):
            return serialMap(items, chunkSize: chunkSize, cancellation: cancellation,
                             progress: progress, transform: transform)
        case .concurrent(let concurrency):
            return ConcurrentAnalysis(concurrency: concurrency, transform: transform)
                .run(over: items, cancellation: cancellation, progress: progress)
        }
    }

    /// Map seriale a blocchi: stessi invarianti del motore concorrente (ordine
    /// d'input, cancellazione al confine del blocco, progresso monotòno) così i due
    /// percorsi sono intercambiabili a parità di risultato.
    ///
    /// FSE-H3 — Ogni `transform` gira dentro un `autoreleasepool`: i temporanei di
    /// decodifica/Vision di quell'elemento si rilasciano PRIMA del successivo, invece
    /// di accumularsi per l'intera passata (causa diretta del jetsam osservato al
    /// device-test). Parità col motore concorrente, che già avvolge ogni worker.
    /// L'`autoreleasepool` non cambia l'esito (output/progresso/cancellazione), solo il
    /// profilo di memoria (AC-FSE-H3-1); su Linux è un passaggio trasparente.
    private func serialMap<Element, Output: Equatable>(
        _ items: [Element],
        chunkSize: Int,
        cancellation: CancellationToken,
        progress: (AnalysisProgress) -> Void,
        transform: (Element) throws -> Output
    ) -> AnalysisOutcome<[Output]> {
        let total = items.count
        var outputs: [Output] = []
        outputs.reserveCapacity(total)
        progress(AnalysisProgress(processed: 0, total: total))

        var index = 0
        while index < total {
            if cancellation.isCancelled {
                return .cancelled(at: AnalysisProgress(processed: outputs.count, total: total))
            }
            let end = min(index + chunkSize, total)
            while index < end {
                do {
                    // autoreleasepool per elemento: rilascia i temporanei di questa
                    // decodifica prima della prossima (FSE-H3). `rethrows` → il do/catch
                    // sottostante intercetta comunque il fallimento del transform.
                    let output = try autoreleasepool { try transform(items[index]) }
                    outputs.append(output)
                } catch let failure as AnalysisFailure {
                    return .failed(reason: failure, at: AnalysisProgress(processed: outputs.count, total: total))
                } catch {
                    return .failed(
                        reason: AnalysisFailure(String(describing: error)),
                        at: AnalysisProgress(processed: outputs.count, total: total)
                    )
                }
                index += 1
            }
            progress(AnalysisProgress(processed: outputs.count, total: total))
        }
        return .completed(outputs)
    }
}
