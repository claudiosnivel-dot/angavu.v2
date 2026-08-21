#!/usr/bin/env node
// session_start_nudge.mjs — hook SessionStart del plugin Trueline (piano Task 8).
//
// Node ESM, SOLO built-in (nessun import): stampa una stringa STATICA e veloce.
// Niente preflight né I/O: il nudge deve essere istantaneo all'avvio della sessione.
// Nomina la skill 'trueline' e i suoi trigger, così l'agente sa quando invocarla.

const NUDGE =
  'Trueline è disponibile per audit di sicurezza / remediation / blueprint su ' +
  'progetti JS/TS+Supabase. Se l\'utente chiede di rivedere la sicurezza, fare un ' +
  'audit, mettere in sicurezza, remediate, bonificare secret o RLS, o avviare/' +
  'avanzare un progetto (blueprint), invoca la skill trueline.';

process.stdout.write(NUDGE + '\n');
