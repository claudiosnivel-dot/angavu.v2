#!/usr/bin/env node
// resolve.mjs — sorgente unica della risoluzione dell'ecosistema attivo (SP-0).
// Classifica il repo -> manifest attivo (via detect), espone i binding. Nessun
// manifest combacia -> null (la skill dichiara "non supportato", non inventa).
//
// Fase 0 (eco-F6): aggiunto detect.deps_any — content-detection ADDITIVA. Se un
// manifest dichiara `deps_any`, classify() legge package.json (JS/TS) o
// requirements.txt (Python) del projectDir e tratta una dipendenza corrispondente
// come SEGNALE FORTE (come files_any). DEFAULT-INVARIANTE: i manifest esistenti
// senza deps_any non cambiano comportamento (Passata 1 calcola hits da filesAny
// solo; Passata 2 salta solo manifest con files_any O deps_any).
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateEcosystem } from './validate_ecosystem.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ECO_DIR = resolve(__dirname, '..', '..', 'references', 'ecosystems');

export function loadEcosystems(dir = ECO_DIR) {
  const out = [];
  let entries = [];
  try { entries = readdirSync(dir); } catch { return out; }
  for (const e of entries) {
    const mf = join(dir, e, 'ecosystem.json');
    if (!existsSync(mf)) continue;
    let m = null;
    try { m = JSON.parse(readFileSync(mf, 'utf8')); } catch { continue; }
    if (validateEcosystem(m).ok) out.push(m);
  }
  return out;
}

// strongSignal(projectDir, entry) -> bool
// SP-1 T2.1 — un'entry di detect.files_any è un SEGNALE FORTE quando il file
// dichiarato esiste OPPURE quando esiste la sua DIRECTORY-MARKER (il primo
// segmento del path-signal). Razionale: i marker dichiarati (es.
// `supabase/config.toml`) identificano un ecosistema tramite la cartella-firma
// (`supabase/`) che un progetto reale ha SEMPRE — anche mid-setup (solo
// `supabase/migrations/`, config.toml non ancora generato) o nelle fixture eval.
// Senza questo, un repo Supabase con la dir `supabase/` ma senza config.toml
// cadrebbe nel fallback lang_any-only e verrebbe mis-classificato come il pack
// generico (es. postgres-jsts), rompendo a valle la selezione degli oracoli del
// loop (verified_set sbagliato). La dir-marker NON è lasca: vale solo per le entry
// con un segmento di directory (es. `supabase/...`); un'entry file-in-root
// (es. `package.json`) resta un match esatto-file, mai dir.
function strongSignal(projectDir, entry) {
  if (existsSync(join(projectDir, entry))) return true; // file dichiarato presente
  const seg = String(entry).split('/')[0];
  if (seg && seg !== entry) {                            // l'entry ha una dir-marker
    try { if (statSync(join(projectDir, seg)).isDirectory()) return true; } catch { /* assente */ }
  }
  return false;
}

