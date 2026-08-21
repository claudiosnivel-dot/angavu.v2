// partition.mjs — partiziona le assertion di characterization in GUARD vs IMPACTED
// rispetto a un finding la cui fix sta per cambiare il codice (06 §7).
//
// Idea (05 §5): prima di applicare una fix, distinguiamo:
//   - IMPACTED  le assertion il cui target e' la STESSA regione/tabella che la
//               fix tocchera': potrebbero LEGITTIMAMENTE cambiare (la fix cambia
//               il comportamento per disegno). Vanno ri-baselined dopo la fix.
//   - GUARD     tutte le altre: devono restare INVARIATE. Se una guard cambia,
//               la fix ha rotto qualcosa di non correlato -> regressione.
//
// GENERICO: l'appartenenza si decide per finding.category + finding.location,
// MAI per nomi hardcoded della reference app. Una assertion e' IMPACTED se:
//   (a) categoria RLS  -> match per TABELLA (assertion.target == tabella toccata),
//   (b) altre categorie-> match per REGIONE FILE (stesso file/percorso del finding),
//   (c) categoria 'build-integrity' -> sempre potenzialmente impacted da ogni fix
//       di codice (la build copre l'intero progetto) -> trattata come IMPACTED.
//
// Node ESM, solo built-in.

// Normalizza un path a slash-forward e ne estrae il basename per confronti robusti.
function norm(p) { return String(p || '').replace(/\\/g, '/'); }
function baseName(p) { return norm(p).split('/').pop(); }

// Estrae la "regione file" che la fix del finding tocchera'.
function findingFile(finding) {
  const loc = finding && finding.location ? finding.location : {};
  return norm(loc.file || loc.path || '');
}

// Estrae la tabella DICHIARATA di un finding RLS (quando il finding la porta
// esplicitamente). A seconda dello stadio/regola la tabella vive in posti diversi:
//   - raw rls_check (RLS001):    finding.table = 'public.audit_logs'
//   - NORMALIZZATO RLS001:       finding.location.symbol = 'public.audit_logs'
//   - eventuale variante:        finding.location.table
// ATTENZIONE: per le regole su POLICY (RLS003/RLS004) il symbol normalizzato e' il
// NOME DELLA POLICY (es. 'documents_read_all'), NON la tabella. Per questi casi il
// match per tabella esplicita fallisce ed e' isImpacted() a ricadere sul match
// TESTUALE col target dell'assertion (vedi sotto). Qui ritorniamo solo cio' che e'
// chiaramente una tabella schema-qualificata.
function findingTable(finding) {
  const loc = finding && finding.location ? finding.location : {};
  const raw = (loc.table || (finding && finding.table) || '').toString().toLowerCase();
  if (raw) return raw;
  // location.symbol e' una tabella SOLO se schema-qualificato (contiene un punto);
  // altrimenti e' il nome di una policy/constraint -> non e' la tabella.
  const sym = (loc.symbol || '').toString().toLowerCase();
  if (sym.includes('.')) return sym;
  return '';
}

// Raccoglie il TESTO del finding (evidence/message/snippet/symbol) per un match
// per-tabella robusto quando la tabella non e' portata esplicitamente (regole su
// policy). Il nome-tabella dell'assertion, se compare in questo testo, prova che
// il finding tocca quella tabella.
function findingText(finding) {
  if (!finding) return '';
  const loc = finding.location || {};
  return [
    finding.evidence, finding.message, finding.snippet, loc.symbol, loc.statement,
  ].filter(Boolean).join(' ').toLowerCase();
}

// Estrae il nome di tabella "nudo" (senza schema) da un target di assertion:
//   'public.invoices' -> 'invoices'; 'invoices' -> 'invoices'.
function bareTable(target) {
  return String(target || '').toLowerCase().split('.').pop();
}

// Una assertion e' IMPACTED dal finding?
function isImpacted(finding, assertion) {
  const cat = finding && finding.category;

  // build-integrity copre l'intero progetto: ogni fix di codice puo' cambiarla.
  if (assertion.kind === 'build-integrity') return true;

  // RLS -> match per tabella. Due vie:
  //   (a) tabella DICHIARATA dal finding (schema-qualificata): match diretto col
  //       target dell'assertion;
  //   (b) FALLBACK testuale (regole su policy, dove il symbol e' il nome-policy):
  //       il nome-tabella nudo dell'assertion compare nel testo del finding
  //       (evidence/message/snippet)? Allora il finding tocca quella tabella.
  if (cat === 'rls') {
    if (assertion.kind !== 'rls') return false;
    const aTarget = String(assertion.target || '').toLowerCase();
    const aBare = bareTable(assertion.target);

    const fTable = findingTable(finding);
    if (fTable && (aTarget.includes(fTable) || fTable.includes(aTarget))) return true;

    // Fallback testuale: cerca il nome-tabella nudo come PAROLA nel testo del
    // finding (word-boundary per evitare match su sottostringhe spurie).
    if (aBare) {
      const re = new RegExp(`\\b${aBare.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`);
      if (re.test(findingText(finding))) return true;
    }
    return false;
  }

  // Altre categorie -> match per regione file (stesso file).
  const fFile = findingFile(finding);
  if (!fFile) return false;
  const aTarget = norm(assertion.target || '');
  // match se condividono lo stesso file (per percorso completo o basename).
  if (!aTarget) return false;
  return aTarget === fFile
    || baseName(aTarget) === baseName(fFile)
    || aTarget.endsWith(fFile)
    || fFile.endsWith(aTarget);
}

// partition(finding, assertions) -> { guard, impacted, rationale }
//
//   guard      [id...]  assertion che DEVONO restare invarianti dopo la fix.
//   impacted   [id...]  assertion che la fix puo' legittimamente cambiare.
//   rationale  string   spiegazione del criterio applicato (per il log/report).
export function partition(finding, assertions = []) {
  const guard = [];
  const impacted = [];

  for (const a of assertions) {
    if (isImpacted(finding, a)) impacted.push(a.id);
    else guard.push(a.id);
  }

  const cat = (finding && finding.category) || 'unknown';
  const loc = cat === 'rls' ? (findingTable(finding) || '(tabella ignota)') : (findingFile(finding) || '(file ignoto)');
  const rationale =
    `finding categoria='${cat}' loc='${loc}': IMPACTED le assertion sulla stessa `
    + `${cat === 'rls' ? 'tabella' : 'regione file'} (+ build-integrity), GUARD le altre `
    + `(devono restare invarianti, 05 §5). impacted=${impacted.length} guard=${guard.length}`;

  return { guard, impacted, rationale };
}

export default partition;
