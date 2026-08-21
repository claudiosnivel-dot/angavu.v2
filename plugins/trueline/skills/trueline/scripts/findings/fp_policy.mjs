#!/usr/bin/env node
// =============================================================================
// fp_policy.mjs — gestione CONSERVATIVA dei falsi positivi (08 §5, L-COL-028).
//
// LA TESI: l'LLM e' il triatore naturale dei FP di SAST (semgrep) e dead-code
// (knip), ma se puo' LIQUIDARE un finding ridiventa giudice e la tesi oracle-first
// crolla (L-COL-002). Questo modulo da' all'LLM un ruolo UTILE ma RISTRETTO,
// implementato come MECCANISMO DETERMINISTICO (non LLM-at-gate-time):
//
//   L'LLM puo'  (a) marcare un finding come SOSPETTO FALSO POSITIVO con EVIDENZA
//               CONCRETA e (b) abbassarne la priorita' di presentazione.
//   L'LLM NON puo'  rimuovere / sopprimere / marcare risolto / cambiare severita'
//               o categoria / contarlo come gestito.
//
// COSA FA QUESTO CODICE (le parti deterministiche/controllabili della policy):
//   1) flagSuspectedFp(finding, evidence) — annota nel finding un blocco
//      `triage_fp` (in coda alla `notes`, formato strutturato e parsabile) SENZA
//      toccare severity/category/fix_state. RICHIEDE evidenza concreta: senza,
//      NON e' un flag-FP (08 §5.1, "requisito di evidenza"); torna il finding
//      INVARIATO. Default: nel-dubbio-si-tiene.
//   2) proposeAllowlistEntry(finding, evidence) — genera una PROPOSTA di voce di
//      allowlist VERSIONATA nel formato che l'ORACOLO legge (.gitleaks.toml /
//      knip ignore / # nosemgrep), con l'evidenza come commento di giustificazione.
//      E' una PROPOSTA: l'umano approva, la voce viene committata (dal git
//      dell'orchestratore, MAI da qui), e al run successivo e' l'ORACOLO STESSO
//      a non emettere piu' il finding (la soppressione resta dell'oracolo).
//   3) Il finding RESTA nel modello e nel report finche' l'umano non agisce: il
//      flag tocca SOLO ordine di presentazione e coda di revisione, MAI il gate.
//
// Node ESM, solo moduli built-in. Nessuna dipendenza, nessuna rete, NESSUN git.
// =============================================================================

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Marcatore strutturato che il flag scrive in `notes` (parsabile a valle/report).
const FP_MARKER = '[suspected-fp]';

// Tipi di evidenza CONCRETA ammessi (08 §5.1: "un sito di import dinamico, una
// convenzione del framework, una fixture di test, un candidato per l'allowlist").
// L'evidenza deve essere CONTROLLABILE: non "secondo me va bene".
const EVIDENCE_KINDS = new Set([
  'dynamic-import',      // sito di import dinamico (knip)
  'framework-entrypoint',// entry point del framework (knip)
  'test-fixture',        // fixture/seed di test (es. segreto finto in un test)
  'framework-convention',// magia del framework che il tool non vede
  'allowlist-candidate', // gia' identificato come candidato all'allowlist
  'documented-config',   // riferimento a config che spiega il pattern
]);

/**
 * Valida che l'evidenza sia CONCRETA e controllabile (08 §5.1, requisito di
 * evidenza). Restituisce { ok, reason }. Senza evidenza valida -> NON e' un
 * flag-FP: il chiamante lascia il finding NORMALE (nel-dubbio-si-tiene).
 *
 * Un'evidenza valida ha:
 *   - kind in EVIDENCE_KINDS (categoria di evidenza nota);
 *   - detail non vuoto (la descrizione concreta e controllabile);
 *   - locator non vuoto (DOVE controllarla: file:riga, nome config, ecc.).
 */
export function validateEvidence(evidence) {
  if (!evidence || typeof evidence !== 'object') {
    return { ok: false, reason: 'evidenza assente: senza evidenza concreta NON e\' un flag-FP (nel-dubbio-si-tiene)' };
  }
  const { kind, detail, locator } = evidence;
  if (!EVIDENCE_KINDS.has(kind)) {
    return { ok: false, reason: `kind di evidenza non riconosciuto: "${kind}" (ammessi: ${[...EVIDENCE_KINDS].join(', ')})` };
  }
  if (!detail || !String(detail).trim()) {
    return { ok: false, reason: 'detail mancante: l\'evidenza deve descrivere il fatto concreto, non un parere' };
  }
  if (!locator || !String(locator).trim()) {
    return { ok: false, reason: 'locator mancante: l\'evidenza deve dire DOVE e\' controllabile (file:riga, config, ...)' };
  }
  return { ok: true, reason: 'evidenza concreta e controllabile' };
}

