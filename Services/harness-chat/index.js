import { createHash, randomUUID } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { chmod, mkdir, readFile, realpath, rename, rm, stat, unlink, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { zstdCompressSync, zstdDecompressSync } from 'node:zlib';

export const inject = ['webServer', 'connection', 'pdfReading', 'workspaceRegistry', 'sessionController'];
const supportDirectory = process.env.PDFLIGHT_HARNESS_SUPPORT_DIRECTORY
  || path.join(os.homedir(), 'Library', 'Application Support', 'dev.pdflight.reader');
const MAX_BODY = 64 * 1024;

/** Match the PDF reader's tab-label rule, including its treatment of extensions. */
export function paperTabTitle(value) {
  const text = typeof value === 'string' ? value.trim() : '';
  const match = /^.+?\s-\s\d{4}\s-\s(.+)$/.exec(text);
  return match ? match[1].replace(/\.pdf$/i, '').trim() || text : text;
}

/** Keep real Harness session titles aligned with their paper tabs. */
export function installConversationTitlePolicy(pdfReading, sessionController) {
  const original = pdfReading.conversation;
  const inFlight = new Set();
  let active = true;

  async function renameAutomaticTitle(paper, entry, session) {
    const title = paperTabTitle(paper?.title);
    const nativeTitle = session?.projections?.values?.title ?? session?.title;
    if (!active || !entry?.available || !session || session.running ||
        !title || title === paper.title || entry.title !== paper.title ||
        nativeTitle !== paper.title || inFlight.has(entry.sessionId)) return;
    inFlight.add(entry.sessionId);
    try { await sessionController.rename({ sessionId: entry.sessionId, title }); }
    catch (error) {
      if (process.env.PDFLIGHT_HARNESS_DEBUG === '1') console.error('Paper title normalization failed:', error);
    } finally { inFlight.delete(entry.sessionId); }
  }

  async function normalizeExisting() {
    try {
      const [{ papers }, { items }] = await Promise.all([
        pdfReading.library(), sessionController.list({}, new AbortController().signal),
      ]);
      const sessions = new Map(items.map(item => [item.sessionId, item]));
      for (const paper of papers) {
        if (!active || paperTabTitle(paper.title) === paper.title) continue;
        const { conversations } = await pdfReading.conversations({ paperId: paper.id });
        for (const entry of conversations) await renameAutomaticTitle(paper, entry, sessions.get(entry.sessionId));
      }
    } catch (error) {
      if (process.env.PDFLIGHT_HARNESS_DEBUG === '1') console.error('Paper title audit failed:', error);
    }
  }

  async function wrapped(input) {
    const result = await original.call(pdfReading, input);
    if (!active || !result?.sessionId || input?.action === 'delete') return result;
    try {
      const [{ papers }, { items }] = await Promise.all([
        pdfReading.library(), sessionController.list({}, new AbortController().signal),
      ]);
      const paper = papers.find(value => value.id === input.paperId);
      const entry = result.conversations?.find(value => value.sessionId === result.sessionId);
      await renameAutomaticTitle(paper, entry, items.find(value => value.sessionId === result.sessionId));
    } catch (error) {
      if (process.env.PDFLIGHT_HARNESS_DEBUG === '1') console.error('Paper title lookup failed:', error);
    }
    return result;
  }

  pdfReading.conversation = wrapped;
  void normalizeExisting();
  return () => {
    active = false;
    if (pdfReading.conversation === wrapped) pdfReading.conversation = original;
  };
}

async function hashFile(filename) {
  const digest = createHash('sha256');
  for await (const chunk of createReadStream(filename)) digest.update(chunk);
  return digest.digest('hex');
}

/** Only use the legacy importer when it can preserve every message's text. */
export function safelyImportable(history) {
  if (!history || !Array.isArray(history.conversations)) return false;
  return history.conversations.every(conversation => {
    if (!Array.isArray(conversation.messages)) return false;
    return conversation.messages.every(message => {
      return (message.role === 'user' || message.role === 'assistant') && typeof message.content === 'string'
        && (!message.imageAttachments || message.imageAttachments.length === 0);
    });
  });
}

async function legacyImportEligibility(pdfPath, historyDir = path.join(supportDirectory, 'ai-chats')) {
  const expected = createHash('sha256').update(pdfPath).digest('hex') + '.json';
  let text;
  try { text = await readFile(path.join(historyDir, expected), 'utf8'); }
  catch (error) { if (error.code === 'ENOENT') return 'none'; throw error; }
  let history;
  try { history = JSON.parse(text); } catch { return 'unsafe'; }
  if (history?.documentPath !== pdfPath || !safelyImportable(history)) return 'unsafe';
  return history.conversations.some(conversation => conversation.messages.length) ? 'safe' : 'none';
}

let pathMappingsQueue = Promise.resolve();

async function withPathMappings(operation) {
  const result = pathMappingsQueue.then(async () => {
    const directory = path.join(supportDirectory, 'harness-bridge');
    const filename = path.join(directory, 'paper-paths.json');
    let mappings = {};
    try { mappings = JSON.parse(await readFile(filename, 'utf8')); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    const outcome = await operation(mappings);
    if (outcome.changed) {
      await mkdir(directory, { recursive: true, mode: 0o700 });
      const temporary = path.join(directory, `.paper-paths-${randomUUID()}.tmp`);
      try {
        await writeFile(temporary, JSON.stringify(mappings), { mode: 0o600, flag: 'wx' });
        await rename(temporary, filename);
      } finally { await unlink(temporary).catch(() => {}); }
    }
    return outcome.value;
  });
  pathMappingsQueue = result.catch(() => {});
  return result;
}

/** Prefer a saved source path; otherwise match a library paper by its bytes. */
export async function resolvePaper(pdfReading, inputPath) {
  if (typeof inputPath !== 'string' || !path.isAbsolute(inputPath) || path.extname(inputPath).toLowerCase() !== '.pdf') {
    throw new Error('请选择有效的本地 PDF。');
  }
  const pdfPath = await realpath(inputPath);
  const file = await stat(pdfPath);
  if (!file.isFile()) throw new Error('无法打开 PDF 文件。');
  return withPathMappings(async mappings => {
    const { papers } = await pdfReading.library();
    const mapped = papers.find(paper => paper.id === mappings[pdfPath]);
    if (mapped) return { value: { paper: mapped, pdfPath }, changed: false };
    const paperName = value => path.basename(value).replace(/\.pdf$/i, '').toLowerCase();
    const candidates = papers.filter(paper => paperName(paper.title) === paperName(pdfPath));
    let sourceHash;
    for (const paper of candidates) {
      try {
        const existing = await stat(paper.path);
        if (existing.size !== file.size) continue;
        sourceHash ??= await hashFile(pdfPath);
        if (sourceHash === await hashFile(paper.path)) {
          mappings[pdfPath] = paper.id;
          return { value: { paper, pdfPath }, changed: true };
        }
      } catch { /* A missing copy must not be mistaken for this PDF. */ }
    }
    const paper = await pdfReading.import({ path: pdfPath });
    mappings[pdfPath] = paper.id;
    return { value: { paper, pdfPath }, changed: true };
  });
}

async function readJSON(req) {
  if (req.method !== 'POST' || !/^application\/json(?:\s*;|$)/i.test(req.headers['content-type'] || '')) throw new Error('Invalid request');
  const chunks = []; let bytes = 0;
  for await (const chunk of req) {
    bytes += chunk.length;
    if (bytes > MAX_BODY) throw new Error('Request too large');
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

async function importLegacy(pdfReading, paper, pdfPath, workspace, historyDir, currentModel) {
  const harnessHome = process.env.DSH_HOME || path.join(os.homedir(), '.dsh');
  const profile = process.env.PDFLIGHT_HARNESS_PROFILE || 'desktop';
  const profileRequire = createRequire(path.join(harnessHome, 'profiles', profile, 'package.json'));
  const pdfPluginEntry = profileRequire.resolve('@local/pdf-reading-mode');
  const { encodeLegacySession, sessionDirectoryName } = await import(new URL('./legacy-import.js', pathToFileURL(pdfPluginEntry)));
  const directory = historyDir || path.join(supportDirectory, 'ai-chats');
  const filename = createHash('sha256').update(pdfPath).digest('hex') + '.json';
  const history = JSON.parse(await readFile(path.join(directory, filename), 'utf8'));
  if (!safelyImportable(history) || history.documentPath !== pdfPath) throw new Error('Legacy history changed during import');
  let number = 0;
  for (const conversation of history.conversations) {
    if (!conversation.messages.length) continue;
    const sessionId = `session-${randomUUID()}`;
    const title = `PDFlight ${conversation.title || `阅读记录 ${++number}`}`;
    const createdAt = Date.parse(conversation.createdAt);
    const selection = currentModel?.();
    const original = zstdDecompressSync(encodeLegacySession({ id: sessionId, cwd: workspace.path, title, turns: [], createdAt,
      ...(selection?.provider && selection?.model ? { provider: selection.provider, model: selection.model } : {}) })).toString('utf8');
    let rows = original.trimEnd().split('\n').map(line => JSON.parse(line));
    const header = rows.shift();
    // The older importer forced full filesystem access. Inherit Harness's
    // current permission settings instead of changing the user's policy.
    rows = rows.filter(row => !['permission/preset', 'sandbox/mode', 'approval/policy'].includes(row.type));
    if (!selection?.provider || !selection?.model) {
      const index = rows.findIndex(row => row.type === 'model/selection');
      if (index >= 0) rows.splice(index, 1);
    }
    let seq = 0;
    let clock = Number.isFinite(createdAt) ? createdAt : Date.now();
    for (const row of rows) { row.seq = seq++; row.time = clock++; }
    const emit = (type, data, surfaceOp, date) => {
      if (Number.isFinite(date)) clock = Math.max(clock, date);
      const row = { type, seq: seq++, time: clock++, data };
      if (surfaceOp) row.surfaceOp = surfaceOp;
      rows.push(row);
    };
    let turn = 0;
    let active = false;
    const closeTurn = () => {
      if (!active) return;
      emit('step/end', { turn, step: 1 });
      emit('turn/end', { turn, reason: { kind: 'completed' } });
      active = false;
    };
    for (const message of conversation.messages) {
      if (message.role === 'user' || !active) {
        closeTurn();
        turn++;
        emit('turn/start', { turn });
        emit('step/start', { turn, step: 1 });
        active = true;
      }
      const id = typeof message.id === 'string' && message.id ? message.id : randomUUID();
      const time = Date.parse(message.createdAt);
      if (message.role === 'user') emit('user/message', { content: [{ type: 'text', text: message.content }], source: { kind: 'user' }, role: 'user', id }, 'append', time);
      else emit('assistant/message', { turn, step: 1, message: { role: 'assistant', content: [{ type: 'text', text: message.content }], source: { kind: 'model', ...(selection?.provider && selection?.model ? { provider: selection.provider, model: selection.model } : {}) }, id }, stream: [] }, 'append', time);
    }
    closeTurn();
    // Current Harness expects a standalone header frame followed by event frames.
    const bytes = Buffer.concat([
      zstdCompressSync(Buffer.from(`${JSON.stringify(header)}\n`)),
      zstdCompressSync(Buffer.from(`${rows.map(row => JSON.stringify(row)).join('\n')}\n`)),
    ]);
    const sessionDirectory = path.join(harnessHome, 'sessions', sessionDirectoryName(workspace.path), sessionId);
    let attached = false;
    try {
      await mkdir(sessionDirectory, { recursive: true });
      await writeFile(path.join(sessionDirectory, 'session.v4.jsonl.zstd'), bytes, { flag: 'wx', mode: 0o600 });
      await writeFile(path.join(sessionDirectory, 'session.lock'), '', { flag: 'a', mode: 0o600 });
      await workspace.attachSession(sessionId);
      attached = true;
      for (let attempt = 0; ; attempt++) {
        try {
          await pdfReading.attach({ paperId: paper.id, sessionId, title, createdAt: Number.isFinite(createdAt) ? conversation.createdAt : undefined, workspaceId: workspace.id });
          break;
        } catch (error) {
          if (!/not registered yet/u.test(error.message) || attempt >= 5) throw error;
          await new Promise(resolve => setTimeout(resolve, 150));
        }
      }
    } catch (error) {
      if (!attached) await rm(sessionDirectory, { recursive: true, force: true });
      throw error;
    }
  }
}

export function createHandler(pdfReading, connection, workspaceRegistry, historyDir, currentModel, currentZoom) {
  const pending = new Map();
  return async (req, res) => {
    const denied = connection.requestRejection(req);
    if (denied !== undefined) { res.writeHead(denied).end(); return; }
    try {
      const body = await readJSON(req);
      const key = body.path;
      if (typeof key !== 'string') throw new Error('Invalid PDF path');
      if (!pending.has(key)) {
        const operation = (async () => {
          let paperWorkspace;
          for (const workspace of workspaceRegistry.list()) {
            if ((workspace.title === '00_paper' || path.basename(workspace.path) === '00_paper')
              && await workspace.status() === 'ok') { paperWorkspace = workspace; break; }
          }
          if (!paperWorkspace) {
            const workspacePath = path.join(supportDirectory, 'harness-workspaces', '00_paper');
            await mkdir(workspacePath, { recursive: true, mode: 0o700 });
            paperWorkspace = await workspaceRegistry.resolveByPath(workspacePath)
              || await workspaceRegistry.create(workspacePath);
          }
          const { paper } = await resolvePaper(pdfReading, key);
          // PDFlight identifies its history by the standardized path, which can
          // differ from realpath when the document was opened through a symlink.
          const historyPath = path.resolve(key);
          let migration = await legacyImportEligibility(historyPath, historyDir);
          if (migration === 'safe') {
            try {
              const existing = await pdfReading.conversations({ paperId: paper.id });
              // The upstream importer archives unavailable PDFlight entries. Leave
              // those recoverable histories alone rather than invoking it on them.
              if (existing.conversations.some(entry => entry.title.startsWith('PDFlight') && !entry.available)) {
                migration = 'retained';
              } else {
                if (existing.conversations.some(entry => entry.title.startsWith('PDFlight') && entry.available)) {
                  migration = 'already-imported';
                } else {
                  await importLegacy(pdfReading, paper, historyPath, paperWorkspace, historyDir, currentModel);
                  migration = 'imported';
                }
              }
            }
            catch (error) {
              if (process.env.PDFLIGHT_HARNESS_DEBUG === '1') console.error('PDFlight legacy import failed:', error);
              migration = 'retained';
            }
          } else if (migration === 'unsafe') migration = 'retained';
          return { paperId: paper.id, migration, chatZoom: currentZoom?.() };
        })();
        pending.set(key, operation);
        operation.finally(() => pending.delete(key)).catch(() => {});
      }
      const result = await pending.get(key);
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' }).end(JSON.stringify(result));
    } catch (error) {
      res.writeHead(400, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' }).end(JSON.stringify({ error: error.message || '无法打开论文对话。' }));
    }
  };
}

export async function apply(ctx) {
  const markerDir = path.join(supportDirectory, 'harness-bridge');
  const marker = path.join(markerDir, 'desktop.json');
  const instance = randomUUID();
  let chatZoom;
  await mkdir(markerDir, { recursive: true, mode: 0o700 });
  await chmod(markerDir, 0o700);
  ctx.effect(() => installConversationTitlePolicy(ctx.pdfReading, ctx.sessionController));
  ctx.effect(() => ctx.webServer.register({ kind: 'exact', path: '/pdflight-bridge/paper', handler: createHandler(ctx.pdfReading, ctx.connection, ctx.workspaceRegistry, undefined, () => ctx.get('agentDefaultModel')?.currentSelection(), () => chatZoom) }));
  ctx.effect(() => ctx.webServer.register({ kind: 'exact', path: '/pdflight-bridge/zoom', handler: async (req, res) => {
    const denied = ctx.connection.requestRejection(req);
    if (denied !== undefined) { res.writeHead(denied).end(); return; }
    try {
      if (req.method === 'POST') {
        const body = await readJSON(req);
        if (typeof body.zoom !== 'number' || !Number.isFinite(body.zoom) || body.zoom < 0.8 || body.zoom > 2.4) throw new Error('Invalid zoom');
        chatZoom = body.zoom;
      } else if (req.method !== 'GET') throw new Error('Invalid request');
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' }).end(JSON.stringify({ zoom: chatZoom }));
    } catch { res.writeHead(400).end(); }
  } }));
  const url = ctx.connection.authenticatedUrl(`${ctx.webServer.protocol}//127.0.0.1:${ctx.webServer.port}/`);
  const temporary = path.join(markerDir, `.desktop-${instance}.tmp`);
  const revision = path.basename(path.dirname(fileURLToPath(import.meta.url)));
  await writeFile(temporary, JSON.stringify({ url, instance, pid: process.pid, revision }), { mode: 0o600, flag: 'wx' });
  await rename(temporary, marker);
  ctx.effect(() => () => {
    void readFile(marker, 'utf8').then(text => {
      if (JSON.parse(text).instance === instance) return unlink(marker);
    }).catch(() => {});
  });
}
