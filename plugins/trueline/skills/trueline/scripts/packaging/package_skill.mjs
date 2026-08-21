#!/usr/bin/env node
// package_skill.mjs — assembla la SKILL spedita, la LINTA (lint strutturale,
// gemello di validate_blueprint applicato alla skill), stampa il MANIFEST di
// versioni, ed emette l'archivio .skill (09 §3).
//
// Artefatto di BUILD del kernel (NON viaggia nel .skill: confeziona ciò che
// viaggia). Deterministico e riproducibile (09 §3, L-COL-002: "verde" = esito
// di comando, non un parere). Node ESM, SOLO moduli built-in: nessun npm
// install, nessuna dipendenza di rete, nessun binario di terzi bundlato.
//
// COSA FA, in ordine (09 §3):
//   1. ASSEMBLA  l'albero canonico (02 §4) con radice trueline/ in una dir di
//      staging: SKILL.md + scripts/ + references/ + assets/prompts/. Esclude
//      node_modules/, package.json/lock, file di test (*.test.mjs) e qualunque
//      cosa NON sia "nostro codice + reference + ruleset vendorizzato" (09 §2).
//   2. LINT STRUTTURALE (deterministico, binario): SKILL.md < ~500 righe
//      (L-COL-014); frontmatter name + description non vuoti; OGNI file
//      referenziato da SKILL.md/dai modes esiste nell'albero assemblato; i 3
//      prompt presenti; il ruleset curato presente (oltre placeholder.yml);
//      NESSUN riferimento orfano. ROSSO -> il pacchetto NON si emette (exit !=0).
//   3. MANIFEST  di versioni: SemVer della skill, versione del ruleset curato,
//      versioni minime degli oracoli (dal preflight), ecosistema/i.
//   4. EMETTE    l'archivio .skill (tar+gzip deterministico, built-in zlib).
//
// USO:
//   node package_skill.mjs                         -> report umano, lint+manifest,
//                                                     emette dist/trueline.skill
//   node package_skill.mjs --out <dir-o-file>      -> staging in <dir>/ (se dir) o
//                                                     accanto al file; archivio in
//                                                     <file>.skill / <dir>.skill
//   node package_skill.mjs --json                  -> { ok, lint, manifest, tree }
//                                                     su stdout; exit 0/!=0
//   node package_skill.mjs --no-archive            -> assembla+linta+manifest, NON
//                                                     emette l'archivio
//   node package_skill.mjs --inject-missing-ref    -> FALSIFICABILITÀ: rimuove
//                                                     dall'albero assemblato un file
//                                                     referenziato da SKILL.md, così
//                                                     il lint DEVE fallire (prova che
//                                                     il lint non è un timbro verde).
//
// ESITO: exit 0 SOLO se il lint passa (e, se richiesto, l'archivio è emesso);
//        exit 1 se il lint fallisce (nessun archivio); 2 su errore d'uso/IO.

import {
  readFileSync, writeFileSync, readdirSync, existsSync, statSync,
  mkdirSync, rmSync, cpSync, realpathSync,
} from 'node:fs';
import { join, dirname, resolve, relative, sep, posix } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gzipSync } from 'node:zlib';
import { createHash } from 'node:crypto';
import { validateEcosystem } from '../ecosystem/validate_ecosystem.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
// Radice della SKILL SORGENTE: trueline/ (questo file vive in trueline/scripts/packaging/).
const SKILL_SRC = resolve(__dirname, '..', '..');
const SKILL_NAME = 'trueline';

// --- Parsing degli argomenti -------------------------------------------------
const args = process.argv.slice(2);
const jsonMode = args.includes('--json');
const noArchive = args.includes('--no-archive');
const injectMissingRef = args.includes('--inject-missing-ref');
// Registra <versione, digest> nel record di release. Atto ESPLICITO per release:
// senza, una versione mai registrata non si emette (vedi releaseGuard).
const recordRelease = args.includes('--record-release');
function flagValue(name) {
  const i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length && !args[i + 1].startsWith('--') ? args[i + 1] : null;
}
const outArg = flagValue('--out');
// Fase 2: target AGGIUNTIVO layout-plugin Claude Code. Non tocca il .skill
// (default). `.claude-plugin/` e `hooks/` NON sono in BUNDLE_TOP -> il .skill
// resta identico (i sorgenti plugin non entrano mai nell'archivio).
const pluginArg = flagValue('--plugin');
// --plugin richiede una directory di output: se il flag c'e' ma senza valore, e'
// un errore d'uso, MAI un no-op silenzioso (che farebbe credere il plugin emesso).
if (args.includes('--plugin') && !pluginArg) {
  fail('--plugin richiede una directory di output (es. --plugin dist/trueline-plugin)', 2);
}

// --- Costanti del lint -------------------------------------------------------
const SKILL_MD_MAX_LINES = 500; // L-COL-014: corpo < ~500 righe
const REQUIRED_PROMPTS = ['project-start.md', 'session-start.md', 'session-end.md'];
const RULESET_REL = posix.join('references', 'oracles', 'semgrep-ai-ruleset');
const RULESET_PLACEHOLDER = 'placeholder.yml';