/**
 * FLAGGA un finding come SOSPETTO FALSO POSITIVO con evidenza concreta.
 *
 * Asimmetria conservativa (08 §5.1): un falso "e' un falso positivo" E' il falso
 * via libera che L-COL-006 vieta; quindi nel dubbio si TIENE. Questo flag NON
 * rimuove, NON sopprime, NON marca risolto, NON cambia severity/category/
 * fix_state. Aggiunge SOLO:
 *   - una `notes` strutturata [suspected-fp] con l'evidenza;
 *   - un marcatore (parsabile) che la presentazione usa per la coda di revisione.
 *
 * @returns {object} { finding, flagged, reason }
 *   - flagged=false + finding INVARIATO se l'evidenza non e' concreta (08 §5.1).
 *   - flagged=true  + finding ANNOTATO (copia) altrimenti. Il finding resta
 *     comunque NEL MODELLO: non viene mai eliminato.
 */
export function flagSuspectedFp(finding, evidence) {
  const v = validateEvidence(evidence);
  if (!v.ok) {
    // Senza evidenza concreta NON e' un flag-FP: il finding resta NORMALE.
    return { finding, flagged: false, reason: v.reason };
  }
  // Copia (no-mutazione). NON tocchiamo severity/category/fix_state/baseline.
  const out = { ...finding, location: { ...finding.location } };
  const note =
    `${FP_MARKER} sospetto falso positivo (kind=${evidence.kind}; ` +
    `evidenza: ${String(evidence.detail).trim()}; controllabile in: ${String(evidence.locator).trim()}). ` +
    'Portato all\'umano: SOLO l\'umano ne dispone (accepted-risk o conferma-e-allowlist). ' +
    'Il finding RESTA nel modello/report finche\' l\'umano non agisce (L-COL-028); ' +
    'severita/categoria/stato NON modificati.';
  const prev = out.notes ? `${String(out.notes).trim()} ` : '';
  out.notes = `${prev}${note}`;
  return { finding: out, flagged: true, reason: v.reason };
}

/**
 * E' un finding gia' flaggato come sospetto-FP? (parsa il marcatore in notes).
 */
export function isSuspectedFp(finding) {
  return Boolean(finding && typeof finding.notes === 'string' && finding.notes.includes(FP_MARKER));
}

// -----------------------------------------------------------------------------
// PROPOSTA di voce di allowlist VERSIONATA (08 §5.2). Il FP confermato non vive
// nella testa dell'LLM: vive nella config che l'ORACOLO legge. L'LLM PROPONE,
// l'umano APPROVA, la voce viene COMMITTATA (git dell'orchestratore, mai qui).
// Restituiamo { target, path, snippet }: `snippet` e' testo pronto da AGGIUNGERE
// al file `path`, con l'evidenza come commento di giustificazione.
// -----------------------------------------------------------------------------

/** Sceglie il formato di allowlist in base all'oracolo che ha emesso il finding. */
function allowlistTargetFor(finding) {
  const oracle = finding && finding.source_oracle && finding.source_oracle.oracle;
  switch (oracle) {
    case 'gitleaks':
      return 'gitleaks';
    case 'knip':
      return 'knip';
    case 'semgrep':
      return 'semgrep';
    default:
      // osv/rls-check non hanno un'allowlist "inline" in questo schema: si
      // gestiscono come accepted-risk umano, non come voce di allowlist proposta.
      return null;
  }
}

/** Escapa una stringa per inserirla in un commento TOML/YAML su singola riga. */
function oneLineComment(s) {
  return String(s).replace(/[\r\n]+/g, ' ').trim();
}

/**
 * PROPONE una voce di allowlist versionata per un FP confermabile dall'umano.
 * Deterministica: stesso finding+evidenza -> stesso snippet. NON scrive su disco,
 * NON committa: restituisce il testo che l'umano (via orchestratore) applichera'.
 *
 * @returns {object|null} { target, path, snippet, requiresHumanApproval:true }
 *   oppure null se l'oracolo non ha un meccanismo di allowlist inline.
 */
