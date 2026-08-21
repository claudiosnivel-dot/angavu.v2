#!/usr/bin/env node
// =============================================================================
// prioritize.mjs — ordinamento riproducibile dei finding (08 §3, "prioritizzazione
// spietata"). Meccanismo di L-COL-002: l'LLM RIORDINA e TRADUCE i fatti
// dell'oracolo; NON li riscrive e NON emette verdetti.
//
// COSA E' (e cosa NON e'):
//   - E' una FUNZIONE PURA sul finding model (04, finding.schema.json): prende un
//     array di finding, restituisce un NUOVO array RIORDINATO + una `notes` di
//     razionale per ciascuno. Deterministica: stesso input -> stesso output.
//   - NON e' un re-scoring: non tocca MAI `severity` ne `category` (immutabili,
//     dall'oracolo). Non cambia il gating del checkpoint (lo fanno le soglie,
//     03 §7 / thresholds). Cambia SOLO l'ordine di presentazione e aggiunge una
//     `notes` motivata (08 §3, §5.4).
//
// FUNZIONE D'ORDINE (08 §3, documentata e riproducibile — non a sensazione):
//
//   blocca-sempre (secret)  >  nuovo & sopra-soglia  >  in-scope  >
//   severita  >  categoria-killer (rls/authz su Supabase)  >
//   pre-existing/advisory in coda
//
// "Spietata" = far emergere i POCHI che contano in cima senza seppellire l'umano
// sotto l'advisory; il debito pre-esistente (BUILD) sta in coda, non inchioda il
// round. L'ordine e' una RACCOMANDAZIONE; il cancello resta oracolo + soglie.
//
// Node ESM, solo moduli built-in. Nessuna dipendenza, nessuna rete, nessun git.
// =============================================================================

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// -----------------------------------------------------------------------------
// Politica di blocco per categoria (eco di 03 §7 / thresholds, NON una sua copia
// autoritativa: serve SOLO a calcolare l'ordine di presentazione, mai il gate).
// `secret` blocca sempre; rls/authz sono le "categorie-killer" su Supabase.
// -----------------------------------------------------------------------------
const ALWAYS_BLOCK = new Set(['secret']);
const KILLER_CATEGORIES = new Set(['rls', 'authz']);

// Severita -> rango numerico (piu' alto = piu' urgente). Solo per ORDINARE:
// non altera mai il campo `severity` del finding.
const SEVERITY_RANK = { CRITICAL: 4, HIGH: 3, MEDIUM: 2, LOW: 1 };

// Soglia "sopra-soglia" ai fini della SOLA presentazione: un finding e'
// considerato "sopra-soglia" per l'ordinamento se la sua severita e' >= MEDIUM
// OPPURE se la categoria blocca-sempre (secret) a prescindere dalla severita
// (03 §7: SECRET_GATE = always-block, severita inapplicabile). Questo NON e' il
// gate: e' solo l'euristica di risalita in cima.
const PRESENTATION_THRESHOLD_RANK = SEVERITY_RANK.MEDIUM;

/**
 * Un finding e' "sopra-soglia di presentazione"? (NON e' il gate del checkpoint.)
 * Vero se blocca-sempre (secret) o se severita >= MEDIUM.
 */
function isAbovePresentationThreshold(f) {
  if (ALWAYS_BLOCK.has(f.category)) return true;
  return (SEVERITY_RANK[f.severity] || 0) >= PRESENTATION_THRESHOLD_RANK;
}

/**
 * Chiave di ordinamento STABILE per un finding. Restituisce un array di numeri:
 * confronto lessicografico discendente (chiave piu' "alta" = piu' in cima).
 * Ogni componente riflette UN gradino della funzione d'ordine 08 §3, nell'ordine
 * esatto in cui i gradini sono enunciati. Tutti i fattori provengono dal finding
 * model; nessuno e' inventato.
 *
 *   [0] blocca-sempre (secret)         1/0
 *   [1] nuovo & sopra-soglia           1/0   (baseline_status=new AND above-threshold)
 *   [2] in-scope                       1/0   (scope_relevance=in-scope)
 *   [3] severita                       4..1  (CRITICAL..LOW) — solo ordinamento
 *   [4] categoria-killer (rls/authz)   1/0
 *   [5] pre-existing in coda           1/0   (1 se NON pre-existing; pre-existing affonda)
 */
function sortKey(f) {
  const isSecret = ALWAYS_BLOCK.has(f.category) ? 1 : 0;
  const isNew = f.baseline_status === 'new';
  const aboveThr = isAbovePresentationThreshold(f);
  const newAndAbove = isNew && aboveThr ? 1 : 0;
  const inScope = f.scope_relevance === 'in-scope' ? 1 : 0;
  const sevRank = SEVERITY_RANK[f.severity] || 0;
  const isKiller = KILLER_CATEGORIES.has(f.category) ? 1 : 0;
  // pre-existing affonda in coda: 1 quando NON e' pre-existing.
  const notPreExisting = f.baseline_status === 'pre-existing' ? 0 : 1;
  return [isSecret, newAndAbove, inScope, sevRank, isKiller, notPreExisting];
}

