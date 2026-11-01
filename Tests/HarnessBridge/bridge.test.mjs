import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, mkdir, readFile, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { Readable } from 'node:stream';

const root = await mkdtemp(path.join(os.tmpdir(), 'pdflight-harness-tests-'));
process.env.PDFLIGHT_HARNESS_SUPPORT_DIRECTORY = path.join(root, 'support');
const { safelyImportable, resolvePaper, createHandler, paperTabTitle, installConversationTitlePolicy } = await import('../../Services/harness-chat/index.js');

function mockReader(papers = []) {
  let imports = 0;
  return {
    get imports() { return imports; },
    async library() { return { papers }; },
    async import({ path: filename }) {
      imports++;
      const paper = { id: `new-${imports}`, title: path.basename(filename).replace(/\.pdf$/i, ''), path: filename };
      papers.push(paper);
      return paper;
    },
    async conversations() { return { conversations: [] }; },
  };
}
function request(body, rejected) {
  const req = Readable.from([Buffer.from(JSON.stringify(body))]);
  req.method = 'POST';
  req.headers = { 'content-type': 'application/json' };
  const result = {};
  const res = { writeHead(code) { result.code = code; return this; }, end(data) { result.body = data ? JSON.parse(data) : null; return this; } };
  return { req, res, result, connection: { requestRejection: () => rejected } };
}

test('legacy eligibility preserves whitespace and incomplete or consecutive messages', () => {
  const history = { conversations: [{ messages: [
    { role: 'user', content: ' first  ' }, { role: 'user', content: 'second' },
    { role: 'assistant', content: 'answer\n' }, { role: 'user', content: 'unfinished' },
  ] }] };
  assert.equal(safelyImportable(history), true);
  history.conversations[0].messages[0].imageAttachments = [{ name: 'image.png' }];
  assert.equal(safelyImportable(history), false);
  assert.equal(safelyImportable({ conversations: [{ messages: [{ role: 'system', content: 'hidden' }] }] }), false);
});

test('paper conversation titles use the exact same author-year rule as the PDF tabs', () => {
  assert.equal(paperTabTitle('Li 等 - 2025 - A Study of RAG.pdf'), 'A Study of RAG');
  assert.equal(paperTabTitle('Smith et al. - 2024 - A - B'), 'A - B');
  assert.equal(paperTabTitle('My own conversation.pdf'), 'My own conversation.pdf');
});

test('normalizes existing automatic paper names and newly opened sessions, without changing custom or running titles', async () => {
  const raw = 'Li 等 - 2025 - A Study.pdf';
  const papers = [{ id: 'paper', title: raw }];
  const entries = [
    { sessionId: 'automatic', title: raw, available: true },
    { sessionId: 'custom', title: raw, available: true },
    { sessionId: 'running', title: raw, available: true },
  ];
  const sessions = [
    { sessionId: 'automatic', projections: { values: { title: raw } } },
    { sessionId: 'custom', projections: { values: { title: 'My research notes' } } },
    { sessionId: 'running', projections: { values: { title: raw } }, running: true },
  ];
  const renamed = [];
  const controller = {
    async list() { return { items: sessions }; },
    async rename(request) {
      renamed.push(request);
      sessions.find(item => item.sessionId === request.sessionId).projections.values.title = request.title;
    },
  };
  const original = async input => ({ sessionId: input.sessionId, conversations: entries });
  const reader = { conversation: original, async library() { return { papers }; }, async conversations() { return { conversations: entries }; } };
  const dispose = installConversationTitlePolicy(reader, controller);
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(renamed, [{ sessionId: 'automatic', title: 'A Study' }]);
  assert.equal(sessions[1].projections.values.title, 'My research notes');
  assert.equal(sessions[2].projections.values.title, raw);
  sessions[2].running = false;
  await reader.conversation({ paperId: 'paper', action: 'select', sessionId: 'running' });
  assert.deepEqual(renamed[1], { sessionId: 'running', title: 'A Study' });
  dispose();
  assert.equal(reader.conversation, original);
});

test('match an existing Harness paper by title and bytes, then retain its identity after a save', async () => {
  const sourceDir = path.join(root, 'source');
  const copyDir = path.join(root, 'library');
  await mkdir(sourceDir); await mkdir(copyDir);
  const source = path.join(sourceDir, 'same.pdf');
  const copy = path.join(copyDir, 'copy.pdf');
  await writeFile(source, 'original PDF bytes'); await writeFile(copy, 'original PDF bytes');
  const reader = mockReader([{ id: 'existing', title: 'same', path: copy }]);
  assert.equal((await resolvePaper(reader, source)).paper.id, 'existing');
  await writeFile(source, 'PDF bytes after annotation');
  assert.equal((await resolvePaper(reader, source)).paper.id, 'existing');
  assert.equal(reader.imports, 0);
  const otherDir = path.join(root, 'other'); await mkdir(otherDir);
  const other = path.join(otherDir, 'same.pdf'); await writeFile(other, 'a different PDF');
  assert.equal((await resolvePaper(reader, other)).paper.id, 'new-1');
  assert.equal(reader.imports, 1);
});

test('reject unauthenticated requests and retain unsupported legacy attachments', async () => {
  const source = path.join(root, 'image.pdf'); await writeFile(source, 'PDF');
  const historyDir = path.join(root, 'histories'); await mkdir(historyDir);
  const id = createHash('sha256').update(source).digest('hex');
  const history = { documentPath: source, documentTitle: 'image.pdf', conversations: [{ messages: [
    { role: 'user', content: 'question', imageAttachments: [{ name: 'image.png' }] },
    { role: 'assistant', content: 'answer' },
  ] }] };
  const historyFile = path.join(historyDir, `${id}.json`);
  const original = JSON.stringify(history); await writeFile(historyFile, original);
  const workspace = { title: '00_paper', path: path.join(root, '00_paper'), async status() { return 'ok'; } };
  const registry = { list: () => [workspace] };
  const reader = mockReader();
  const denied = request({ path: source }, 401);
  await createHandler(reader, denied.connection, registry, historyDir)(denied.req, denied.res);
  assert.equal(denied.result.code, 401);
  assert.equal(reader.imports, 0);
  const allowed = request({ path: source });
  await createHandler(reader, allowed.connection, registry, historyDir)(allowed.req, allowed.res);
  assert.equal(allowed.result.code, 200);
  assert.equal(allowed.result.body.migration, 'retained');
  assert.equal(await readFile(historyFile, 'utf8'), original);
});
