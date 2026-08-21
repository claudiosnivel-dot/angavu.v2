// arch_contract.mjs — loader + validatore del CONTRATTO DI ALTITUDINE (A2b).
// Il blueprint dichiara `architecture: { layers, forbidden, allow }` in un blocco
// ```yaml di 00-INDEX.md. Questo è un CONSUMATORE NUOVO: replica l'idioma
// extractYamlBlocks (i loader di validate_blueprint/blueprint_tasks NON si toccano,
// L-COL-029) e parsa il solo sotto-schema `architecture:` (layers = mapping
// name->glob; forbidden/allow = liste di flow-map inline `- { k: v, ... }`).
// Deterministico, solo built-in.
import { readFileSync, existsSync, statSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

function extractYamlBlocks(text) {
  const blocks = [];
  const re = /```ya?ml\s*\n([\s\S]*?)```/g;
  let m;
  while ((m = re.exec(text)) !== null) blocks.push(m[1]);
  return blocks;
}

const unquote = (v) => {
  v = String(v).trim();
  if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) return v.slice(1, -1);
  return v;
};

// Divide "from: ui, to: data" sul primo livello, rispettando gli apici.
function splitTopComma(s) {
  const out = [];
  let cur = '', inS = false, inD = false;
  for (const c of s) {
    if (c === "'" && !inD) inS = !inS;
    else if (c === '"' && !inS) inD = !inD;
    if (c === ',' && !inS && !inD) { out.push(cur); cur = ''; continue; }
    cur += c;
  }
  if (cur.trim()) out.push(cur);
  return out;
}

// "{ from: ui, to: data, mode: direct }" -> { from:'ui', to:'data', mode:'direct' }
function parseFlowMap(s) {
  const inner = s.trim().replace(/^\{/, '').replace(/\}$/, '').trim();
  const obj = {};
  if (!inner) return obj;
  for (const part of splitTopComma(inner)) {
    const idx = part.indexOf(':');
    if (idx < 0) continue;
    const k = part.slice(0, idx).trim();
    const v = unquote(part.slice(idx + 1));
    if (k) obj[k] = v;
  }
  return obj;
}

// Rimuove un commento inline `# ...` QUOTE-AWARE: il `#` conta solo se è fuori
// dagli apici e (per idioma YAML) a inizio riga o preceduto da spazio. Così
// `note: "fix #123"` resta intatto, mentre `ui: "x"   # cmt` viene ripulito.
function stripComment(line) {
  let inS = false, inD = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === "'" && !inD) inS = !inS;
    else if (c === '"' && !inS) inD = !inD;
    else if (c === '#' && !inS && !inD && (i === 0 || /\s/.test(line[i - 1]))) return line.slice(0, i);
  }
  return line;
}

// Parsa il blocco YAML se contiene un top-level `architecture:`. Ritorna il
// contratto o null. indentOf per distinguere layers (mapping) da forbidden/allow.
function parseArchBlock(yaml) {
  const lines = yaml.replace(/\r\n/g, '\n').split('\n');
  const indentOf = (l) => l.length - l.trimStart().length;
  let i = 0;
  // trova `architecture:` al livello top (indent 0)
  while (i < lines.length && !/^architecture:\s*$/.test(lines[i])) i++;
  if (i >= lines.length) return null;
  i++;
  const contract = { layers: {}, forbidden: [], allow: [], raw: yaml };
  let section = null; // 'layers' | 'forbidden' | 'allow'
  for (; i < lines.length; i++) {
    const raw = lines[i];
    const ind = indentOf(raw); // indent sulla riga grezza
    const t = stripComment(raw).trim(); // toglie il commento inline, quote-aware
    if (t === '') continue; // riga vuota o solo-commento
    if (ind === 0) break; // fine del blocco architecture
    const sec = t.match(/^(layers|forbidden|allow):\s*$/);
    if (sec && ind <= 2) { section = sec[1]; continue; }
    if (section === 'layers') {
      const kv = t.match(/^([A-Za-z_][\w-]*):\s*(.+)$/);
      if (kv) contract.layers[kv[1]] = unquote(kv[2]);
    } else if (section === 'forbidden' || section === 'allow') {
      const item = t.match(/^-\s*(\{.*\})\s*$/);
      if (item) contract[section].push(parseFlowMap(item[1]));
    }
  }
  return contract;
}

// Carica il contratto dai file .md del blueprint (00-INDEX.md per convenzione, ma
// scansiona tutti i .md: il primo blocco con `architecture:` vince). null se assente.
export function loadArchContract(blueprintDir) {
  if (!existsSync(blueprintDir) || !statSync(blueprintDir).isDirectory()) return null;
  const files = readdirSync(blueprintDir).filter((f) => f.endsWith('.md')).sort();
  for (const f of files) {
    const text = readFileSync(join(blueprintDir, f), 'utf8');
    for (const block of extractYamlBlocks(text)) {
      if (/^architecture:\s*$/m.test(block)) {
        const c = parseArchBlock(block);
        if (c) return c;
      }
    }
  }
  return null;
}

// Validazione STRUTTURALE (plan-time): forma ben formata, NON aggancio al codice
// (quello è arch_check, build-time). >=1 strato con glob non vuoto, >=1 regola,
// from/to dichiarati, mode noto, allow verso strati dichiarati.
export function validateArchContract(c) {
  const errors = [];
  const layers = c && c.layers ? c.layers : {};
  const layerNames = Object.keys(layers);
  if (layerNames.length === 0) errors.push('nessuno strato dichiarato (layers vuoto)');
  for (const [name, glob] of Object.entries(layers)) {
    if (!glob || !String(glob).trim()) errors.push(`strato "${name}" senza selettore glob`);
  }
  const rules = (c && c.forbidden) || [];
  if (rules.length === 0) errors.push('nessuna regola forbidden (contratto vacuo)');
  const set = new Set(layerNames);
  for (const r of rules) {
    if (!set.has(r.from)) errors.push(`regola forbidden con from="${r.from}" non dichiarato`);
    if (!set.has(r.to)) errors.push(`regola forbidden con to="${r.to}" non dichiarato`);
    if (r.mode && !['direct', 'transitive'].includes(r.mode)) errors.push(`regola con mode="${r.mode}" ignoto (direct|transitive)`);
  }
  for (const a of (c && c.allow) || []) {
    if (!set.has(a.from) || !set.has(a.to)) errors.push(`allow con strato non dichiarato (${a.from}->${a.to})`);
  }
  return { ok: errors.length === 0, errors };
}