/**
 * Confronto fra due chiavi (array di numeri), discendente. A parita' totale,
 * il tie-break e' il `fingerprint` (lessicografico ascendente): garantisce un
 * ordine TOTALE e STABILE indipendente dall'ordine di input (riproducibilita,
 * L-COL-002). Nessun fattore casuale, nessuna data di sistema.
 */
function compareFindings(a, b) {
  const ka = sortKey(a);
  const kb = sortKey(b);
  for (let i = 0; i < ka.length; i++) {
    if (ka[i] !== kb[i]) return kb[i] - ka[i]; // discendente
  }
  // Tie-break deterministico e totale.
  const fa = a.fingerprint || '';
  const fb = b.fingerprint || '';
  if (fa < fb) return -1;
  if (fa > fb) return 1;
  return 0;
}

/**
 * Razionale leggibile della posizione di un finding, scritto in `notes`
 * (08 §3: "piu' una motivazione in notes"). E' PROSA di razionale d'ordine,
 * MAI un via libera (08 §4: mai "e' sicuro"). Non rivendica sicurezza, non
 * promuove stati: spiega solo PERCHE' sta dove sta nella coda.
 */
export function priorityRationale(f, rank) {
  const reasons = [];
  if (ALWAYS_BLOCK.has(f.category)) {
    reasons.push('categoria blocca-sempre (secret): in cima a prescindere dalla severita (03 §7)');
  }
  if (f.baseline_status === 'new' && isAbovePresentationThreshold(f)) {
    reasons.push('nuovo e sopra-soglia di presentazione');
  } else if (f.baseline_status === 'pre-existing') {
    reasons.push('debito pre-esistente: in coda, non inchioda il round (08 §3)');
  }
  if (f.scope_relevance === 'in-scope') {
    reasons.push('in-scope per il macrotask corrente');
  } else if (f.scope_relevance === 'out-of-scope') {
    reasons.push('out-of-scope per il macrotask corrente');
  }
  reasons.push(`severita ${f.severity} (immutabile, dall'oracolo)`);
  if (KILLER_CATEGORIES.has(f.category)) {
    reasons.push(`categoria-killer ${f.category} su Supabase`);
  }
  const pos = `posizione ${rank + 1} nell'ordine di presentazione`;
  return `${pos}. Razionale: ${reasons.join('; ')}. L'ordine e' una raccomandazione (08 §3); il cancello resta oracolo + soglie (03 §7), severita/categoria NON modificate.`;
}

/**
 * PRIORITIZZA: ordina i finding secondo la funzione d'ordine 08 §3 e scrive in
 * ciascuno una `notes` di razionale. FUNZIONE PURA: non muta gli input (clona),
 * non tocca severity/category, non cambia fix_state. Restituisce un NUOVO array.
 *
 * @param {object[]} findings  array di finding (finding model 04)
 * @param {object}   [opts]
 * @param {boolean}  [opts.appendRationale=true]  se true, scrive `notes` con il razionale
 *                   (preservando una eventuale `notes` preesistente, anteposta).
 * @returns {object[]} nuovo array ordinato (copie dei finding)
 */
export function prioritize(findings, opts = {}) {
  const appendRationale = opts.appendRationale !== false;
  if (!Array.isArray(findings)) {
    throw new Error('prioritize: atteso un array di finding');
  }
  // Clona (no-mutazione) e ordina con confronto totale/stabile.
  const cloned = findings.map((f) => ({ ...f, location: { ...f.location } }));
  cloned.sort(compareFindings);

  if (appendRationale) {
    cloned.forEach((f, i) => {
      const rationale = priorityRationale(f, i);
      const prev = f.notes ? `${String(f.notes).trim()} ` : '';
      f.notes = `${prev}[triage] ${rationale}`;
    });
  }
  return cloned;
}

/**
 * Variante che restituisce solo l'ordine dei fingerprint (utile a test/diff
 * stabili senza confronto dell'intero oggetto). Pura.
 */
export function priorityOrder(findings) {
  return prioritize(findings, { appendRationale: false }).map((f) => f.fingerprint);
}

// =============================================================================
// CLI: node prioritize.mjs <findings.json|-> [--no-notes]
//   Legge un array di finding (file o stdin "-"), stampa l'array ORDINATO con
//   `notes` di razionale. Solo built-in, deterministico.
// =============================================================================
function main(argv) {
  const args = argv.slice(2);
  const noNotes = args.includes('--no-notes');
  const positional = args.filter((a) => !a.startsWith('--'));
  const src = positional[0];
  if (!src) {
    process.stderr.write(
      'uso: node prioritize.mjs <findings.json|-> [--no-notes]\n' +
        'Ordina i finding (08 §3) e scrive notes di razionale. Non tocca severity/category.\n',
    );
    return 2;
  }
  let findings;
  try {
    const raw = src === '-' ? readFileSync(0, 'utf8') : readFileSync(resolve(src), 'utf8');
    findings = JSON.parse(raw);
  } catch (err) {
    process.stderr.write(`impossibile leggere/parsare ${src}: ${err.message}\n`);
    return 2;
  }
  let ordered;
  try {
    ordered = prioritize(findings, { appendRationale: !noNotes });
  } catch (err) {
    process.stderr.write(`errore di prioritizzazione: ${err.message}\n`);
    return 1;
  }
  process.stdout.write(JSON.stringify(ordered, null, 2) + '\n');
  return 0;
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1] === __filename) {
  process.exit(main(process.argv));
}
