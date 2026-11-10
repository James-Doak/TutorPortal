// Uploads build/questions.json and build/diagrams.json into Supabase tables (readable only by logged-in users).
// Needs env: SUPABASE_URL and SUPABASE_SERVICE_KEY (service_role key; keep it secret, never commit it).
import fs from 'node:fs';

const url = process.env.SUPABASE_URL, key = process.env.SUPABASE_SERVICE_KEY;
if (!fs.existsSync('build/questions.json')) { console.log('No build/questions.json. Nothing to sync.'); process.exit(0); }
if (!url || !key) { console.error('Set SUPABASE_URL and SUPABASE_SERVICE_KEY.'); process.exit(1); }

const headers = { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json',
  Prefer: 'resolution=merge-duplicates,return=minimal' };
const post = async (table, body, onConflict) => {
  const r = await fetch(`${url}/rest/v1/${table}?on_conflict=${onConflict}`, { method: 'POST', headers, body: JSON.stringify(body) });
  if (!r.ok) throw new Error(`${table}: ${r.status} ${await r.text()}`);
};
const del = async (table, col, keep) => {
  // Remove rows no longer in the workbook.
  const r = await fetch(`${url}/rest/v1/${table}?${col}=not.in.(${keep.map((k) => `"${k.replace(/"/g, '\\"')}"`).join(',')})`, { method: 'DELETE', headers });
  if (!r.ok) throw new Error(`delete ${table}: ${r.status} ${await r.text()}`);
};
const chunks = (a, n = 200) => Array.from({ length: Math.ceil(a.length / n) }, (_, i) => a.slice(i * n, i * n + n));

const qs = JSON.parse(fs.readFileSync('build/questions.json', 'utf8'));
const dg = JSON.parse(fs.readFileSync('build/diagrams.json', 'utf8'));
for (const c of chunks(qs)) await post('questions', c.map((d) => ({ id: d.id, data: d })), 'id');
const dRows = Object.entries(dg).map(([question_id, figures]) => ({ question_id, figures }));
for (const c of chunks(dRows, 50)) await post('diagrams', c, 'question_id');
if (qs.length) await del('questions', 'id', qs.map((d) => d.id));
if (dRows.length) await del('diagrams', 'question_id', dRows.map((d) => d.question_id));
console.log(`Synced ${qs.length} questions and ${dRows.length} diagram sets to Supabase.`);
