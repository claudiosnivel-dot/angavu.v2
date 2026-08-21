# ecosystems/phoenix-ex/guide.md — Trueline · ecosistema phoenix-ex (Elixir/Phoenix)

> Pack di rilevamento eco-F4 — tier **detection** (fase 1). Coverage dichiarata;
> nessun loop verificato (`verified_set` vuoto). Authz-surface = **route-authz**
> (action mutanti nei controller Phoenix senza plug di autenticazione),
> via Semgrep Elixir — ma **fuori dal floor** (gap dichiarato `L-COL-006`):
> l'engine OSS di Semgrep non parsa Elixir (richiede l'engine proprietario Pro,
> `--pro-languages`, non disponibile nel sandbox). Binding conservato come
> **bonus non-floor**; oracolo route-authz Elixir **deferred F6**.

---

## Profilo dell'ecosistema

- **Linguaggio**: Elixir — Phoenix Framework (web), Ecto (ORM), Plug (middleware), Plug.Router.
- **Backend**: phoenix-app — server HTTP gestito da Phoenix o da Plug + Cowboy direttamente.
- **Pattern tipici**: controller Phoenix (`use MyAppWeb, :controller`), router (`use MyAppWeb, :router`), pipeline (`plug :accepts`), azioni mutanti (`create/2`, `update/2`, `delete/2`).
- **Marker di rilevamento** (`detect.lang_any`): `mix.exs` — file di progetto Elixir, SEMPRE presente in qualsiasi progetto Mix/Phoenix.
- **Lockfile dipendenze**: `mix.lock` — blocca le versioni esatte dei pacchetti Hex.
- **Test runner tipici**: ExUnit (nativo Elixir), non configurato esplicitamente nel manifest (non rilevante per il tier detection).

---

## Oracle set — batteria detection (eco-F4, fase 1)

| Controllo | Categoria finding | Oracolo | Note |
|---|---|---|---|
| Sicurezza | `secret` | gitleaks — working tree | Shared con tutti i pack; rileva credenziali hardcoded in qualsiasi file Elixir/config |
| Sicurezza | `dependency-vuln` | osv-scanner su `mix.lock` | Lockfile Hex; `--lockfile mix.lock` |
| Sicurezza | `authz` (`authz-surface`) | Semgrep + `ruleset/` (Elixir) — **bonus, NON nel floor** | Engine OSS non parsa Elixir (richiede Pro `--pro-languages`): inaffidabile → gap dichiarato `L-COL-006`, deferred F6 |
| Sicurezza | `injection` | Semgrep + `ruleset/` | Stesso vincolo (engine OSS Elixir); non nel floor |
| Igiene | `dead-code` | compiler (dichiarato) | Il compilatore Elixir avverte su variabili/funzioni non usate; NON nel floor |

**Floor (categorie minime obbligatorie):** `secret`, `dependency-vuln`.

**`authz` fuori dal floor — gap dichiarato (`L-COL-006`).** Il difetto route-authz EX-S3 resta seminato e documentato e il binding `authz=semgrep` (role `authz-surface`) resta come **bonus non-floor**, ma l'engine OSS di Semgrep (immagine pinnata `semgrep/semgrep:latest`) **non può parsare Elixir** — emette `Missing plugin … needed for parsing Elixir target. Try adding --pro-languages` e 0 finding. Il parsing Elixir richiede l'engine proprietario **Pro** (`--pro-languages`), non disponibile nel sandbox. La route-authz Elixir via Semgrep è quindi **sperimentale/inaffidabile** e degrada onestamente: oracolo **deferred F6**.

**Copertura dichiarata:** tier detection — rileva la presenza di difetti, non ne certifica l'assenza. Nessun finding non equivale a "sicuro" (`L-COL-006`).

---

## authz-surface: route-authz (plug di autenticazione assente)

In Phoenix, l'autenticazione viene applicata **prima** che una action esegua scritture.
I meccanismi principali sono:

- `plug :require_authenticated_user` nel modulo controller o nella pipeline del router.
- Lettura di `conn.assigns[:current_user]` con guard esplicito e `halt/1` se nil.
- `Plug.Conn.halt/1` dopo una risposta 401/403 per interrompere il pipeline.

### Pattern difettoso rilevato (SEED:EX-S3)

```elixir
defmodule MyAppWeb.PostsController do
  use MyAppWeb, :controller

  # DIFETTO — action mutante senza plug auth (CWE-862, A01:2025)
  def create(conn, params) do
    {:ok, post} = MyApp.Posts.create_post(params)
    json(conn, %{ok: true, data: post})
  end
end
```

### Pattern sicuro (contrasto — NON flaggato)

```elixir
defmodule MyAppWeb.SecurePostsController do
  use MyAppWeb, :controller
  plug :require_authenticated_user  # check applicato a tutte le action

  def create(conn, params) do
    current_user = conn.assigns[:current_user]
    {:ok, post} = MyApp.Posts.create_post(Map.put(params, "user_id", current_user.id))
    json(conn, %{ok: true, data: post})
  end

  defp require_authenticated_user(conn, _opts) do
    case conn.assigns[:current_user] do
      nil  -> conn |> put_status(401) |> json(%{error: "non autenticato"}) |> halt()
      _usr -> conn
    end
  end
end
```

### Auth-check riconosciuti dal ruleset (esclusioni `pattern-not-inside`)

- `plug :require_authenticated_user` nel modulo controller
- `plug :authenticate_user` (variante comune)
- `conn.assigns[:current_user]` verificato nel corpo dell'action con guard/case
- `Plug.Conn.halt/1` come risposta 401/403 prima della scrittura

---

## Dipendenze vulnerabili rilevate (SEED:EX-S2)

Il lockfile `mix.lock` fissa le versioni dei pacchetti Hex. osv-scanner interroga
il database OSV sul file di lock e riporta i pacchetti con advisory noti.

**Seed seminato:** `plug 1.10.3` — vulnerabile a EEF-CVE-2026-8468 / GHSA-468c-vq7p-gh64
(Unbounded buffer accumulation nella gestione degli header multipart → DoS, CWE-770).

---

## Secret hardcoded (SEED:EX-S1)

In Phoenix, le credenziali appaiono tipicamente in:
- `config/config.exs` — configurazione build-time (pericoloso: committato nel repo).
- `config/dev.exs` — configurazione sviluppo (pericoloso se contiene password reali).
- `config/runtime.exs` — configurazione runtime (SAFE se usa `System.get_env/1`).

Il pattern sicuro legge i segreti **solo** dall'ambiente:

```elixir
# config/runtime.exs — CONTRASTO PULITO (nessun finding gitleaks)
config :my_app, MyApp.Repo,
  url: System.get_env("DATABASE_URL") ||
    raise "DATABASE_URL non impostata"
```

---

## Preflight specifico

- `mix.lock` presente — assente → osv-scanner non può girare, degradato e dichiarato.
- Nessun DB live richiesto (phoenix-ex non ha controlli RLS a runtime nel tier detection).
- Semgrep Elixir: l'engine OSS (`semgrep/semgrep:latest`) non parsa Elixir (richiede l'engine Pro `--pro-languages`). authz/injection sono **fuori dal floor** e degradano onestamente (gap dichiarato `L-COL-006`, non bloccanti per il gate detection F4; deferred F6).
