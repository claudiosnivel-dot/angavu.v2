// detect_deploy_coupling.mjs — rilevatore di accoppiamento main<->deploy (05 §8.3).
//
// Operazionalizza il "mix fail-safe" congelato (01 §5.3 / 05 §8.3, L-COL-025):
//   1) AUTO-DETECT dei segnali di deploy-on-push-to-main.
//   2) Esito scritto come main_deploy_coupled: true | false | unknown e
//      confermato UNA volta con l'utente (qui lo restituiamo; la persistenza in
//      SESSION-STATE e la conferma sono del runtime della skill).
//   3) FAIL-SAFE: se l'esito e' unknown/ambiguo e NON confermato dall'utente,
//      la skill tratta main come COUPLED -> il merge autonomo e' SOSPESO
//      (human-gated). L'autonomia non assume MAI in silenzio "non-coupled".
//
// L'asimmetria di rischio (05 §8.3): una coupling MANCATA = deploy autonomo in
// produzione (catastrofico); una coupling SPURIA = solo un gate umano in piu'.
// In dubbio, si gata.
//
// SEGNALI cercati (01 §5.3):
//   - workflow GitHub Actions che deploya su push a main (.github/workflows/*)
//   - auto-deploy Cloudflare Pages/Workers (wrangler.toml, integrazione Git)
//   - vercel.json / netlify.toml con deploy automatico
//   - hook/branch di deploy Supabase (supabase/config.toml, branch deploy)
//
// API PROGRAMMATICA:
//   detectDeployCoupling(repoDir) -> { coupled: true|false|'unknown', signals[] }
//       contratto compatto M1.5: l'esito grezzo a TRE stati del detect statico.
//       coupled=true  -> segnale chiaro; false -> repo pulito; 'unknown' -> ambiguo.
//   evaluateDeployCoupling(repoDir, confirmedCoupled) -> decisione + fail-safe.
//
// CONTRATTO CLI:
//   node detect_deploy_coupling.mjs <project-dir> [--confirmed-coupled=true|false]
//   node detect_deploy_coupling.mjs <project-dir> --detect-only
// Stampa su stdout un JSON. Senza --detect-only (default, orchestratore):
//   { main_deploy_coupled, effective_gate, signals[], ambiguous[], reason, detect_value }
//   - main_deploy_coupled: "true" | "false" | "unknown" (esito grezzo del detect)
//   - effective_gate: "suspended" | "autonomous" (dopo il fail-safe)
//       suspended  = merge autonomo SOSPESO (human-gated)
//       autonomous = merge autonomo consentito (solo se NON coupled e confermato dall'utente)
// Con --detect-only (contratto compatto M1.5):
//   { coupled: true|false|"unknown", signals[] }
// Exit 0 sempre che il detect giri (l'esito e' nel JSON, non nell'exit code).
//
// Node ESM, solo built-in (fs, path, url). Niente rete.

import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

// --- API programmatica (usata dal modello git e dai test) --------------------

