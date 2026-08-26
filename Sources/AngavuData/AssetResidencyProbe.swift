import Foundation
import AngavuDomain

// P0-2b (Data) — Probe reale della residenza per-asset via PhotoKit.
//
// Misura, per un singolo asset, se il suo originale è servibile SENZA rete (residente
// sul device ORA) e con quanti byte. Implementa il port `AssetResidencyProbing`
// (Domain): l'aggregatore puro (`ResidencyAggregator`) lo esegue a blocchi
// cancellabili, off-main, così la misura su ~25k asset non rifreeza la UI.
//
// Onestà (manifesto "numeri veri"):
//  • `isNetworkAccessAllowed = false`: se l'originale non è sul device, PhotoKit NON
//    scarica da iCloud → l'asset conta **0 byte device** (in cloud, non libera spazio
//    locale eliminandolo). Zero rete, coerente con la baseline privacy.
//  • sincrono di proposito: attende in modo BLOCCANTE la richiesta async di PhotoKit
//    sul thread di fondo dell'aggregatore (mai il main). Il contratto del port
//    (sincrono) si compone col motore `ChunkedAnalysis` (sincrono, off-main).
//
// Copertura dichiarata (L-COL-006): adapter Apple-only → **compilato in CI, runtime
// sul device NON coperto** da unit test (richiede una libreria reale con iCloud
// "Ottimizza spazio"). L'oracolo dell'aggregazione è il test di dominio
// `ResidencyMeasurementTests`.

#if canImport(Photos)
import Photos

public struct PHAssetResidencyProbe: AssetResidencyProbing {
    /// Tempo massimo d'attesa per la risposta di PhotoKit su un singolo asset. Oltre
    /// il quale la residenza non è confermabile a buon mercato: si conta 0 (onestà
    /// conservativa — meglio sotto-stimare che gonfiare). Off-main, non blocca la UI.
    private let perAssetTimeout: TimeInterval

    public init(perAssetTimeout: TimeInterval = 10) {
        self.perAssetTimeout = perAssetTimeout
    }

    public func deviceResidentBytes(forLocalIdentifier id: String, libraryBytes: Int64) -> Int64 {
        guard libraryBytes > 0 else { return 0 }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = fetch.firstObject else { return 0 }

        let resources = PHAssetResource.assetResources(for: asset)
        guard let primary = primaryResource(for: asset, among: resources) else { return 0 }

        return isResidentWithoutNetwork(primary) ? libraryBytes : 0
    }

    /// Risorsa "piena" da testare per la residenza: preferisce l'originale foto/video,
    /// poi le varianti full-size, infine la prima disponibile.
    private func primaryResource(
        for asset: PHAsset,
        among resources: [PHAssetResource]
    ) -> PHAssetResource? {
        let preferred: [PHAssetResourceType] = asset.mediaType == .video
            ? [.video, .fullSizeVideo, .pairedVideo]
            : [.photo, .fullSizePhoto, .alternatePhoto]
        for type in preferred {
            if let match = resources.first(where: { $0.type == type }) { return match }
        }
        return resources.first
    }

    /// Vero se la risorsa è servibile senza rete: si richiedono i dati con
    /// `isNetworkAccessAllowed = false` e si conclude residente al primo byte reale
    /// (cancellando subito la richiesta per non leggere l'intero file). Un errore
    /// senza dati (originale in cloud) → non residente.
    private func isResidentWithoutNetwork(_ resource: PHAssetResource) -> Bool {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false

        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var resident = false
        var finished = false
        let manager = PHAssetResourceManager.default()

        let requestID = manager.requestData(
            for: resource,
            options: options,
            dataReceivedHandler: { data in
                guard !data.isEmpty else { return }
                lock.lock()
                let firstChunk = !resident
                resident = true
                let alreadyFinished = finished
                lock.unlock()
                // Primo byte reale ⇒ residente: basta, non serve leggere tutto il file.
                if firstChunk && !alreadyFinished { semaphore.signal() }
            },
            completionHandler: { _ in
                lock.lock()
                let alreadySignalled = resident
                finished = true
                lock.unlock()
                // Completato senza aver ricevuto dati ⇒ non residente (o errore rete).
                if !alreadySignalled { semaphore.signal() }
            }
        )

        let waited = semaphore.wait(timeout: .now() + perAssetTimeout)
        // Timeout: residenza non confermata → cancella e conta 0 (conservativo).
        manager.cancelDataRequest(requestID)
        if waited == .timedOut { return false }

        lock.lock()
        defer { lock.unlock() }
        return resident
    }
}
#endif