// Cosa viaggia nel .skill (09 §2 / 02 §4). Solo il NOSTRO codice + reference +
// ruleset vendorizzato + i prompt. Tutto il resto resta fuori.
const BUNDLE_TOP = ['SKILL.md', 'scripts', 'references', 'assets'];
// Esclusioni dentro l'albero bundlato: niente node_modules, manifest npm, test,
// né artefatti di staging precedenti.
function isExcluded(relPath) {
  const p = relPath.split(sep).join('/');
  if (p === 'node_modules' || p.startsWith('node_modules/') || p.includes('/node_modules/')) return true;
  if (/(^|\/)package(-lock)?\.json$/.test(p)) return true;
  if (/(^|\/)tsconfig\.json$/.test(p)) return true;
  if (/\.test\.mjs$/.test(p)) return true;            // suite di test: non spedite
  if (/(^|\/)\.[^/]+$/.test(p) && !p.endsWith('.skill')) {
    // file/dir nascosti (.gitkeep, .DS_Store) — non spediti
    if (/(^|\/)\.(gitkeep|DS_Store|git)(\/|$)/.test(p)) return true;
  }
  // assets/: solo prompts/ viaggia (02 §4)
  if (p === 'assets') return false;
  return false;
}

// --- Helpers di FS ricorsivo -------------------------------------------------
function walk(dir, baseAbs, acc) {
  let entries;
  try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return acc; }
  for (const e of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    const abs = join(dir, e.name);
    const rel = relative(baseAbs, abs);
    if (isExcluded(rel)) continue;
    if (e.isDirectory()) walk(abs, baseAbs, acc);
    else if (e.isFile()) acc.push(rel.split(sep).join('/'));
  }
  return acc;
}

function copyTree(srcRoot, dstRoot) {
  rmSync(dstRoot, { recursive: true, force: true });
  mkdirSync(dstRoot, { recursive: true });
  for (const top of BUNDLE_TOP) {
    const src = join(srcRoot, top);
    if (!existsSync(src)) continue;
    const dst = join(dstRoot, top);
    cpSync(src, dst, {
      recursive: true,
      filter: (s) => {
        const rel = relative(srcRoot, s);
        if (rel === '' || rel === top) return true;
        return !isExcluded(rel);
      },
    });
  }
}

// --- Estrazione dei RIFERIMENTI da SKILL.md e dai modes -----------------------
// Un "riferimento" è un percorso a un artefatto BUNDLATO citato nel corpo o in un
// file di modalità: o un link markdown [..](path), o un token in backtick che
// inizia per references/ | scripts/ | assets/. I percorsi relativi (../x) sono
// risolti rispetto alla cartella del file che li cita. Deterministico.
const REF_PREFIXES = ['references/', 'scripts/', 'assets/'];

function isBundleRef(p) {
  return REF_PREFIXES.some((pre) => p === pre.slice(0, -1) || p.startsWith(pre));
}

