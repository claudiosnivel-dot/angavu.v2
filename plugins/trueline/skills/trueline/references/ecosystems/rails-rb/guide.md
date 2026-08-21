# ecosystems/rails-rb/guide.md — Trueline · ecosistema rails-rb (Ruby su Rails)

> Pack di rilevamento tier **detection** (eco-F4). Coverage dichiarata;
> verified_set vuoto (fase 1). Authz-surface = **route-authz**
> (controller con `skip_before_action` su callback di autenticazione).

---

## Profilo dell'ecosistema

- **Linguaggio**: Ruby — Rails, Sinatra, Rack; Bundler per la gestione delle dipendenze.
- **Backend**: rails-app — Action Controller, Active Record, middleware Rack.
- **Client DB tipici**: Active Record (`ActiveRecord::Base.connection`), Sequel, pg gem diretta.
- **Framework authz tipici**: Devise (`authenticate_user!`), CanCanCan (`authorize!`), Pundit (`authorize`).
- **Gestione dipendenze**: Bundler (`Gemfile` + `Gemfile.lock`).
- **Segnale di classificazione**: presenza di `Gemfile` nella directory del progetto (`detect.lang_any`).

---

## Oracle set — batteria detection (eco-F4)

| Controllo chkp | Categoria finding | Oracolo | Wrapper | Note |
|---|---|---|---|---|
| 2 — sicurezza | `authz` (`authz-surface`) | Semgrep + ruleset route-authz del pack (`ruleset/`) | `scripts/oracles/run_semgrep.mjs` | Rileva `skip_before_action` su callback di autenticazione senza sostituto |
| 2 — sicurezza | `injection` | Semgrep + ruleset del pack (`ruleset/`) | `scripts/oracles/run_semgrep.mjs` | SQL/shell string-concat da input utente |
| 2 — sicurezza | `secret` | gitleaks — working tree | `scripts/oracles/run_gitleaks.mjs` | `--redact` obbligatorio; shared con gli altri pack |
| 2 — sicurezza | `dependency-vuln` | osv-scanner su lockfile | `scripts/oracles/run_osv.mjs` | Lockfile: `Gemfile.lock` |
| 1 — dead-code | `dead-code` | debride | (non eseguito in eco-F4) | unsound → detection-only (F5) |

**Floor (categorie minime obbligatorie):** `secret`, `dependency-vuln`, `authz`.

**Copertura dichiarata:** il pack è in tier **detection** — rileva la presenza di difetti, non ne certifica l'assenza. Nessun finding nei finding di detection non equivale a "sicuro" (`L-COL-006`). authz/injection via semgrep = **best-effort** (semgrep assente nel sandbox → degrada onesto; mai falso verde).

---

## authz-surface: route-authz (skip_before_action)

In Rails, l'autenticazione si applica tipicamente tramite `before_action :authenticate_user!` (o equivalenti: `require_login`, `authenticate!`). Quando un controller chiama `skip_before_action :authenticate_user!` su azioni mutanti (`create`, `update`, `destroy`) **senza aggiungere un controllo alternativo**, quelle azioni diventano accessibili senza verifica d'identità (CWE-862, Broken Access Control).

### Pattern difettoso rilevato (SEED:RB-S3)

```ruby
class ArticlesController < ApplicationController
  # DIFETTO — skip del callback di autenticazione sulle azioni mutanti (CWE-862)
  skip_before_action :authenticate_user!, only: [:create, :update, :destroy]

  def create
    # Chiunque può creare articoli: nessun check identità
    @article = Article.new(article_params)
    @article.save
    render json: @article
  end
end
```

### Pattern sicuro (contrasto — NON flaggato)

```ruby
class AdminController < ApplicationController
  # SICURO — before_action di autenticazione applicato (non skippato)
  before_action :authenticate_user!

  def create_resource
    # Solo utenti autenticati possono accedere
    render json: { resource_created: true }
  end
end
```

### Callback di autenticazione riconosciuti dal ruleset

- `authenticate_user!` (Devise)
- `authenticate!`
- `require_login` (Sorcery/altri)
- `logged_in?` / `current_user` (pattern custom)
- `verify_user`
- `login_required`

---

## Sink DB e pattern route-authz rilevati

| Tipo | Pattern difettoso rilevato |
|---|---|
| Rails Controller | `skip_before_action :<auth_callback>, ...` senza guard alternativo |
| Devise | `skip_before_action :authenticate_user!` su azioni CREATE/UPDATE/DESTROY |
| Sinatra/Sorcery | `skip_before_action :require_login` |

Azioni `GET` (sola lettura) e controller con `before_action` applicato: **nessun finding** (0 FP per design).

---

## Dipendenze vulnerabili — lockfile

Il lockfile `Gemfile.lock` è il riferimento primario per osv-scanner. Il pin vulnerabile del SEED (RB-S2) è `nokogiri (1.10.0)`, una versione nota per avere advisory nel database OSV/GitHub Security Advisory (libxml2 vulnerabilities). La versione pulita di contrasto nelle gem standard (`rack`) resta aggiornata.

---

## Segreti — gitleaks (language-agnostic)

gitleaks rileva segreti hardcoded in qualsiasi file sorgente Ruby (`.rb`), YAML, `.env`, ecc. Il SEED RB-S1 usa una chiave in stile Stripe (`sk_live_...`) hardcodata in un initializer Rails (`config/initializers/`). Il contrasto pulito legge le credenziali da `ENV['...']` senza mai committare il valore.

---

## Preflight specifico

- `Gemfile.lock` presente — assente → osv-scanner non può girare, degradato e dichiarato.
- Semgrep disponibile (docker) — assente → authz/injection degradano onesto (best-effort, L-COL-006).
- debride installato — assente → dead-code degradato dichiarato (non-floor, F5).
- Nessun DB live richiesto (rails-rb non ha controlli RLS a runtime).

---

## Differenza rispetto a postgres-jsts

| Aspetto | postgres-jsts | rails-rb |
|---|---|---|
| Linguaggio | JavaScript / TypeScript | Ruby |
| Segnale classify | `package.json` (lang_any) | `Gemfile` (lang_any) |
| authz-surface | route-authz (Express/Next: `router.post/put/...`) | route-authz (Rails: `skip_before_action`) |
| dead-code | knip | debride (detection-only, unsound) |
| lockfile | `package-lock.json` / `yarn.lock` / `pnpm-lock.yaml` | `Gemfile.lock` |
| verified_set | `[]` (eco-F4 = detection) | `[]` (eco-F4 = detection) |
