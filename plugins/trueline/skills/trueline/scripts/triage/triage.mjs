#!/usr/bin/env node
// =============================================================================
// triage.mjs — AGGREGATORE di triage (08): compone prioritizzazione (08 §3),
// spiegazione (08 §4) e policy conservativa sui falsi positivi (08 §5,
// L-COL-028) in UN'unica funzione pura sul finding model (04).
//
// E' l'ENTRYPOINT che il resto della pipeline (05 loop, report 04 §10) e il gate
// (eval/harness/m4_gate_check.mjs) chiamano: i mattoni vivono in
// trueline/scripts/findings/{prioritize,fp_policy,explain}.mjs; qui si ORCHESTRANO
// SENZA duplicarne la logica e SENZA mai oltrepassare il confine L-COL-002:
//
//   L'LLM/triage  riordina (prioritize), traduce (explain), segnala-con-evidenza
//                 un sospetto-FP (fp_policy) e propone una voce di allowlist.
//   L'LLM/triage  NON cambia severity/category, NON marca verified/risolto, NON
//                 rimuove/sopprime un finding (il sospetto-FP RESTA nel modello).
//
// PROPRIETA' GARANTITE (08 §3/§4/§5, L-COL-028, L-COL-002):
//   - DETERMINISMO: stesso input -> stesso ordine (prioritize e' totale/stabile;
//     non si usa Date.now/uuid/random). triage(x) === triage(x) per ordine.
//   - IL SOSPETTO-FP RESTA: flaggato-con-evidenza + proposta di allowlist
//     versionata ATTACCATA al finding, MAI scartato (nel-dubbio-si-tiene, 08 §5).
//   - IMMUTABILI: il flag-FP non tocca severity/category/fix_state (08 §2).
//   - VERO POSITIVO MAI LIQUIDATO: si flagga SOLO cio' che il chiamante indica in
//     opts.fpEvidence, e MAI un finding senza evidenza concreta (08 §5.1).
//   - SPIEGAZIONE ONESTA: nessun "sicuro"/"via libera" (08 §4, L-COL-006).
//
// API:
//   triage(findings, opts) -> { prioritized:[...], explanations:[...],
//                               fp:{ flagged:[...], proposals:[...] }, order:[...] }
//   opts:
//     fpEvidence  mappa fingerprint -> evidenza del sospetto-FP. Accetta sia una
//                 STRINGA (descrizione libera; il kind/locator si derivano dal
//                 finding) sia un oggetto strutturato { kind, detail, locator }
//                 (passato verbatim a fp_policy). Solo i finding ELENCATI qui
//                 sono candidati al flag-FP: nessun auto-flag (08 §5.1).
//     explain     se true (default) allega a ciascun finding una spiegazione
//                 (08 §4) in `explanation` e la raccoglie in `explanations`.
//     appendRationale  inoltrato a prioritize (default true): scrive la `notes`
//                 di razionale d'ordine.
//
// `prioritized` e' l'array ORDINATO (08 §3) con, per ciascun finding flaggato-FP,
// il blocco `triage_fp` (notes [suspected-fp]) e la PROPOSTA di allowlist in
// `allowlist_proposal` (cosi report/diff la vedono accanto al finding). L'ordine
// e' una RACCOMANDAZIONE; il cancello resta oracolo + soglie (03 §7).
//
// Node ESM, solo built-in + i tre moduli findings/ (anch'essi solo built-in).
// Nessuna dipendenza, nessuna rete, NESSUN git.
// =============================================================================

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

import { prioritize } from '../findings/prioritize.mjs';
import { applyFpPolicy } from '../findings/fp_policy.mjs';
import { explainFinding } from '../findings/explain.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Identita stabile di un finding (per appaiare evidenza/risultati). Mai casuale.
function fpOf(f) {
  return (f && (f.fingerprint || f.id)) || JSON.stringify(f);
}

