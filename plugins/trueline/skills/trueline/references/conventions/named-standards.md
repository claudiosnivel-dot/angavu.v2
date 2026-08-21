# Named Standards — Trueline conventions reference

**Modulo sorgente:** `07-CONVENTIONS-THREATMODEL` §3, §5  
**Caricamento:** per modalità attiva (`02` §6) — pieno in BUILD e REMEDIATE; parziale in BOOTSTRAP per le `security_notes`.  
**Scopo:** fornire il vocabolario verificabile che gli oracoli mappano e che l'LLM cita. Niente aggettivi, solo riferimenti.

---

## §3 Standard nominati

### §3.1 OWASP Top 10:2025 — tassonomia di rischio

L'edizione **canonica e unica** adottata da Trueline è **OWASP Top 10:2025** (finale da gennaio 2026), che rimpiazza la 2021. Ogni finding e ogni spiegazione si esprime in codici 2025; non esiste doppia titolazione.

Cambi rilevanti per Trueline rispetto alla 2021:
- **SSRF assorbita in A01** Broken Access Control (non più A10 autonoma).
- **Injection scesa ad A05** (era A03 nel 2021).
- **Software Supply Chain Failures** (A03:2025) nuova categoria che espande le vecchie "componenti vulnerabili" (A06:2021).

**Vincolo di realtà e normalizzazione (`L-COL-026`).** Le regole curate del ruleset Semgrep (`semgrep-ai-ruleset`, §4 di `07`) le scriviamo noi e portano già metadati 2025. Le fonti **esterne** che non controlliamo — regole del registry Semgrep, advisory OSV — taggano ancora su 2021 o su CWE e non passeranno a 2025 a breve. Trueline le **normalizza al confine dell'adapter**: il codice grezzo si traduce in 2025 prima di popolare il campo `owasp` del finding (`04`); l'originale grezzo è preservato nel campo `owasp_source` per tracciabilità.

**Mappa di normalizzazione — emesso → canonico 2025.**  
La tabella è la mappa di normalizzazione per le categorie a cui gli oracoli di Trueline arrivano; non riproduce l'intera lista 2025.

| `category` Trueline | Emesso da fonti esterne (2021 / CWE) | Canonico 2025 |
|---|---|---|
| `rls` / `authz` | A01:2021 Broken Access Control | **A01:2025** Broken Access Control |
| `injection` | A03:2021 Injection | **A05:2025** Injection |
| `crypto` | A02:2021 Cryptographic Failures | **A04:2025** Cryptographic Failures |
| `secret` | A07:2021 / A02:2021 | **A07:2025** Authentication Failures / **A02:2025** Security Misconfiguration |
| `dependency-vuln` | A06:2021 Vulnerable & Outdated Components | **A03:2025** Software Supply Chain Failures |
| `config` / `misc` | A05:2021 Security Misconfiguration | **A02:2025** Security Misconfiguration |
| sink SSRF (in `injection` / `misc`) | A10:2021 SSRF | **A01:2025** (assorbita in Broken Access Control) |
| `dead-code` | — (igiene) | — (igiene, nessun codice OWASP) |

### §3.2 OWASP ASVS 5.0.0 — requisiti verificabili

ASVS è lo standard naturale per uno strumento di **verifica**: dà requisiti testabili, non aggettivi. Versione corrente **5.0.0** (maggio 2025).

**Formato di citazione:** `v5.0.0-<capitolo>.<sezione>.<requisito>` — es. `v5.0.0-1.2.5` = prevenzione OS command injection via query parametrizzate.

Nota: ASVS 5.0 ha rimosso le mappe dirette a CWE dalla lista principale; per la precisione sul "tipo di debolezza" si usa CWE separatamente (§3.3).

**Mappa per topic** (i numeri di capitolo 5.0 si citano al momento della scrittura della regola; qui si nomina il topic):

| Concern Trueline v1 | Topic ASVS 5.0 |
|---|---|
| `injection` (SQL / command / PostgREST) | Encoding & Sanitization → **Injection Prevention** |
| `authz` / `rls` | **Access Control / Authorization** |
| `crypto` (random, hashing, confronti) | **Cryptography** |
| `secret` (gestione segreti / config) | **Configuration & Secret Management** |
| validazione input lato server | **Validation & Business Logic** |
| autenticazione / token | **Authentication / Self-contained Tokens** |

