import AngavuDomain
import Foundation

// FSE-J3 (Data) — Sostituzione compressa REALE (censimento C2).
//
// Prima: l'export girava ma `apply()` calcolava solo il piano puro
// (`CompressedReplacementPlanner`) — nessun `PHAssetCreationRequest`, nessuna
// eliminazione dell'originale → NIENTE spazio liberato (no-op).
//
// Qui il cablaggio della sostituzione vera, in due strati:
//   • ORCHESTRAZIONE pura (`SafeCompressedAssetInstaller`) — salva il compresso e,
//     SOLO dopo un salvataggio verificato, elimina l'originale col deleter di J1.
//     È testabile in CI senza device (saver + deleter iniettati): l'invariante
//     anti-perdita «salvataggio fallito → nessuna delete» è un ORACOLO reale.
//   • ADAPTER di piattaforma (`PHAssetCreationSaver`) — il solo `PHAssetCreationRequest`,
//     guardato `canImport(Photos)`, device-only (runtime dichiarato non coperto, §7).

/// Esito dell'installazione del compresso in libreria.
public enum CompressedInstallResult: Equatable, Sendable {
    /// Compresso salvato in libreria E originale eliminato (→ «Eliminati di recente»).
    case installed
    /// Salvataggio del compresso fallito: l'originale NON è stato toccato (mai perdita dati).
    case saveFailed(reason: String)
    /// Compresso salvato ma l'eliminazione dell'originale non è riuscita/annullata:
    /// entrambi restano in libreria (nessuna perdita — il compresso c'è, l'originale intatto).
    case deleteFailed(reason: String)
}

/// Salva la versione compressa e, dopo verifica, elimina l'originale. I test la
/// sostituiscono con una spia che registra le invocazioni e restituisce un esito noto.
public protocol CompressedAssetInstalling {
    /// Salva il file compresso in `url` come nuovo asset (preservando data/luogo dei
    /// metadati) e, SOLO su salvataggio riuscito, elimina l'originale `originalId`.
    func install(
        compressedAt url: URL,
        originalId: String,
        metadata: VideoMetadata
    ) async -> CompressedInstallResult
}

/// Esito del solo passo di salvataggio del compresso in libreria.
public enum CompressedSaveResult: Equatable, Sendable {
    /// Salvato e verificato: da qui in poi è sicuro eliminare l'originale.
    case saved
    /// Salvataggio non riuscito: l'originale NON va toccato.
    case failed(reason: String)
}

/// Salva un file compresso in libreria come nuovo asset. L'adapter reale usa
/// `PHAssetCreationRequest`; i test iniettano un fake con esito noto.
public protocol CompressedVideoSaving {
    func save(compressedAt url: URL, metadata: VideoMetadata) async -> CompressedSaveResult
}

/// Null-object: default dell'`AppEnvironment` finché `live()` non cabla l'installer
/// reale. NON finge un successo — riporta `saveFailed`, così l'AC-FSE-J3-2 becca un
/// installer lasciato sul null-object nella radice di composizione (censimento C2).
public struct NoCompressedInstaller: CompressedAssetInstalling {
    public init() {}
    public func install(
        compressedAt url: URL,
        originalId: String,
        metadata: VideoMetadata
    ) async -> CompressedInstallResult {
        .saveFailed(reason: "nessun installer configurato")
    }
}

/// Orchestrazione PURA della sostituzione (nessuna dipendenza di piattaforma): salva il
/// compresso e, SOLO se il salvataggio è verificato, elimina l'originale col deleter di J1
/// (→ «Eliminati di recente», indice allineato). L'ordine è la garanzia anti-perdita: mai
/// `delete` prima di un `save` andato a buon fine. Testabile in CI con saver + deleter fake.
public struct SafeCompressedAssetInstaller: CompressedAssetInstalling {
    private let saver: any CompressedVideoSaving
    private let deleter: any AssetDeleting

    public init(saver: any CompressedVideoSaving, deleter: any AssetDeleting) {
        self.saver = saver
        self.deleter = deleter
    }

    public func install(
        compressedAt url: URL,
        originalId: String,
        metadata: VideoMetadata
    ) async -> CompressedInstallResult {
        // 1) Salva il compresso. NIENTE eliminazione prima di questo passo.
        let saved = await saver.save(compressedAt: url, metadata: metadata)
        if case .failed(let reason) = saved {
            return .saveFailed(reason: reason) // originale intatto: mai perdita di dati
        }
        // 2) Salvataggio verificato: elimina l'originale via la rete di sicurezza (J1).
        let deletion = await deleter.delete(ids: [originalId])
        switch deletion {
        case .success:
            return .installed
        case .cancelled:
            return .deleteFailed(reason: "eliminazione dell'originale annullata")
        case .failed(let reason):
            return .deleteFailed(reason: reason)
        }
    }
}

#if canImport(Photos)
import Photos
import CoreLocation

/// Adapter reale del salvataggio: `PHAssetCreationRequest` con data/luogo preservati.
/// È il SOLO pezzo device-only della sostituzione (runtime non coperto in CI, §7).
public struct PHAssetCreationSaver: CompressedVideoSaving {
    public init() {}

    public func save(compressedAt url: URL, metadata: VideoMetadata) async -> CompressedSaveResult {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                // Il file è un temporaneo dell'export, di nostra proprietà: spostalo
                // (non copiarlo) — evita di duplicare i byte su disco.
                options.shouldMoveFile = true
                request.addResource(with: .video, fileURL: url, options: options)
                // Preserva data/luogo dell'originale (parità coi metadati dell'export).
                request.creationDate = metadata.creationDate
                if let latitude = metadata.latitude, let longitude = metadata.longitude {
                    request.location = CLLocation(latitude: latitude, longitude: longitude)
                }
            }
            return .saved
        } catch {
            return .failed(reason: (error as NSError).localizedDescription)
        }
    }
}
#endif
