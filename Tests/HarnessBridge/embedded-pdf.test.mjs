import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';

test('embedded chat does not load the hidden PDF; standalone reader still does', async (t) => {
  const client = process.env.HARNESS_PDF_CLIENT || path.join(os.homedir(), 'Documents/deepseek-harness/default-workspace/pdf-reading-mode/client.js');
  let source;
  try { source = await readFile(client, 'utf8'); }
  catch (error) { if (error.code === 'ENOENT') return t.skip('Harness PDF reading plugin not installed'); throw error; }
  const anchor = source.indexOf('let cancelled=false,task,opened;setDocument(null);');
  const start = source.lastIndexOf('useEffect(()=>{', anchor);
  const end = source.indexOf('},[paper?.id]);', anchor);
  assert.ok(anchor >= 0 && start >= 0 && end >= 0, 'PDF loading effect must be located for this regression check');
  const effect = source.slice(start, end + '},[paper?.id]);'.length)
    .replace("import('/pdf-reading/assets/pdf.mjs')", 'loadPdfModule()');
  assert.ok(effect.includes('loadPdfModule()'), 'PDF module import must be intercepted');
  function pdfLoadCount(embedded) {
    let loads = 0;
    const invoke = new Function('useEffect', 'window', 'setDocument', 'selectionRef', 'findCache',
      'setFindMatches', 'setFindIndex', 'setFindOpen', 'setFindQuery', 'model', 'paper',
      'loadPdfModule', 'flushPosition', 'zoom', 'clearTimeout', 'cancelAnimationFrame', effect);
    invoke(callback => callback(), { __PDFLIGHT_EMBED__: embedded }, () => {}, { current: null },
      { current: new Map() }, () => {}, () => {}, () => {}, () => {}, { patch() {} }, { id: 'fixture' },
      () => { loads++; return new Promise(() => {}); }, () => {}, { current: {} }, () => {}, () => {});
    return loads;
  }
  assert.equal(pdfLoadCount(false), 1, 'standalone Harness must load the PDF');
  assert.equal(pdfLoadCount(true), 0, 'PDFlight must not load a second, hidden PDF');
});
