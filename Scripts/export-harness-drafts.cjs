// One-time, read-only extraction from a COPY of Chromium Local Storage.
// Usage: node export-harness-drafts.cjs <copied-leveldb> <classic-level-module> <paper-conversations.json> <output-file>
// Output contains only paper-session drafts. Do not run this on a live LevelDB.
const fs = require('node:fs/promises');
const { ClassicLevel } = require(process.argv[3]);

async function main() {
  const [databasePath, , groupsPath, output] = process.argv.slice(2);
  if (!databasePath || !groupsPath || !output) throw new Error('Missing arguments');
  const groups = JSON.parse(await fs.readFile(groupsPath, 'utf8'));
  const paperSessions = new Set(groups.groups.flatMap(group => group.conversations.map(item => item.sessionId)));
  const drafts = [];
  const zoomValues = new Set();
  const db = new ClassicLevel(databasePath, { keyEncoding: 'buffer', valueEncoding: 'buffer' });
  try {
    for await (const [key, value] of db.iterator()) {
      const encodedKey = key.toString('utf8');
      if (encodedKey.includes('pdf-reading-chat-zoom') && value.length) {
        const encoding = value[0] === 0 ? 'utf16le' : value[0] === 1 ? 'latin1' : null;
        const zoom = encoding && Number(value.subarray(1).toString(encoding));
        if (typeof zoom === 'number' && zoom >= 0.8 && zoom <= 2.4) zoomValues.add(zoom);
      }
      const offset = encodedKey.indexOf('dsh.conversation.');
      if (offset < 0 || !value.length) continue;
      const sessionId = encodedKey.slice(offset + 'dsh.conversation.'.length).replace(/\0/g, '');
      if (!paperSessions.has(sessionId)) continue;
      const encoding = value[0] === 0 ? 'utf16le' : value[0] === 1 ? 'latin1' : null;
      if (!encoding) continue;
      let state;
      try { state = JSON.parse(value.subarray(1).toString(encoding)); } catch { continue; }
      const draft = typeof state.draft === 'string' ? { text: state.draft, references: [] } : state.draft;
      if (typeof draft?.text !== 'string' || (!draft.text && !draft.references?.length)) continue;
      drafts.push({ sessionId, draft });
    }
  } finally { await db.close(); }
  const file = await fs.open(output, 'wx', 0o600);
  const chatZoom = zoomValues.size === 1 ? [...zoomValues][0] : null;
  try { await file.writeFile(JSON.stringify({ version: 1, source: 'Harness Desktop', chatZoom, drafts }, null, 2)); }
  finally { await file.close(); }
  console.log(`Captured ${drafts.length} paper-session drafts; source data was not changed.`);
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