// Normalizza un riferimento citato in `fromRelDir` (dir del file citante, relativa
// alla radice dell'albero) in un percorso POSIX relativo alla radice. Mantiene il
// trailing slash (segnala "directory") se presente.
function normalizeRef(raw, fromRelDir) {
  let ref = raw.trim();
  // togli ancore e query
  ref = ref.replace(/[#?].*$/, '');
  if (!ref) return null;
  const trailingSlash = ref.endsWith('/');
  // percorso assoluto-nell'albero (references/.., scripts/.., assets/..)
  let relPath;
  if (isBundleRef(ref)) {
    relPath = ref;
  } else if (ref.startsWith('../') || ref.startsWith('./')) {
    // relativo alla dir del file citante
    relPath = posix.normalize(posix.join(fromRelDir, ref));
  } else {
    return null; // non è un riferimento ad artefatto bundlato
  }
  relPath = relPath.replace(/\/+$/, '');
  if (!isBundleRef(relPath + (trailingSlash ? '/' : ''))) return null;
  return { path: relPath, isDir: trailingSlash };
}

function extractRefsFromFile(absFile, treeRoot) {
  const txt = readFileSync(absFile, 'utf8');
  const fromRelDir = relative(treeRoot, dirname(absFile)).split(sep).join('/');
  const refs = new Map(); // path -> { path, isDir }
  // (a) link markdown: ](target)
  const linkRe = /\]\(([^)]+)\)/g;
  let m;
  while ((m = linkRe.exec(txt)) !== null) {
    const n = normalizeRef(m[1], fromRelDir);
    if (n) refs.set(n.path, n);
  }
  // (b) token in backtick che iniziano per un prefisso bundlato
  const codeRe = /`([^`]+)`/g;
  while ((m = codeRe.exec(txt)) !== null) {
    const tok = m[1].trim();
    // primo "campo" del token (evita prosa dentro il backtick)
    const first = tok.split(/\s+/)[0];
    if (isBundleRef(first)) {
      const n = normalizeRef(first, fromRelDir);
      if (n) refs.set(n.path, n);
    }
  }
  return [...refs.values()];
}

// --- Frontmatter -------------------------------------------------------------
function parseFrontmatter(skillTxt) {
  const fm = skillTxt.match(/^---\s*\n([\s\S]*?)\n---/);
  if (!fm) return { name: '', description: '', raw: '' };
  const body = fm[1];
  const nameM = body.match(/(^|\n)name:\s*(.+?)\s*(\n|$)/);
  // description può essere multilinea (block scalar >). Prende fino al prossimo
  // campo top-level (chiave: a inizio riga) o alla fine del frontmatter.
  const descM = body.match(/(^|\n)description:\s*([\s\S]*?)(?:\n[A-Za-z_][A-Za-z0-9_]*:|\s*$)/);
  const name = nameM ? nameM[2].trim() : '';
  let description = descM ? descM[2].trim() : '';
  description = description.replace(/^>\s*/, '').replace(/\s+/g, ' ').trim();
  return { name, description, raw: body };
}

function lineCount(txt) {
  return txt.replace(/\r\n/g, '\n').split('\n').length;
}

// --- LINT STRUTTURALE --------------------------------------------------------
function structuralLint(treeRoot, { injectedMissing } = {}) {
  const errors = [];
  const warnings = [];
  const skillMd = join(treeRoot, 'SKILL.md');

  // (0) SKILL.md presente
  if (!existsSync(skillMd)) {
    errors.push('SKILL.md assente nell\'albero assemblato');
    return { ok: false, errors, warnings, refs: [] };
  }
  const skillTxt = readFileSync(skillMd, 'utf8');

  // (1) SKILL.md < ~500 righe (L-COL-014)
  const lines = lineCount(skillTxt);
  if (!(lines > 0 && lines < SKILL_MD_MAX_LINES)) {
    errors.push(`SKILL.md ha ${lines} righe (atteso 0 < righe < ${SKILL_MD_MAX_LINES}, L-COL-014)`);
  }

  // (2) frontmatter: name + description non vuoti
  const { name, description } = parseFrontmatter(skillTxt);
  if (!name) errors.push('frontmatter: name vuoto/assente');
  if (!description) errors.push('frontmatter: description vuota/assente');

  // (3) ogni file referenziato da SKILL.md/modes esiste (no riferimenti orfani)
  const modeFiles = ['bootstrap.md', 'build.md', 'remediate.md']
    .map((f) => join(treeRoot, 'references', 'modes', f))
    .filter(existsSync);
  const refSources = [skillMd, ...modeFiles];
  const allRefs = new Map();
  for (const src of refSources) {
    for (const r of extractRefsFromFile(src, treeRoot)) {
      // tieni traccia di QUALE file lo cita (per messaggi)
      if (!allRefs.has(r.path)) allRefs.set(r.path, { ...r, from: [] });
      allRefs.get(r.path).from.push(relative(treeRoot, src).split(sep).join('/'));
    }
  }
  const refs = [...allRefs.values()];
  for (const r of refs) {
    const abs = join(treeRoot, r.path.split('/').join(sep));
    const ok = existsSync(abs);
    if (!ok) {
      errors.push(`riferimento ORFANO: "${r.path}" citato da ${r.from.join(', ')} ma assente nell'albero`);
      continue;
    }
    const st = statSync(abs);
    if (r.isDir) {
      if (!st.isDirectory()) errors.push(`riferimento "${r.path}" atteso directory ma è un file`);
      else if (walk(abs, abs, []).length === 0) errors.push(`directory referenziata "${r.path}" è vuota`);
    } else if (st.isDirectory()) {
      // un riferimento senza trailing slash che è una dir: tollerato solo se non vuota
      if (walk(abs, abs, []).length === 0) errors.push(`riferimento "${r.path}" è una directory vuota`);
    }
  }

  // (4) i 3 prompt presenti
  for (const p of REQUIRED_PROMPTS) {
    if (!existsSync(join(treeRoot, 'assets', 'prompts', p))) {
      errors.push(`prompt di lifecycle assente: assets/prompts/${p}`);
    }
  }

  // (5) ruleset curato presente (oltre placeholder.yml)
  const rulesetDir = join(treeRoot, RULESET_REL.split('/').join(sep));
  if (!existsSync(rulesetDir) || !statSync(rulesetDir).isDirectory()) {
    errors.push(`ruleset curato assente: ${RULESET_REL}/`);
  } else {
    const curated = readdirSync(rulesetDir)
      .filter((f) => /\.ya?ml$/i.test(f) && f !== RULESET_PLACEHOLDER);
    if (curated.length === 0) {
      errors.push(`ruleset curato assente: solo ${RULESET_PLACEHOLDER} in ${RULESET_REL}/ (curato mancante)`);
    }
  }

  // (6) ogni manifest ecosistema valido (validateEcosystem); manifest ROTTO -> FAIL
  // Scansiona references/ecosystems/<id>/ecosystem.json nell'albero assemblato.
  const ecosystemsDir = join(treeRoot, 'references', 'ecosystems');
  if (existsSync(ecosystemsDir) && statSync(ecosystemsDir).isDirectory()) {
    const ecoEntries = readdirSync(ecosystemsDir, { withFileTypes: true });
    for (const ee of ecoEntries.sort((a, b) => a.name.localeCompare(b.name))) {
      if (!ee.isDirectory()) continue;
      const mfAbs = join(ecosystemsDir, ee.name, 'ecosystem.json');
      if (!existsSync(mfAbs)) continue;
      let em = null;
      try { em = JSON.parse(readFileSync(mfAbs, 'utf8')); }
      catch (e) { errors.push(`ecosistema "${ee.name}": ecosystem.json non e JSON valido: ${e.message}`); continue; }
      const vr = validateEcosystem(em);
      if (!vr.ok) {
        for (const ve of vr.errors) errors.push(`ecosistema "${ee.name}": ${ve}`);
      }
    }
  }

  // (7) L-COL-029: le TABELLE DETERMINISTICHE di fix sono EVAL-ONLY (vivono in
  // eval/, fuori da BUNDLE_TOP) e NON devono MAI finire nel .skill. Controllo
  // FALSIFICABILE che ancora sul PAYLOAD (gli identificatori UNICI del provider
  // eval), non solo su una forma-export: cosi' resta robusto a re-export, arrow,
  // default, o uno split table-only sotto altro nome. Tutto ANCORATO a INIZIO
  // RIGA (/m) -> i commenti/regex INDENTATI di QUESTO stesso file (e la
  // provider-call indentata di run_loop.mjs) NON fanno self-match.
  const EVAL_PAYLOAD = new RegExp(
    '^(?:export\\s+)?(?:async\\s+)?function\\s+(?:deterministicFixProvider|selectKnownFix)\\b'
    + '|^(?:export\\s+)?const\\s+(?:PERLANG_SECRET_FIXES|FIX_TABLE)\\b'
    + '|^(?:export\\s+)?const\\s+deterministicFixProvider\\s*=',
    'm',
  );
  for (const rel of walk(treeRoot, treeRoot, [])) {
    const base = rel.split('/').pop();
    if (base === 'fix_provider.eval.mjs') {
      errors.push(`provider deterministico EVAL-ONLY spedito nel .skill: ${rel} (L-COL-029)`);
      continue;
    }
    if (!rel.endsWith('.mjs')) continue;
    let txt = '';
    try { txt = readFileSync(join(treeRoot, rel.split('/').join(sep)), 'utf8'); } catch { continue; }
    if (EVAL_PAYLOAD.test(txt)) {
      errors.push(`tabella di fix deterministica EVAL-ONLY presente nel .skill: ${rel} (L-COL-029)`);
    }
  }

  if (injectedMissing) {
    // verifica difensiva: l'iniezione DEVE aver prodotto almeno un orfano
    const orphanSeen = errors.some((e) => e.startsWith('riferimento ORFANO'));
    if (!orphanSeen) {
      errors.push(`--inject-missing-ref non ha prodotto un orfano (file iniettato: ${injectedMissing})`);
    }
  }

  return {
    ok: errors.length === 0,
    errors,
    warnings,
    refs: refs.map((r) => r.path),
    skill_md_lines: lines,
    frontmatter: { name, description },
  };
}