// Esito a TRE stati del detect statico (05 §8.3):
//   - 'true'    : almeno un segnale CHIARO di deploy-on-push-to-main.
//   - 'false'   : nessun segnale E nessuna ambiguita' (repo pulito).
//   - 'unknown' : indicatori AMBIGUI (es. workflow con push->main ma senza uno
//                 step di deploy riconoscibile, o un indizio parziale) che il
//                 detect non sa classificare con sicurezza. Il chiamante lo
//                 tratta come COUPLED (fail-safe).
//
// L'asimmetria: 'unknown' NON e' 'false'. Il detect non puo' escludere coupling
// configurate FUORI dal repo (CI in repo separato, integrazione Git lato
// provider); ma in un repo senza alcun indizio l'esito grezzo del detect e'
// 'false' (repo pulito), e la conservativita' su autonomia/conferma utente e'
// responsabilita' del fail-safe a valle (applyFailSafe), non del detect.
//
// Rileva i segnali in projectDir. Ritorna l'esito grezzo:
//   { value: "true"|"false"|"unknown", signals: string[], ambiguous: string[],
//     reason: string }
export function detectSignals(projectDir) {
  const root = resolve(projectDir);
  const signals = [];
  const ambiguous = [];

  // 1) GitHub Actions: workflow con trigger push su main/master e uno step di deploy.
  const wfDir = join(root, '.github', 'workflows');
  if (existsSync(wfDir)) {
    for (const f of safeReaddir(wfDir)) {
      if (!/\.ya?ml$/i.test(f)) continue;
      const txt = safeRead(join(wfDir, f));
      if (!txt) continue;
      const pushesMain = /on:[\s\S]*push[\s\S]*branches[\s\S]*\b(main|master)\b/i.test(txt)
        || /\bpush:[\s\S]*\b(main|master)\b/i.test(txt);
      const deploys = /\b(deploy|wrangler|vercel|netlify|supabase\s+db\s+push|gh-pages|cloudflare)\b/i.test(txt);
      if (pushesMain && deploys) {
        signals.push(`github-actions:${f} (push->main + step di deploy)`);
      } else if (pushesMain) {
        // Trigger su push->main ma nessuno step di deploy riconoscibile: e' un
        // workflow CI generico (test/lint)? o un deploy mascherato? AMBIGUO.
        ambiguous.push(`github-actions:${f} (push->main ma nessuno step di deploy riconoscibile)`);
      }
    }
  }

  // 2) Cloudflare Wrangler (Pages/Workers).
  for (const wf of ['wrangler.toml', 'wrangler.json', 'wrangler.jsonc']) {
    if (existsSync(join(root, wf))) signals.push(`cloudflare-wrangler:${wf}`);
  }

  // 3) Vercel / Netlify.
  if (existsSync(join(root, 'vercel.json'))) signals.push('vercel:vercel.json');
  if (existsSync(join(root, 'netlify.toml'))) signals.push('netlify:netlify.toml');

  // 4) Supabase: presenza di config + indizio di deploy (branch deploy / db push).
  const supaCfg = join(root, 'supabase', 'config.toml');
  if (existsSync(supaCfg)) {
    const txt = safeRead(supaCfg) || '';
    // La sola presenza di supabase/ NON e' un segnale forte di deploy-on-push;
    // lo e' un indizio esplicito di branch/db deploy automatico.
    if (/\b(branch|deploy|db\s*push)\b/i.test(txt)) {
      signals.push('supabase:config.toml (indizio di branch/db deploy)');
    } else {
      // config.toml presente ma senza indizio di deploy: ambiguo (potrebbe
      // esserci un branch-deploy configurato lato dashboard Supabase).
      ambiguous.push('supabase:config.toml (presente, deploy non determinabile dal file)');
    }
  }

  // Precedenza dell'esito (fail-safe): segnale CHIARO -> true; altrimenti se
  // c'e' ambiguita' -> unknown; altrimenti repo pulito -> false.
  if (signals.length > 0) {
    return {
      value: 'true',
      signals,
      ambiguous,
      reason: `rilevati ${signals.length} segnale/i di deploy-on-push-to-main`,
    };
  }
  if (ambiguous.length > 0) {
    return {
      value: 'unknown',
      signals: [],
      ambiguous,
      reason:
        `rilevati ${ambiguous.length} indicatore/i AMBIGUO/I non classificabili `
        + 'con sicurezza; il chiamante li tratta come coupled (fail-safe).',
    };
  }
  return {
    value: 'false',
    signals: [],
    ambiguous: [],
    reason: 'nessun segnale ne indizio ambiguo nel repo: repo pulito (not-coupled).',
  };
}

// API del contratto M1.5 (05 §8.3): esito del detect statico in forma compatta.
// Ritorna ESATTAMENTE { coupled, signals }:
//   - coupled: true    -> almeno un segnale chiaro di deploy-on-push-to-main
//   - coupled: false   -> nessun segnale e nessuna ambiguita' (repo pulito)
//   - coupled: 'unknown' -> indicatori ambigui (il chiamante li tratta come coupled)
//   - signals: elenco dei segnali (e, in coda, degli indizi ambigui) rilevati
//
// NOTA (05 §8.3, punto 2-3): l'esito va scritto in SESSION-STATE come
// main_deploy_coupled e CONFERMATO UNA VOLTA con l'utente; in caso di 'unknown'
// (o di mancata conferma) il fail-safe a valle assume COUPLED -> merge
// autonomo SOSPESO. Vedi applyFailSafe/evaluateDeployCoupling.
export function detectDeployCoupling(repoDir) {
  const d = detectSignals(repoDir);
  const coupled = d.value === 'true' ? true : d.value === 'false' ? false : 'unknown';
  return {
    coupled,
    // I segnali chiari per primi; gli indizi ambigui (se presenti) in coda,
    // cosi' l'elenco e' sempre esplicativo dell'esito anche quando e' 'unknown'.
    signals: [...d.signals, ...d.ambiguous],
  };
}

