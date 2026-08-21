#!/usr/bin/env node
// =============================================================================
// explain.mjs — generatore di spiegazione in linguaggio semplice (08 §4).
//
// Trasforma un finding strutturato e secco (rule_id, CWE, riga) in qualcosa su
// cui AGIRE, restando dentro il confine di L-COL-002 (l'LLM TRADUCE i fatti
// dell'oracolo; non li riscrive, non emette verdetti). Quattro elementi (08 §4):
//
//   1. Cos'e'           — in una frase, senza gergo non spiegato.
//   2. Perche' conta    — citando uno STANDARD NOMINATO di 07 (es. "viola A05:2025
//                         / lo standard RLS R3"), NON un parere.
//   3. Dove             — da `location` (file, riga, simbolo).
//   4. Direzione fix    — da `remediation_hint` (oracolo/convenzione, 04); NON un
//                         verdetto dell'LLM.
//
// VINCOLI (08 §4):
//   - Mai gonfiare la certezza, mai "e' sicuro": lo stato resta quello del finding
//     (un problema RILEVATO, non un'assoluzione). Lo verifichiamo nel self-test.
//   - Segreti mai in chiaro nell'evidenza (04 §7): usiamo SOLO l'`evidence` gia'
//     redatta a monte da normalize; non reidratiamo mai un valore.
//   - Proporzionato: un LOW advisory non si spiega come un CRITICAL.
//   - Framing onesto (L-COL-006): si spiega il problema; mai un "sei al sicuro".
//
// Lo standard nominato citato proviene da una MAPPA DETERMINISTICA (07 §3/§4/§5),
// NON da un giudizio LLM a runtime: stesso finding -> stessa citazione.
//
// Node ESM, solo moduli built-in. Nessuna dipendenza, nessuna rete, nessun git.
// =============================================================================

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// -----------------------------------------------------------------------------
// MAPPA STANDARD NOMINATI (07). Deterministica: categoria (+ rule_id per RLS) ->
// { what, why, asvsTopic }. NON e' un re-scoring ne un giudizio; e' il vocabolario
// che 07 §3 impone al posto degli aggettivi. I codici OWASP 2025 e i CWE
// AUTORITATIVI restano quelli del finding (owasp/cwe); qui diamo la PROSA "cos'e'
// / perche' conta" ancorata allo standard, e il topic ASVS 5.0 (07 §3.2).
// -----------------------------------------------------------------------------
const CATEGORY_STANDARD = {
  secret: {
    what: 'una credenziale/segreto (chiave, token o password) compare nel sorgente invece che in una variabile d\'ambiente o secret manager',
    why: 'un segreto nel codice e\' esponibile a chiunque legga il repo o la history; la service_role key, in piu\', bypassa RLS ed espone l\'intero DB',
    asvsTopic: 'Configuration & Secret Management',
  },
  injection: {
    what: 'input non fidato finisce in una query/comando costruito per concatenazione invece che con binding parametrizzato',
    why: 'un input ostile puo\' cambiare la struttura della query/comando ed eseguire operazioni non previste (CWE-89 SQL injection, CWE-78 command injection)',
    asvsTopic: 'Injection Prevention',
  },
  authz: {
    what: 'una route/handler che muta dati non verifica l\'identita\'/ruolo del chiamante prima di scrivere',
    why: 'senza authz applicativa un chiamante puo\' agire per conto di altri; con la service_role (che bypassa RLS) il controllo applicativo e\' l\'unica difesa rimasta',
    asvsTopic: 'Access Control / Authorization',
  },
  rls: {
    what: 'una tabella/policy Row Level Security non isola l\'accesso per identita\'/tenant come richiede lo standard RLS nominato (07 §5)',
    why: 'senza RLS corretta una tabella public e\' leggibile/scrivibile via Data API oltre il dovuto: e\' rottura del controllo d\'accesso',
    asvsTopic: 'Access Control / Authorization',
  },
  crypto: {
    what: 'si usa una primitiva crittografica debole o un confronto non timing-safe dove servirebbe forza crittografica',
    why: 'random non-crittografico, hash deboli o confronti non costanti rendono prevedibili token/segreti o trapelano informazione (CWE-338/327/208)',
    asvsTopic: 'Cryptography',
  },
  'dependency-vuln': {
    what: 'una dipendenza dichiarata e\' a una versione con una vulnerabilita\' nota (CVE/GHSA)',
    why: 'una componente vulnerabile importa il rischio della sua falla nel progetto (catena di fornitura software)',
    asvsTopic: 'Dependencies / Supply Chain',
  },
  config: {
    what: 'una configurazione espone una superficie o disabilita una protezione attesa',
    why: 'una misconfigurazione apre un percorso che gli altri controlli davano per chiuso',
    asvsTopic: 'Configuration',
  },
  'dead-code': {
    what: 'un export/file non e\' referenziato da alcun entry: e\' codice morto (igiene, nessun OWASP)',
    why: 'il codice morto non e\' una vulnerabilita\' ma e\' superficie inutile e fonte di confusione; lo standard qui e\' di IGIENE, non di sicurezza',
    asvsTopic: null,
  },
  misc: {
    what: 'un pattern segnalato dall\'oracolo che non rientra nelle categorie principali',
    why: 'va valutato rispetto allo standard nominato pertinente (07 §3)',
    asvsTopic: null,
  },
};