// -----------------------------------------------------------------------------
// Coercizione dell'evidenza del chiamante in evidenza STRUTTURATA per fp_policy
// (08 §5.1: { kind, detail, locator } concreti e controllabili). Il chiamante
// puo' passare:
//   - un oggetto { kind, detail, locator }  -> usato verbatim (validato a valle);
//   - una stringa libera                    -> kind DERIVATO dal testo, detail =
//       la stringa, locator DERIVATO dalla location del finding (file:riga).
// La derivazione NON inventa: il locator viene dalla `location` reale del finding;
// senza una location utile, il locator resta vuoto e fp_policy RIFIUTA il flag
// (nel-dubbio-si-tiene): un finding senza evidenza concreta NON e' un FP.
// -----------------------------------------------------------------------------
function coerceEvidence(raw, finding) {
  if (raw && typeof raw === 'object') {
    // Gia' strutturata: completa il locator dal finding se assente.
    const locator = raw.locator && String(raw.locator).trim()
      ? raw.locator
      : locatorOf(finding);
    return { kind: raw.kind, detail: raw.detail, locator };
  }
  const detail = String(raw == null ? '' : raw).trim();
  return { kind: inferKind(detail, finding), detail, locator: locatorOf(finding) };
}

// Locator concreto dalla location del finding (DOVE controllare il sospetto-FP).
function locatorOf(finding) {
  const loc = (finding && finding.location) || {};
  if (!loc.file) return '';
  const line = loc.start_line != null ? `:${loc.start_line}` : '';
  return `${loc.file}${line}`;
}

// Deriva il kind di evidenza (tra quelli ammessi da fp_policy) dal testo libero +
// dall'oracolo del finding. Conservativo: se il testo nomina un entrypoint/import
// dinamico/fixture lo si riconosce; altrimenti per il dead-code (knip) il caso
// piu' comune e' l'entrypoint del framework. Non e' un giudizio di merito: e' SOLO
// la categorizzazione dell'evidenza fornita dal chiamante (il flag resta
// subordinato alla validazione di fp_policy e all'azione umana).
function inferKind(text, finding) {
  const t = String(text || '').toLowerCase();
  if (/import\s*dinamic|dynamic[-\s]?import/.test(t)) return 'dynamic-import';
  if (/entrypoint|entry[-\s]?point|router|framework/.test(t)) return 'framework-entrypoint';
  if (/fixture|test|seed/.test(t)) return 'test-fixture';
  if (/convenzione|convention|magia|magic/.test(t)) return 'framework-convention';
  if (/allowlist|allow[-\s]?list|candidat/.test(t)) return 'allowlist-candidate';
  if (/config|documentat/.test(t)) return 'documented-config';
  // Default per categoria: il dead-code (knip) e' il caso piu' affilato dei FP
  // (08 §5.3) e l'entrypoint del framework e' l'ipotesi di FP piu' frequente.
  const oracle = finding && finding.source_oracle && finding.source_oracle.oracle;
  if ((finding && finding.category === 'dead-code') || oracle === 'knip') {
    return 'framework-entrypoint';
  }
  // Nessuna categoria di evidenza riconoscibile: fp_policy rifiutera' (corretto).
  return 'unknown';
}

/**
 * TRIAGE: compone prioritize + fp_policy + explain in un unico passaggio puro.
 *
 * @param {object[]} findings  array di finding (finding model 04). NON mutato.
 * @param {object}   [opts]
 * @param {Object<string,(string|object)>} [opts.fpEvidence]  fingerprint -> evidenza
 *        del sospetto-FP (stringa o { kind, detail, locator }). Solo questi sono
 *        candidati al flag-FP (nessun auto-flag, 08 §5.1).
 * @param {boolean}  [opts.explain=true]          allega la spiegazione (08 §4).
 * @param {boolean}  [opts.appendRationale=true]  scrive la notes di razionale (08 §3).
 * @returns {{ prioritized: object[], order: string[], explanations: object[],
 *            fp: { flagged: object[], proposals: object[] } }}
 */