// projectDepNames(projectDir) -> Set<string>
// SP-F6 Fase 0 — nomi delle dipendenze DICHIARATE dal progetto: package.json
// (dependencies + devDependencies, JS/TS) e requirements.txt (Python). Alimenta il
// nuovo segnale-forte detect.deps_any: alcuni backend (es. Mongo/Dynamo) NON hanno un
// file-marker che li distingua da un generico progetto JS — si identificano SOLO dalla
// dipendenza dichiarata, invisibile a una detection presence-only. Letto al più UNA
// volta per classify (memoizzato dal chiamante) e SOLO se almeno un manifest usa
// deps_any: i pack senza deps_any non innescano alcuna lettura -> default-invarianti.
function projectDepNames(projectDir) {
  const names = new Set();
  const pkgPath = join(projectDir, 'package.json');
  if (existsSync(pkgPath)) {
    try {
      const pkg = JSON.parse(readFileSync(pkgPath, 'utf8'));
      for (const field of ['dependencies', 'devDependencies']) {
        const o = pkg && pkg[field];
        if (o && typeof o === 'object') for (const k of Object.keys(o)) names.add(k);
      }
    } catch { /* package.json assente/non-JSON: nessun dep JS dichiarato */ }
  }
  const reqPath = join(projectDir, 'requirements.txt');
  if (existsSync(reqPath)) {
    try {
      for (const raw of readFileSync(reqPath, 'utf8').split(/\r?\n/)) {
        const line = raw.trim();
        if (!line || line.startsWith('#') || line.startsWith('-')) continue; // commento / opzione pip
        const name = line.split(/[=<>~!;,\[\s]/)[0].trim();                   // nome prima del version-specifier
        if (name) names.add(name);
      }
    } catch { /* requirements.txt illeggibile */ }
  }
  return names;
}

// classify(projectDir) -> id (string) | null | {ambiguous:true, candidates:[...]}
// SP-1 T2.1 — precedenza file-signal-forte, in DUE passate:
//  (1) i manifest con detect.files_any NON vuoto il cui SEGNALE FORTE è presente
//      (file dichiarato O dir-marker, vedi strongSignal) = SEGNALE FORTE; tra più
//      match forti vince il più SPECIFICO (più files_any combacianti). Pari merito
//      sul MASSIMO numero di hit files_any -> TIE-BREAK per LINGUA (SP-3 T2.1):
//      due manifest con lo STESSO backend (es. supabase-jsts e supabase-py
//      condividono files_any:["supabase/config.toml"]) differiscono solo per la
//      LINGUA. Si conta allora il numero di match detect.lang_any presenti nel
//      projectDir: vince chi ha più match (il backend È deciso, la lingua lo
//      disambigua — es. package.json -> JS/TS, requirements.txt -> Python). Se
//      pareggiano ANCHE sulla lingua (entrambe presenti, o entrambe assenti) =
//      AMBIGUITÀ -> esito {ambiguous} (il chiamante fa proponi+conferma, regola
//      dura SKILL.md §1) — MAI un verde silenzioso.
//  (2) fallback: i manifest lang_any-only (detect senza files_any NÉ deps_any) il cui
//      lang_any combacia; stessa gestione dell'ambiguità.
//  Repo che non combacia in nessuna passata -> null (non supportato, onesto).
//
//  SP-F6 Fase 0 (ADDITIVO, default-invariante) — campo opzionale detect.deps_any: una
//  dipendenza dichiarata (∈ deps_any) vale come UN files_any presente -> SEGNALE FORTE
//  in passata 1 (Mongo/Dynamo non hanno file-marker, solo la dipendenza li distingue).
//  Un manifest deps_any-only il cui dep NON combacia non ricade nemmeno in passata 2
//  (dichiara "rilevante solo se la mia dipendenza è presente"). I 17 pack senza deps_any
//  NON leggono dipendenze e percorrono ESATTAMENTE il ramo storico -> comportamento immutato.
export function classify(projectDir, ecosystems = loadEcosystems()) {
  // Set dei nomi-dipendenza del progetto, letto AL PIÙ UNA VOLTA e SOLO se un manifest
  // usa detect.deps_any (lazy): i pack senza deps_any non innescano alcuna lettura.
  let depNamesCache = null;
  const depNames = () => (depNamesCache ??= projectDepNames(projectDir));
  const depsMatched = (d) => {
    const da = d.deps_any || [];
    if (!da.length) return false;
    const names = depNames();
    return da.some((name) => names.has(name));
  };

  // Passata 1 — segnale forte: files_any presente (file o dir-marker) OPPURE deps_any
  // combaciante (una dipendenza ∈ deps_any). Un dep-match conta come UN files_any
  // presente. Si registra anche langHits (match di lang_any nel projectDir) per il tie-break.
  const strong = [];
  for (const m of ecosystems) {
    const d = m.detect || {};
    const filesAny = d.files_any || [];
    const depHit = depsMatched(d);
    if (!filesAny.length && !depHit) continue;
    const hits = filesAny.filter((f) => strongSignal(projectDir, f)).length + (depHit ? 1 : 0);
    if (hits > 0) {
      const langHits = (d.lang_any || []).filter((f) => existsSync(join(projectDir, f))).length;
      strong.push({ id: m.id, hits, langHits });
    }
  }
  if (strong.length) {
    const max = Math.max(...strong.map((s) => s.hits));
    let top = strong.filter((s) => s.hits === max);
    if (top.length === 1) return top[0].id;
    // Tie-break per LINGUA (SP-3 T2.1): stesso backend, lingue diverse. Vince chi ha
    // più match lang_any; se pareggiano anche sulla lingua -> ambiguità onesta.
    const maxLang = Math.max(...top.map((s) => s.langHits));
    top = top.filter((s) => s.langHits === maxLang);
    if (top.length === 1) return top[0].id;
    return { ambiguous: true, candidates: top.map((s) => s.id) }; // proponi+conferma
  }

  // Passata 2 — fallback lang_any-only (nessun files_any NÉ deps_any nel manifest).
  // I manifest con deps_any sono "forti-capaci": valutati solo in passata 1 (un dep-match
  // li promuove; un dep-miss li esclude — non devono catturare ogni package.json).
  const weak = [];
  for (const m of ecosystems) {
    const d = m.detect || {};
    if ((d.files_any || []).length || (d.deps_any || []).length) continue; // i forti-capaci sono già stati valutati
    const langAny = d.lang_any || [];
    const hits = langAny.filter((f) => existsSync(join(projectDir, f))).length;
    if (hits > 0) weak.push({ id: m.id, hits });
  }
  if (weak.length) {
    const max = Math.max(...weak.map((w) => w.hits));
    const top = weak.filter((w) => w.hits === max);
    if (top.length === 1) return top[0].id;
    return { ambiguous: true, candidates: top.map((w) => w.id) }; // proponi+conferma
  }

  return null;
}

const keysToCategories = (oracles) => {
  const out = {};
  for (const [key, b] of Object.entries(oracles)) for (const cat of key.split('|')) out[cat.trim()] = b;
  return out;
};
export const oraclesFor = (m) => keysToCategories(m.oracles);
export const deadCodeTool = (m) => (m.oracles['dead-code'] && m.oracles['dead-code'].tool) || null;
export const testRunnerDetect = (m) => (m.test_runner && m.test_runner.detect) || [];
export const verifiedSet = (m) => m.verified_set || [];
export const floorOf = (m) => m.floor || [];
export function authzSurfaceCategory(m) {
  for (const [key, b] of Object.entries(m.oracles)) if (b && b.role === 'authz-surface') return key.split('|')[0].trim();
  return null;
}
export function loadManifest(id) { return loadEcosystems().find((m) => m.id === id) || null; }