// CWE -> frase breve per arricchire "cos'e'" quando il finding porta un CWE.
const CWE_HINT = {
  'CWE-89': 'SQL injection',
  'CWE-78': 'OS command injection',
  'CWE-862': 'missing authorization',
  'CWE-285': 'improper authorization',
  'CWE-798': 'credenziali hardcoded',
  'CWE-338': 'PRNG non crittografico',
  'CWE-327': 'algoritmo crittografico debole',
  'CWE-208': 'confronto non timing-safe',
  'CWE-918': 'SSRF',
  'CWE-22': 'path traversal',
};

// Profondita' PROPORZIONATA (08 §4): un LOW non si spiega come un CRITICAL.
function depthFor(severity) {
  switch (String(severity || '').toUpperCase()) {
    case 'CRITICAL':
    case 'HIGH':
      return 'full';
    case 'MEDIUM':
      return 'brief';
    default:
      return 'minimal';
  }
}

/**
 * Costruisce la citazione "perche' conta" SENZA aggettivi: nomina lo standard
 * (OWASP 2025 dal campo owasp, CWE dal campo cwe, eventuale provvedimento RLS dal
 * rule_id, topic ASVS dalla mappa). Mai un parere.
 */
function whyItMatters(finding, std) {
  const cites = [];
  if (finding.owasp) cites.push(`OWASP ${finding.owasp}`);
  if (finding.cwe) {
    const hint = CWE_HINT[finding.cwe];
    cites.push(hint ? `${finding.cwe} (${hint})` : finding.cwe);
  }
  // Provvedimento RLS nominato (07 §5), quando l'oracolo e' rls-check.
  if (finding.category === 'rls' && finding.source_oracle && /RLS\d+/.test(finding.source_oracle.rule_id || '')) {
    cites.push(`standard RLS nominato (07 §5), controllo ${finding.source_oracle.rule_id}`);
  }
  if (std && std.asvsTopic) cites.push(`ASVS 5.0 topic "${std.asvsTopic}"`);
  const standardsLine = cites.length ? cites.join('; ') : 'standard nominato pertinente (07 §3)';
  return `${std ? std.why : 'va valutato rispetto allo standard nominato'}. Riferimento (non un parere): viola ${standardsLine}.`;
}