// Applica il fail-safe (05 §8.3) all'esito del detect + alla (eventuale)
// conferma utente. Ritorna { main_deploy_coupled, effective_gate, reason }.
//
//   confirmedCoupled: true | false | null
//     - true  => l'utente conferma coupled  -> coupled, gate suspended
//     - false => l'utente conferma NON coupled (override del detect) -> non coupled
//     - null  => nessuna conferma -> vale il fail-safe sull'esito del detect
export function applyFailSafe(detected, confirmedCoupled = null) {
  // Conferma esplicita dell'utente: ha la precedenza (puo' correggere il detect).
  if (confirmedCoupled === true) {
    return {
      main_deploy_coupled: 'true',
      effective_gate: 'suspended',
      reason: 'utente ha confermato coupled: merge autonomo SOSPESO (human-gated)',
    };
  }
  if (confirmedCoupled === false) {
    return {
      main_deploy_coupled: 'false',
      effective_gate: 'autonomous',
      reason: 'utente ha confermato NON coupled: merge autonomo consentito',
    };
  }

  // Nessuna conferma: fail-safe sull'esito del detect.
  if (detected.value === 'true') {
    return {
      main_deploy_coupled: 'true',
      effective_gate: 'suspended',
      reason: `coupled da auto-detect (${detected.reason}); merge autonomo SOSPESO`,
    };
  }
  // value === 'false' (repo pulito) o 'unknown' (ambiguo), MA non confermato
  // dall'utente => si ASSUME coupled (05 §8.3, punto 2-3). L'esito grezzo del
  // detect entra in SESSION-STATE, ma l'autonomia non assume MAI in silenzio
  // "non-coupled": serve la conferma esplicita una volta (confirmedCoupled=false).
  return {
    main_deploy_coupled: detected.value,
    effective_gate: 'suspended',
    reason:
      `esito '${detected.value}' del detect NON confermato dall'utente: FAIL-SAFE -> `
      + 'trattato come coupled, merge autonomo SOSPESO '
      + '(l\'autonomia non assume mai non-coupled in silenzio; serve conferma 05 §8.3).',
  };
}

// Orchestratore: detect + fail-safe in un colpo. Restituisce sia la DECISIONE
// (main_deploy_coupled/effective_gate/reason) sia l'esito grezzo del detect
// (detect_value/signals/ambiguous), cosi' il chiamante (layered_git) puo' gatare
// e SESSION-STATE puo' registrare l'esito da confermare con l'utente.
export function evaluateDeployCoupling(projectDir, confirmedCoupled = null) {
  const detected = detectSignals(projectDir);
  const decision = applyFailSafe(detected, confirmedCoupled);
  return {
    ...decision,
    signals: detected.signals,
    ambiguous: detected.ambiguous,
    detect_value: detected.value,
  };
}

// --- Helper di IO sicuri ------------------------------------------------------

function safeRead(p) {
  try { return readFileSync(p, 'utf8'); } catch { return null; }
}
function safeReaddir(d) {
  try {
    return readdirSync(d).filter((f) => {
      try { return statSync(join(d, f)).isFile(); } catch { return false; }
    });
  } catch { return []; }
}

// --- CLI ----------------------------------------------------------------------

function main() {
  const args = process.argv.slice(2);
  const dir = args.find((a) => !a.startsWith('--'));
  if (!dir) {
    process.stderr.write(
      'uso: node detect_deploy_coupling.mjs <project-dir> '
      + '[--confirmed-coupled=true|false] [--detect-only]\n',
    );
    process.exit(2);
  }
  // --detect-only: contratto compatto M1.5 { coupled, signals }.
  if (args.includes('--detect-only')) {
    const out = detectDeployCoupling(dir);
    process.stdout.write(JSON.stringify(out, null, 2) + '\n');
    process.exit(0);
  }
  let confirmed = null;
  const cf = args.find((a) => a.startsWith('--confirmed-coupled='));
  if (cf) {
    const v = cf.split('=')[1];
    if (v === 'true') confirmed = true;
    else if (v === 'false') confirmed = false;
  }
  const out = evaluateDeployCoupling(dir, confirmed);
  process.stdout.write(JSON.stringify(out, null, 2) + '\n');
  process.exit(0);
}

// Esegui solo se invocato direttamente (non in import).
const __isMain = process.argv[1]
  && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (__isMain) main();