**Uso:** una `security_notes` di task (`11`) e una spiegazione di finding (`08`) possono citare il requisito ASVS pertinente come **criterio**, non come opinione.

### §3.3 CWE — tassonomia di debolezza

Il campo `cwe` del finding (`04`) porta l'identificatore preciso della debolezza (es. `CWE-89` SQL injection). Rende un finding non ambiguo a chi lo legge e lega un pattern vietato (`forbidden-patterns.md`) alla sua famiglia di debolezza.

### §3.4 Standard RLS nominato

È specifico Supabase/Postgres, ancorato alla guida ufficiale Supabase, e costituisce lo standard contro cui misura il checker RLS (`03` §5.4). Enumerato per intero in §5 di `07-CONVENTIONS-THREATMODEL`; riprodotto qui come riferimento operativo.

**Lo standard.** *Ogni tabella `public`/user-facing ha RLS abilitato e almeno una policy che vincola l'accesso per identità/tenant (`auth.uid()` / `tenant_id`); l'isolamento finto e l'uso client-side della service_role sono vietati.*

Ogni provvedimento è etichettato per come si verifica: `[statico]` dal checker RLS (`03` §5.4), `[DB-test]` richiede il DB di test di `06` §6.1, `[advisory]` igiene/performance non bloccante.

| # | Provvedimento | Verifica |
|---|---|---|
| R1 | RLS **abilitato** su ogni tabella `public`/user-facing (senza, è pubblica via Data API/PostgREST). | `[statico]` |
| R2 | RLS abilitato ⇒ **≥1 policy** (niente deny-all silenzioso che "rompe" l'app senza errori visibili). | `[statico]` |
| R3 | **Niente `USING (true)` / `WITH CHECK (true)`** su tabelle user-facing; **niente** `auth.uid() IS NOT NULL` come sola condizione (= tutti gli autenticati). | `[statico]` |
| R4 | Le policy **vincolano per identità/tenant** (`auth.uid() = user_id` / derivazione `tenant_id`) — la correttezza della logica multi-tenant. | `[DB-test]` |
| R5 | Clausola **`TO authenticated`** (o ruolo appropriato) specificata, non implicita/pubblica. | `[statico]` |
| R6 | Una **UPDATE policy** è accompagnata da una **SELECT policy** (Postgres deve leggere la riga per valutare `USING`). | `[statico]` |
| R7 | **service_role** confinata server-side, con **authz applicativa esplicita** (bypassa RLS) — overlap con il pattern vietato §4.3 di `forbidden-patterns.md`. | `[statico]` + `[DB-test]` |
| R8 | Funzioni **`SECURITY DEFINER`** fanno authz propria (altrimenti chiunque le chiama bypassa RLS). | `[statico]` |
| R9 | Performance: `(select auth.uid())` per cache initPlan; colonne di policy **indicizzate**. | `[advisory]` |

**Confine di copertura dichiarato** (`L-COL-006`, da `03` §5.4): lo static-first non vede lo schema modificato solo dal dashboard Supabase e non riversato in migration. Il checker lo dichiara ("verificato contro le migration dichiarate; tabelle assenti dalle migration non coperte") — non riempie il vuoto con una stima.

**Trappola del test** (lega `06` §6.1): l'SQL Editor di Supabase gira come superuser e bypassa RLS — testare RLS lì dà un falso verde. La verifica comportamentale di R4/R7 va fatta **attraverso il client con auth reale** su un DB di test, non nell'editor.

### §3.5 Come gli standard vengono usati

- **Gli oracoli mappano** i loro finding su questi standard: le regole curate (`semgrep-ai-ruleset`) via `metadata.owasp` / `cwe` già in 2025; il RLS checker contro il §3.4 (standard R1..R9); OSV via CVE/GHSA. I codici OWASP legacy provenienti da fonti esterne sono normalizzati a 2025 (§3.1, `L-COL-026`) prima di popolare il campo `owasp`.
- **L'LLM cita** (non inventa): in `08` per il "perché conta", in `11` per le `security_notes`. Lo standard è il prior vincolato che `L-COL-012` impone al posto degli aggettivi.