/** "Dove": file, riga, simbolo da location. Nessun valore di segreto. */
function whereLine(finding) {
  const loc = finding.location || {};
  const sym = loc.symbol ? ` — simbolo \`${loc.symbol}\`` : '';
  const lines =
    loc.start_line && loc.end_line && loc.start_line !== loc.end_line
      ? `righe ${loc.start_line}-${loc.end_line}`
      : `riga ${loc.start_line || 0}`;
  return `${loc.file || '(file ignoto)'} (${lines})${sym}`;
}

/**
 * GENERA la spiegazione strutturata di UN finding (08 §4). Pura, deterministica.
 * Restituisce { what, why, where, fixDirection, severity, depth, text }.
 *   - text e' la resa leggibile concatenata; gli altri campi sono i 4 elementi.
 *   - NON contiene MAI "e' sicuro"/"via libera"; lo stato resta quello del finding.
 *   - NON reidrata segreti: usa solo `evidence` gia' redatta.
 */
export function explainFinding(finding) {
  if (!finding || typeof finding !== 'object') {
    throw new Error('explainFinding: atteso un finding');
  }
  const std = CATEGORY_STANDARD[finding.category] || CATEGORY_STANDARD.misc;
  const depth = depthFor(finding.severity);

  // 1. Cos'e' — una frase, eventualmente arricchita dal CWE.
  const cweHint = finding.cwe && CWE_HINT[finding.cwe] ? ` (${CWE_HINT[finding.cwe]})` : '';
  const what = `${capitalize(std.what)}${cweHint}.`;

  // 2. Perche' conta — citando lo standard nominato, mai un parere.
  const why = whyItMatters(finding, std);

  // 3. Dove — da location.
  const where = whereLine(finding);

  // 4. Direzione della fix — SOLO da remediation_hint (oracolo/convenzione).
  //    Se manca, lo dichiariamo onestamente; NON inventiamo un verdetto.
  const fixDirection = finding.remediation_hint
    ? String(finding.remediation_hint).trim()
    : 'Nessun suggerimento di fix dall\'oracolo/convenzione per questo finding (04): la direzione va derivata dallo standard nominato citato; nessun verdetto automatico.';

  // Framing onesto (08 §4 / L-COL-006): chiudiamo dichiarando lo STATO del finding
  // (rilevato), MAI "sei al sicuro".
  const status = `Stato: ${finding.fix_state || 'detected'} (problema RILEVATO; nessuna assoluzione, L-COL-006).`;

  // Resa proporzionata: minimal/brief tagliano il "perche'" a una riga.
  const whyRendered =
    depth === 'minimal' ? `${std.why}.` : why;

  const text =
    `Cos'e': ${what}\n` +
    `Perche' conta: ${whyRendered}\n` +
    `Dove: ${where}\n` +
    `Direzione della fix: ${fixDirection}\n` +
    `${status}`;

  return { what, why, where, fixDirection, severity: finding.severity, depth, text };
}

function capitalize(s) {
  const str = String(s || '');
  return str.charAt(0).toUpperCase() + str.slice(1);
}

// =============================================================================
// CLI: node explain.mjs <finding.json|->  (oppure un array di finding)
//   Stampa la/le spiegazione/i. Deterministico, built-in.
// =============================================================================
function main(argv) {
  const src = argv[2];
  if (!src) {
    process.stderr.write('uso: node explain.mjs <finding.json|->\n');
    return 2;
  }
  let input;
  try {
    const raw = src === '-' ? readFileSync(0, 'utf8') : readFileSync(resolve(src), 'utf8');
    input = JSON.parse(raw);
  } catch (err) {
    process.stderr.write(`impossibile leggere/parsare ${src}: ${err.message}\n`);
    return 2;
  }
  const findings = Array.isArray(input) ? input : [input];
  const out = findings.map((f) => explainFinding(f));
  process.stdout.write(JSON.stringify(out, null, 2) + '\n');
  return 0;
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1] === __filename) {
  process.exit(main(process.argv));
}
