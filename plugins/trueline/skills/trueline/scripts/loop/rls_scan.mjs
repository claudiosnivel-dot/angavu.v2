// rls_scan.mjs — risoluzione MANIFEST-DRIVEN della directory delle migration RLS
// (scioglie O-COL-011 / applica L-COL-029). SEAM condiviso: l'engine NON cabla
// piu' 'supabase/migrations'; CHIEDE al manifest dove vivono le migration e usa
// il PRIMO dir esistente. Default BIT-INVARIANTE per il layout Supabase.
//
// PROBLEMA risolto: tre script spediti cablavano 'supabase/migrations', mentre
// postgres-py (non-Supabase) usa 'migrations/'. Questo helper centralizza la
// precedenza e mantiene il comportamento Supabase byte-identico (il default ha
// 'supabase/migrations' come PRIMO elemento, e quella dir esiste nelle fixture
// Supabase -> stesso path risolto, stessa chiamata a valle).
//
// PRECEDENZA per la DIRECTORY delle migration:
//   1) opts.scan                        (array esplicito passato dal chiamante)
//   2) opts.manifest.oracles.rls.scan   (array dichiarato nel manifest attivo)
//   3) DEFAULT = ['supabase/migrations', 'migrations', 'db/migrations']
// Si ritorna il PRIMO dir ESISTENTE (assoluto, sotto `dir`). Se NESSUNO della
// lista esiste, FALLBACK a resolve(dir, 'supabase', 'migrations') — il path
// cablato storico: BIT-INVARIANTE per chi prima cablava sempre quel path.
//
// Node ESM, solo built-in (fs, path). Niente rete.

import { existsSync, statSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

// Lista di default delle candidate per la migration-dir, relative al projectDir.
// 'supabase/migrations' e' PRIMA: per le fixture Supabase (dove esiste) la
// risoluzione coincide col path storicamente cablato -> comportamento invariato.
export const DEFAULT_RLS_SCAN = ['supabase/migrations', 'migrations', 'db/migrations'];

// Il path cablato storico, usato come FALLBACK quando nessuna candidata esiste:
// preserva il comportamento byte-identico dei chiamanti che prima facevano
// sempre resolve(dir, 'supabase', 'migrations') (anche su una dir inesistente,
// dove gli oracoli a valle degradano onestamente).
function legacyDefaultDir(dir) {
  return resolve(dir, 'supabase', 'migrations');
}

function isDir(p) {
  try { return statSync(p).isDirectory(); } catch { return false; }
}

// Estrae la lista di candidate dalle opzioni, secondo la precedenza. Ritorna
// sempre un array non-vuoto (cade sul DEFAULT se ne' opts.scan ne' il manifest
// la dichiarano).
function scanListFrom(opts = {}) {
  if (Array.isArray(opts.scan) && opts.scan.length > 0) return opts.scan;
  const fromManifest = opts.manifest
    && opts.manifest.oracles
    && opts.manifest.oracles.rls
    && opts.manifest.oracles.rls.scan;
  if (Array.isArray(fromManifest) && fromManifest.length > 0) return fromManifest;
  return DEFAULT_RLS_SCAN;
}

// resolveRlsMigrationsDir(dir, opts) -> string (path ASSOLUTO della migration-dir)
//
//   dir   projectDir / copia temp / reference-app
//   opts  { scan?: string[], manifest?: <ecosystem.json> }
//
// Ritorna il PRIMO dir ESISTENTE tra le candidate (assoluto, sotto `dir`). Se
// nessuna esiste, FALLBACK al path cablato storico (BIT-INVARIANTE Supabase).
export function resolveRlsMigrationsDir(dir, opts = {}) {
  const candidates = scanListFrom(opts);
  for (const rel of candidates) {
    const abs = resolve(dir, rel);
    if (isDir(abs)) return abs;
  }
  // Nessuna candidata esiste: torna al path cablato storico. Per il layout
  // Supabase questo coincide con candidates[0] (gia' tentato): nessun cambio di
  // comportamento. Per dir sconosciute, e' la stessa dir (inesistente) che il
  // codice cablato avrebbe passato agli oracoli, che degradano onestamente.
  return legacyDefaultDir(dir);
}

// resolveRlsMigrationFile(dir, opts) -> string | null
//
// Trova il file .sql PRIMARIO della migration-dir risolta: preferisce
// '0001_init.sql' (la convenzione delle fixture), altrimenti il PRIMO *.sql in
// ordine alfabetico. Ritorna il path ASSOLUTO, o null se la dir non esiste o non
// contiene .sql. Serve a fix_provider per localizzare la migration da fixare
// senza cablare ne' la dir ne' il nome-file.
export function resolveRlsMigrationFile(dir, opts = {}) {
  const migDir = resolveRlsMigrationsDir(dir, opts);
  if (!isDir(migDir)) return null;
  let files;
  try {
    files = readdirSync(migDir).filter((f) => f.toLowerCase().endsWith('.sql')).sort();
  } catch {
    return null;
  }
  if (files.length === 0) return null;
  const preferred = files.find((f) => f === '0001_init.sql');
  return join(migDir, preferred || files[0]);
}

export default resolveRlsMigrationsDir;