// --- MANIFEST di versioni (09 §4) --------------------------------------------
function readJson(p) {
  try { return JSON.parse(readFileSync(p, 'utf8')); } catch { return null; }
}

// Versione SemVer della skill: campo "skill_version" del package.json sorgente se
// presente, altrimenti "version" (>0.0.0), altrimenti default v0.1.0 documentato.
function skillSemver() {
  const pkg = readJson(join(SKILL_SRC, 'package.json')) || {};
  if (typeof pkg.skill_version === 'string' && /^\d+\.\d+\.\d+/.test(pkg.skill_version)) return pkg.skill_version;
  if (typeof pkg.version === 'string' && /^\d+\.\d+\.\d+/.test(pkg.version) && pkg.version !== '0.0.0') return pkg.version;
  return '0.1.0';
}

// Versione del ruleset curato: header "# version:" nel file curato, o hash corto
// del contenuto come fallback deterministico (pin tracciato nel manifest).
function rulesetVersion() {
  const dir = join(SKILL_SRC, RULESET_REL.split('/').join(sep));
  if (!existsSync(dir)) return null;
  const curated = readdirSync(dir).filter((f) => /\.ya?ml$/i.test(f) && f !== RULESET_PLACEHOLDER).sort();
  if (curated.length === 0) return null;
  const txt = readFileSync(join(dir, curated[0]), 'utf8');
  const vM = txt.match(/#\s*version:\s*([\w.\-+]+)/i);
  if (vM) return vM[1];
  // hash deterministico FNV-1a a 32 bit del contenuto concatenato (no dep esterne)
  let h = 0x811c9dc5;
  const all = curated.map((f) => readFileSync(join(dir, f), 'utf8')).join('\n');
  for (let i = 0; i < all.length; i++) { h ^= all.charCodeAt(i); h = Math.imul(h, 0x01000193); }
  const hex = (h >>> 0).toString(16).padStart(8, '0');
  return `0.0.0+sha.${hex}`;
}

// Versioni MINIME degli oracoli: lette dal preflight (fonte di verità del pin,
// 03 §4 / 09 §4). Parsing del literal MINIMUM_VERSIONS senza importare il modulo
// (evita side-effect: preflight esegue al require). Deterministico.
function oracleMinVersions() {
  const pf = join(SKILL_SRC, 'scripts', 'preflight.mjs');
  if (!existsSync(pf)) return {};
  const txt = readFileSync(pf, 'utf8');
  const blockM = txt.match(/MINIMUM_VERSIONS\s*=\s*\{([\s\S]*?)\};/);
  if (!blockM) return {};
  const out = {};
  const re = /['"]?([\w.\-]+)['"]?\s*:\s*\[\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\]/g;
  let m;
  while ((m = re.exec(blockM[1])) !== null) {
    out[m[1]] = `${m[2]}.${m[3]}.${m[4]}`;
  }
  return out;
}

// Ecosistemi supportati: sottocartelle di references/ecosystems/ con ecosystem.json.
// Ritorna array di { id, version, tier } in ordine deterministico.
// tier = "verified" se verified_set non vuoto, altrimenti "detection".
// Un manifest ROTTO (validateEcosystem fallisce) non viene incluso (già bloccato
// dal lint, ma difensivamente escluso anche qui).
function ecosystems() {
  const dir = join(SKILL_SRC, 'references', 'ecosystems');
  if (!existsSync(dir)) return [];
  const entries = readdirSync(dir, { withFileTypes: true });
  const result = [];
  for (const e of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    if (!e.isDirectory()) continue;
    const mfPath = join(dir, e.name, 'ecosystem.json');
    if (!existsSync(mfPath)) continue;
    let m = null;
    try { m = JSON.parse(readFileSync(mfPath, 'utf8')); } catch { continue; }
    const v = validateEcosystem(m);
    if (!v.ok) continue; // manifest rotto: escluso (il lint lo avrà già bloccato)
    const tier = m.verified_set && m.verified_set.length > 0 ? 'verified' : 'detection';
    result.push({ id: m.id, version: m.version, tier });
  }
  return result;
}

function buildManifest(treeRoot) {
  const semgrepImg = (() => {
    const rs = join(SKILL_SRC, 'scripts', 'oracles', 'run_semgrep.mjs');
    if (!existsSync(rs)) return null;
    const m = readFileSync(rs, 'utf8').match(/SEMGREP_IMAGE\s*=\s*['"]([^'"]+)['"]/);
    return m ? m[1] : null;
  })();
  const fileCount = walk(treeRoot, treeRoot, []).length;
  return {
    name: SKILL_NAME,
    skill_version: skillSemver(),
    ruleset_version: rulesetVersion(),
    oracle_min_versions: oracleMinVersions(),
    semgrep_image: semgrepImg,
    ecosystems: ecosystems(),
    license: 'MIT',
    telemetry: 'none',
    bundled_files: fileCount,
    generated_at_note: 'manifest deterministico (nessun timestamp incorporato — L-COL-002)',
  };
}

// --- ARCHIVIO .skill (tar + gzip, built-in zlib) -----------------------------
// tar ustar deterministico: niente mtime/uid variabili (mtime=0, uid/gid=0), così
// l'archivio è riproducibile bit-a-bit (10 §5). Solo Node built-in.
function tarHeader(name, size, mode, type) {
  const buf = Buffer.alloc(512, 0);
  const write = (str, off, len) => buf.write(str.slice(0, len), off, 'utf8');
  // ustar: nome max 100 (prefix per il resto)
  let nm = name;
  let prefix = '';
  if (Buffer.byteLength(nm) > 100) {
    const idx = nm.lastIndexOf('/', nm.length - (nm.length - 100));
    // split su uno slash così che entrambe le parti rientrino
    let cut = nm.length - 100;
    let slash = nm.indexOf('/', cut);
    if (slash === -1) slash = nm.lastIndexOf('/');
    prefix = nm.slice(0, slash);
    nm = nm.slice(slash + 1);
  }
  write(nm, 0, 100);
  write((mode & 0o7777).toString(8).padStart(7, '0') + '\0', 100, 8);
  write('0000000\0', 108, 8);   // uid 0
  write('0000000\0', 116, 8);   // gid 0
  write(size.toString(8).padStart(11, '0') + '\0', 124, 12);
  write('00000000000\0', 136, 12); // mtime 0
  write('        ', 148, 8);    // checksum placeholder (spazi)
  write(type, 156, 1);          // '0' file, '5' dir
  write('ustar\0', 257, 6);
  write('00', 263, 2);
  if (prefix) write(prefix, 345, 155);
  // checksum
  let sum = 0;
  for (let i = 0; i < 512; i++) sum += buf[i];
  write(sum.toString(8).padStart(6, '0') + '\0 ', 148, 8);
  return buf;
}

function buildTar(treeRoot, archiveRootName) {
  const chunks = [];
  // directory + file in ordine deterministico
  const files = walk(treeRoot, treeRoot, []).sort();
  // includi anche le dir (per i tool che le vogliono esplicite) — derivale dai file
  const dirs = new Set();
  for (const f of files) {
    const parts = f.split('/');
    for (let i = 1; i < parts.length; i++) dirs.add(parts.slice(0, i).join('/'));
  }
  for (const d of [...dirs].sort()) {
    chunks.push(tarHeader(`${archiveRootName}/${d}/`, 0, 0o755, '5'));
  }
  for (const f of files) {
    const data = readFileSync(join(treeRoot, f.split('/').join(sep)));
    chunks.push(tarHeader(`${archiveRootName}/${f}`, data.length, 0o644, '0'));
    chunks.push(data);
    const pad = (512 - (data.length % 512)) % 512;
    if (pad) chunks.push(Buffer.alloc(pad, 0));
  }
  // due blocchi di zero a fine archivio
  chunks.push(Buffer.alloc(1024, 0));
  return Buffer.concat(chunks);
}

// --- CONTROLLO DI RELEASE (L-COL-035 applicato alla distribuzione) -----------
// Un artefatto che nessuno puo' RICEVERE non e' spedito, come un gate che nessuno
// esegue non e' un verde. `claude plugin update` e' VERSION-gated: se l'albero
// spedito cambia e la versione no, l'update risponde «already at the latest
// version» e NON copia nulla — l'utente resta con detection vecchia, dichiarata
// aggiornata. Difetto MISURATO il 28 lug 2026 (il plugin globale era indietro di
// un'intera sessione). Qui si rende impossibile ri-emettere contenuto diverso
// sotto la stessa versione.
const RELEASE_RECORD = process.env.TRUELINE_RELEASE_DIGESTS
  ? resolve(process.env.TRUELINE_RELEASE_DIGESTS)
  : resolve(SKILL_SRC, '..', 'RELEASE-DIGESTS.json');

// Digest deterministico dell'albero ASSEMBLATO: path POSIX ordinati + sha256 del
// contenuto. Niente mtime, niente ordine di FS -> stesso albero, stesso digest.
//
// FINE-RIGA NORMALIZZATI (CRLF -> LF) sui file di TESTO. Il repo gira con
// core.autocrlf=true e senza .gitattributes: lo stesso commit produce CRLF su
// Windows e LF altrove, quindi un digest sui byte grezzi cambierebbe fra macchine
// e a ogni checkout — un ROSSO senza che nessuno abbia toccato il contenuto. La
// conversione di git non e' una modifica d'autore, ed e' l'unica cosa che qui si
// normalizza: ogni altra differenza di byte resta una differenza. I file BINARI
// (rilevati dal byte NUL) sono hashati grezzi, senza toccarli.
function shippedDigest(treeRoot) {
  const files = walk(treeRoot, treeRoot, []).sort();
  const h = createHash('sha256');
  for (const rel of files) {
    const abs = join(treeRoot, rel.split('/').join(sep));
    let buf = readFileSync(abs);
    if (!buf.includes(0)) buf = Buffer.from(buf.toString('utf8').replace(/\r\n/g, '\n'), 'utf8');
    h.update(rel);
    h.update('\0');
    h.update(createHash('sha256').update(buf).digest('hex'));
    h.update('\n');
  }
  return h.digest('hex');
}

// LIMITE DICHIARATO (L-COL-006): il record NON sa se una versione sia gia' stata
// DISTRIBUITA. Ri-registrare con --record-release una versione non ancora uscita
// e' legittimo (nessuno ha ricevuto il digest vecchio); farlo su una versione gia'
// in mano agli utenti aggirerebbe il controllo. `--record-release` e' l'atto UMANO
// esplicito che se ne assume la responsabilita': lo strumento rende visibile il
// cambiamento, non decide al posto di chi rilascia.
// Ritorna { ok, lines, error } — `error` non vuoto = emissione VIETATA.
function releaseGuard(treeRoot, version) {
  const lines = [];
  if (!existsSync(RELEASE_RECORD)) {
    // Caso legittimo: chi ri-pacchettizza dal proprio install non ha il record
    // del NOSTRO repo. Si dichiara, non si tace (L-COL-006: mai un verde muto).
    lines.push(`[--] controllo di release NON APPLICABILE — record assente (${RELEASE_RECORD})`);
    lines.push('     Copertura mancante DICHIARATA: nessuna garanzia che il contenuto sia cambiato insieme alla versione.');
    return { ok: true, lines, error: null };
  }
  let record;
  try { record = JSON.parse(readFileSync(RELEASE_RECORD, 'utf8')); }
  catch (e) { return { ok: false, lines, error: `record di release illeggibile (${RELEASE_RECORD}): ${e.message}` }; }
  if (!record || typeof record !== 'object' || Array.isArray(record)) {
    return { ok: false, lines, error: `record di release malformato (${RELEASE_RECORD}): atteso un oggetto <versione> -> <digest>` };
  }
  const digest = shippedDigest(treeRoot);
  const known = record[version];
  if (typeof known !== 'string') {
    if (!recordRelease) {
      return {
        ok: false,
        lines,
        error: `versione ${version} mai registrata in ${RELEASE_RECORD}. Se e' una release NUOVA, rilancia con --record-release per registrarne il digest; se invece hai cambiato l'albero spedito, bumpa prima "skill_version" in trueline/package.json.`,
      };
    }
    record[version] = digest;
    try { writeFileSync(RELEASE_RECORD, `${JSON.stringify(record, null, 2)}\n`, 'utf8'); }
    catch (e) { return { ok: false, lines, error: `record di release non scrivibile (${RELEASE_RECORD}): ${e.message}` }; }
    lines.push(`[OK] release ${version} REGISTRATA — digest ${digest.slice(0, 16)}…`);
    return { ok: true, lines, error: null };
  }
  if (known !== digest) {
    return {
      ok: false,
      lines,
      error: `l'albero SPEDITO e' cambiato ma la versione e' ancora ${version} (registrato ${known.slice(0, 16)}…, calcolato ${digest.slice(0, 16)}…). `
        + 'Un update version-gated NON consegnerebbe questo contenuto e riporterebbe "already at the latest version": '
        + 'bumpa "skill_version" in trueline/package.json e ri-registra con --record-release.',
    };
  }
  lines.push(`[OK] release ${version} invariata — digest ${digest.slice(0, 16)}… coincide col registrato`);
  return { ok: true, lines, error: null };
}

// --- MAIN --------------------------------------------------------------------
function fail(msg, code = 2) {
  if (jsonMode) console.log(JSON.stringify({ ok: false, error: msg }, null, 2));
  else console.error(`package_skill: ERRORE — ${msg}`);
  process.exit(code);
}

// Risolvi la destinazione: staging dir + path dell'archivio.
let stagingDir;
let archivePath;
if (outArg) {
  const out = resolve(outArg);
  if (out.endsWith('.skill')) {
    stagingDir = out.replace(/\.skill$/, '') + '.staging';
    archivePath = out;
  } else {
    stagingDir = out;
    archivePath = out.replace(/[/\\]$/, '') + '.skill';
  }
} else {
  stagingDir = resolve(SKILL_SRC, '..', 'dist', `${SKILL_NAME}.staging`);
  archivePath = resolve(SKILL_SRC, '..', 'dist', `${SKILL_NAME}.skill`);
}

// 1) ASSEMBLA
try {
  copyTree(SKILL_SRC, stagingDir);
} catch (e) {
  fail(`assemblaggio fallito: ${e.message}`);
}

// 1b) (opzionale) inietta un orfano: rimuovi dall'albero un file referenziato da
//     SKILL.md, così il lint DEVE bocciarlo (falsificabilità del lint).
let injectedMissing = null;
if (injectMissingRef) {
  const skillMd = join(stagingDir, 'SKILL.md');
  const candidates = existsSync(skillMd)
    ? extractRefsFromFile(skillMd, stagingDir).filter((r) => !r.isDir)
    : [];
  // scegli un file referenziato deterministicamente (il primo in ordine) ed esistente
  const victim = candidates
    .map((r) => r.path)
    .sort()
    .find((p) => existsSync(join(stagingDir, p.split('/').join(sep))));
  if (victim) {
    rmSync(join(stagingDir, victim.split('/').join(sep)), { force: true });
    injectedMissing = victim;
  } else {
    injectedMissing = '(nessun candidato file-ref trovato)';
  }
}

// 2) LINT
const lint = structuralLint(stagingDir, { injectedMissing });

// 3) MANIFEST (calcolato dall'albero assemblato + sorgenti)
const manifest = buildManifest(stagingDir);

// 3b) CONTROLLO DI RELEASE — prima di QUALUNQUE emissione (.skill e plugin).
//     Un contenuto nuovo sotto una versione gia' registrata non esce di qui.
//     SOLO a lint VERDE: il controllo gata l'EMISSIONE, e a lint rosso non si
//     emette comunque nulla. Farlo girare lo stesso MASCHEREREBBE il fallimento
//     del lint (exit 2 del release-guard al posto di exit 1 del lint) — proprio
//     cio' che il gate m5 verifica con --inject-missing-ref, dove l'albero e'
//     mutato APPOSTA e un digest diverso e' l'esito atteso, non una violazione.
let release = { ok: true, lines: ['[--] controllo di release SALTATO — lint rosso: nessuna emissione da gatare'], error: null };
if (lint.ok) {
  release = releaseGuard(stagingDir, skillSemver());
  if (!release.ok) fail(release.error, 2);
}

// 4) ARCHIVIO (solo se lint verde e non --no-archive)
let archiveEmitted = null;
if (lint.ok && !noArchive) {
  try {
    const tar = buildTar(stagingDir, SKILL_NAME);
    const gz = gzipSync(tar, { level: 9 });
    mkdirSync(dirname(archivePath), { recursive: true });
    writeFileSync(archivePath, gz);
    archiveEmitted = { path: archivePath, bytes: gz.length };
  } catch (e) {
    fail(`emissione archivio fallita: ${e.message}`, 2);
  }
}

// 4b) LAYOUT-PLUGIN (opzionale, --plugin <dir>): target AGGIUNTIVO, non altera
//     il .skill. Emette <dir>/.claude-plugin/plugin.json + <dir>/hooks/hooks.json
//     + <dir>/skills/trueline/{SKILL.md,scripts,references,assets} (riuso di
//     copyTree, stesse esclusioni del .skill). Emesso solo se il lint è verde.
let pluginEmitted = null;
if (pluginArg && lint.ok) {
  try {
    const pluginDir = resolve(pluginArg);
    // skills/trueline: identico al contenuto del .skill (copyTree + BUNDLE_TOP)
    copyTree(SKILL_SRC, join(pluginDir, 'skills', SKILL_NAME));
    // node_modules RUNTIME della skill (pgsql-ast-parser & co.): il plugin dev'essere
    // AUTOCONTENUTO (rls_check importa pgsql-ast-parser, import top-level). Sono esclusi
    // dal .skill (isExcluded), ma il PLUGIN li BUNDLA (pure-JS, 0 binari nativi ->
    // portabili) -> gira su macchina nuda senza npm. Il .skill resta invariato.
    const nmSrc = join(SKILL_SRC, 'node_modules');
    if (existsSync(nmSrc)) {
      cpSync(nmSrc, join(pluginDir, 'skills', SKILL_NAME, 'node_modules'), { recursive: true });
    }
    // .claude-plugin/ e hooks/: sorgenti versionati, copiati al livello del plugin
    // (NON in BUNDLE_TOP -> non entrano mai nel .skill: invarianza dell'archivio).
    for (const top of ['.claude-plugin', 'hooks']) {
      const src = join(SKILL_SRC, top);
      if (!existsSync(src)) continue;
      cpSync(src, join(pluginDir, top), {
        recursive: true,
        filter: (s) => {
          const rel = relative(SKILL_SRC, s);
          if (rel === '' || rel === top) return true;
          return !isExcluded(rel);
        },
      });
    }
    // Deriva la versione del plugin da skillSemver() (single source of truth): il
    // sorgente .claude-plugin/plugin.json e' un template, la versione emessa segue
    // skill_version (niente deriva al bump). Il .skill non e' toccato.
    const emittedManifest = join(pluginDir, '.claude-plugin', 'plugin.json');
    if (existsSync(emittedManifest)) {
      const pm = JSON.parse(readFileSync(emittedManifest, 'utf8'));
      pm.version = skillSemver();
      writeFileSync(emittedManifest, JSON.stringify(pm, null, 2) + '\n');
    }
    pluginEmitted = { path: pluginDir };
  } catch (e) {
    fail(`emissione layout-plugin fallita: ${e.message}`, 2);
  }
}

const tree = walk(stagingDir, stagingDir, []).sort();
const ok = lint.ok && (noArchive || archiveEmitted !== null);

// --- REPORT ------------------------------------------------------------------
if (jsonMode) {
  console.log(JSON.stringify({
    ok,
    lint: { ok: lint.ok, errors: lint.errors, warnings: lint.warnings, skill_md_lines: lint.skill_md_lines },
    manifest,
    tree,
    archive: archiveEmitted,
    plugin: pluginEmitted,
    staging_dir: stagingDir,
    injected_missing_ref: injectedMissing,
  }, null, 2));
} else {
  console.log('============================================================');
  console.log(' package_skill — assembla + lint strutturale + manifest + .skill (09 §3)');
  console.log(`   sorgente : ${SKILL_SRC}`);
  console.log(`   staging  : ${stagingDir}`);
  console.log('============================================================');
  console.log('');
  console.log('1) Albero assemblato (02 §4):');
  console.log(`   ${tree.length} file bundlati (esclusi node_modules/, package*.json, *.test.mjs)`);
  console.log('');
  console.log('2) LINT STRUTTURALE (deterministico, esito binario):');
  console.log(`   SKILL.md: ${lint.skill_md_lines} righe (limite ${SKILL_MD_MAX_LINES}, L-COL-014)`);
  console.log(`   frontmatter: name="${lint.frontmatter?.name}" description=${lint.frontmatter?.description ? 'non-vuota' : 'VUOTA'}`);
  console.log(`   riferimenti verificati: ${lint.refs.length}`);
  if (lint.ok) {
    console.log('   [OK] lint VERDE — nessun riferimento orfano, prompt + ruleset presenti');
  } else {
    console.log('   [FAIL] lint ROSSO:');
    for (const e of lint.errors) console.log(`     - ${e}`);
  }
  console.log('');
  console.log('2b) CONTROLLO DI RELEASE (un update version-gated deve poter consegnare):');
  for (const l of release.lines) console.log(`   ${l}`);
  console.log('');
  console.log('3) MANIFEST di versioni (09 §4):');
  console.log(`   skill:        ${manifest.name} v${manifest.skill_version} (SemVer)`);
  console.log(`   ruleset:      ${manifest.ruleset_version}`);
  console.log(`   oracoli (min): ${Object.entries(manifest.oracle_min_versions).map(([k, v]) => `${k}>=${v}`).join(', ') || '(nessuno)'}`);
  console.log(`   semgrep image: ${manifest.semgrep_image || '(n/d)'}`);
  const ecoStr = manifest.ecosystems.length > 0
    ? manifest.ecosystems.map((e) => `${e.id} ${e.version} (${e.tier})`).join(', ')
    : '(nessuno)';
  console.log(`   ecosistemi:   ${ecoStr}`);
  console.log(`   licenza:      ${manifest.license} · telemetria: ${manifest.telemetry}`);
  console.log('');
  console.log('4) ARCHIVIO .skill:');
  if (!lint.ok) {
    console.log('   [SKIP] lint ROSSO -> archivio NON emesso (09 §3: rosso -> il pacchetto non si emette)');
  } else if (noArchive) {
    console.log('   [SKIP] --no-archive');
  } else if (archiveEmitted) {
    console.log(`   [OK] emesso ${archiveEmitted.path} (${archiveEmitted.bytes} byte, tar+gzip deterministico)`);
  }
  console.log('');
  if (pluginArg) {
    console.log('4b) LAYOUT-PLUGIN (--plugin, target AGGIUNTIVO al .skill):');
    if (!lint.ok) {
      console.log('   [SKIP] lint ROSSO -> layout-plugin NON emesso');
    } else if (pluginEmitted) {
      console.log(`   [OK] emesso ${pluginEmitted.path} (.claude-plugin/ + hooks/ + skills/${SKILL_NAME}/)`);
    }
    console.log('');
  }
  console.log('------------------------------------------------------------');
  console.log(`=== package_skill: ${ok ? 'OK' : 'FAIL'} ===`);
  console.log('------------------------------------------------------------');
}

process.exit(ok ? 0 : 1);