export function proposeAllowlistEntry(finding, evidence) {
  const target = allowlistTargetFor(finding);
  if (!target) return null;
  const v = validateEvidence(evidence);
  // La proposta di allowlist e' SEMPRE accompagnata dall'evidenza: senza, non
  // proponiamo (stesso requisito del flag, 08 §5.1).
  if (!v.ok) return null;

  const ruleId = (finding.source_oracle && finding.source_oracle.rule_id) || 'unknown';
  const file = (finding.location && finding.location.file) || '';
  const line = (finding.location && finding.location.start_line) || 0;
  const justify = oneLineComment(
    `${evidence.kind}: ${evidence.detail} (controllabile in ${evidence.locator})`,
  );
  const provenance = 'PROPOSTA triage (08 §5.2) — richiede APPROVAZIONE UMANA e commit dell\'orchestratore (L-COL-028)';

  if (target === 'gitleaks') {
    // .gitleaks.toml: allowlist per regola+path, con commento di giustificazione.
    const path = '.gitleaks.toml';
    const snippet =
      `# ${provenance}\n` +
      `# giustificazione: ${justify}\n` +
      `[[allowlist]]\n` +
      `  description = "FP confermato: ${oneLineComment(ruleId)} in ${file} (rivedere prima di mergere)"\n` +
      `  regexTarget = "match"\n` +
      `  paths = ['''${escapeToml(file)}''']\n`;
    return { target, path, snippet, requiresHumanApproval: true };
  }

  if (target === 'knip') {
    // knip ignore: per i FP di dead-code (import dinamici, entry del framework).
    // Si propone una voce `ignore`/`entry` in knip.json (08 §5.3, L-COL-021).
    const path = 'knip.json';
    const key = evidence.kind === 'framework-entrypoint' ? 'entry' : 'ignore';
    const snippet =
      `// ${provenance}\n` +
      `// giustificazione: ${justify}\n` +
      `// aggiungere a knip.json -> "${key}": [ ..., "${escapeJson(file)}" ]\n` +
      `{ "${key}": ["${escapeJson(file)}"] }\n`;
    return { target, path, snippet, requiresHumanApproval: true };
  }

  // semgrep: commento # nosemgrep ANCORATO alla riga del match, con regola e
  // giustificazione. NB: e' una PROPOSTA testuale; l'inserimento nel sorgente
  // resta gate umano + commit dell'orchestratore.
  const path = file;
  const snippet =
    `# ${provenance}\n` +
    `# giustificazione: ${justify}\n` +
    `# da inserire sulla riga ${line} di ${file}:\n` +
    `# nosemgrep: ${oneLineComment(ruleId)}\n`;
  return { target: 'semgrep', path, snippet, requiresHumanApproval: true };
}

function escapeToml(s) {
  return String(s).replace(/'''/g, "''\\'");
}
function escapeJson(s) {
  return String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

/**
 * Applica la policy FP a UN finding: valida l'evidenza, e SE concreta flagga +
 * propone l'allowlist. SE non concreta, NON flagga (nel-dubbio-si-tiene) e
 * restituisce il finding invariato. Pura.
 *
 * @returns {object} { finding, flagged, allowlistProposal, reason }
 */
export function applyFpPolicy(finding, evidence) {
  const { finding: flaggedFinding, flagged, reason } = flagSuspectedFp(finding, evidence);
  const allowlistProposal = flagged ? proposeAllowlistEntry(finding, evidence) : null;
  return { finding: flaggedFinding, flagged, allowlistProposal, reason };
}

// =============================================================================
// CLI: node fp_policy.mjs <finding.json|-> --evidence-kind <k> --detail <d> --locator <l>
//   Flagga UN finding (stdin/file) come sospetto-FP con evidenza e stampa
//   { finding, flagged, allowlistProposal, reason }. Senza evidenza valida,
//   flagged=false e finding invariato (08 §5.1). Deterministico.
// =============================================================================
function parseArgs(argv) {
  const positional = [];
  const flags = {};
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const key = a.slice(2);
      const val = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : 'true';
      flags[key] = val;
    } else {
      positional.push(a);
    }
  }
  return { positional, flags };
}

function main(argv) {
  const { positional, flags } = parseArgs(argv);
  const src = positional[0];
  if (!src) {
    process.stderr.write(
      'uso: node fp_policy.mjs <finding.json|-> --evidence-kind <k> --detail <d> --locator <l>\n' +
        `kind ammessi: ${[...EVIDENCE_KINDS].join(', ')}\n`,
    );
    return 2;
  }
  let finding;
  try {
    const raw = src === '-' ? readFileSync(0, 'utf8') : readFileSync(resolve(src), 'utf8');
    finding = JSON.parse(raw);
  } catch (err) {
    process.stderr.write(`impossibile leggere/parsare ${src}: ${err.message}\n`);
    return 2;
  }
  const evidence = {
    kind: flags['evidence-kind'],
    detail: flags.detail,
    locator: flags.locator,
  };
  const result = applyFpPolicy(finding, evidence);
  process.stdout.write(JSON.stringify(result, null, 2) + '\n');
  return 0;
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1] === __filename) {
  process.exit(main(process.argv));
}