export function triage(findings, opts = {}) {
  if (!Array.isArray(findings)) {
    throw new Error('triage: atteso un array di finding');
  }
  const fpEvidence = (opts && opts.fpEvidence) || {};
  const doExplain = opts.explain !== false;
  const appendRationale = opts.appendRationale !== false;

  // 1) FP POLICY (08 §5, L-COL-028) — PRIMA della prioritizzazione, cosi che la
  //    `notes` [suspected-fp] e la proposta di allowlist viaggino con il finding
  //    nell'ordinamento. Si flagga SOLO cio' che il chiamante indica in
  //    fpEvidence, MAI in autonomia (no auto-flag); senza evidenza concreta il
  //    finding resta NORMALE (nel-dubbio-si-tiene). Il finding RESTA SEMPRE nel
  //    modello: applyFpPolicy non rimuove nulla.
  const fpFlagged = [];
  const fpProposals = [];
  const afterFp = findings.map((f) => {
    const key = fpOf(f);
    if (!Object.prototype.hasOwnProperty.call(fpEvidence, key)) {
      return f; // non candidato: invariato.
    }
    const evidence = coerceEvidence(fpEvidence[key], f);
    const res = applyFpPolicy(f, evidence);
    if (!res.flagged) {
      // Evidenza non concreta: NON e' un flag-FP (08 §5.1). Il finding resta
      // normale e nel modello. Non si scarta, non si degrada.
      return res.finding;
    }
    // Flaggato: ATTACCA la proposta di allowlist versionata al finding (cosi il
    // report/diff la vede accanto). Campi immutabili (severity/category/fix_state)
    // restano quelli che applyFpPolicy ha gia' preservato.
    const annotated = res.allowlistProposal
      ? { ...res.finding, allowlist_proposal: res.allowlistProposal }
      : res.finding;
    fpFlagged.push(annotated);
    if (res.allowlistProposal) fpProposals.push(res.allowlistProposal);
    return annotated;
  });

  // 2) PRIORITIZZAZIONE (08 §3) — funzione d'ordine documentata e riproducibile.
  //    Pura, totale, stabile: stesso input -> stesso ordine (determinismo).
  const prioritized = prioritize(afterFp, { appendRationale });

  // 3) SPIEGAZIONE (08 §4) — opzionale; allegata a ciascun finding senza alterare
  //    severity/category/stato. Mai "sicuro"/"via libera" (vincolo di explain).
  let explanations = [];
  if (doExplain) {
    for (const f of prioritized) {
      const ex = explainFinding(f);
      f.explanation = ex;
      explanations.push({ fingerprint: fpOf(f), ...ex });
    }
  }

  return {
    prioritized,
    order: prioritized.map((f) => fpOf(f)),
    explanations,
    fp: { flagged: fpFlagged, proposals: fpProposals },
  };
}

export default triage;

// =============================================================================
// CLI: node triage.mjs <findings.json|-> [--no-explain] [--no-notes]
//                       [--fp-evidence <fp-evidence.json>]
//   Legge un array di finding (file o stdin "-"), applica il triage e stampa
//   { prioritized, order, explanations, fp }. --fp-evidence carica la mappa
//   fingerprint->evidenza. Deterministico, solo built-in.
// =============================================================================
function parseArgs(argv) {
  const positional = [];
  const flags = { explain: true, notes: true, fpEvidenceFile: null };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--no-explain') flags.explain = false;
    else if (a === '--no-notes') flags.notes = false;
    else if (a === '--fp-evidence') flags.fpEvidenceFile = argv[++i];
    else if (a.startsWith('--fp-evidence=')) flags.fpEvidenceFile = a.slice('--fp-evidence='.length);
    else if (!a.startsWith('--')) positional.push(a);
  }
  return { positional, flags };
}

function main(argv) {
  const { positional, flags } = parseArgs(argv);
  const src = positional[0];
  if (!src) {
    process.stderr.write(
      'uso: node triage.mjs <findings.json|-> [--no-explain] [--no-notes] '
      + '[--fp-evidence <fp-evidence.json>]\n'
      + 'Compone prioritize (08 §3) + fp_policy (08 §5) + explain (08 §4). '
      + 'Non tocca severity/category; il sospetto-FP RESTA nel modello.\n',
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
  let fpEvidence = {};
  if (flags.fpEvidenceFile) {
    try {
      fpEvidence = JSON.parse(readFileSync(resolve(flags.fpEvidenceFile), 'utf8'));
    } catch (err) {
      process.stderr.write(`fp-evidence non leggibile: ${err.message}\n`);
      return 2;
    }
  }
  let out;
  try {
    out = triage(findings, { fpEvidence, explain: flags.explain, appendRationale: flags.notes });
  } catch (err) {
    process.stderr.write(`errore di triage: ${err.message}\n`);
    return 1;
  }
  process.stdout.write(JSON.stringify(out, null, 2) + '\n');
  return 0;
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1] === __filename) {
  process.exit(main(process.argv));
}
