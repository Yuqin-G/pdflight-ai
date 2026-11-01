import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

test('Desktop reports its PDF-reading chat zoom without changing its layout', async () => {
  const source = await readFile(new URL('../../Services/harness-chat/client.js', import.meta.url), 'utf8');
  let definition, layoutChanges = 0;
  const requests = [];
  const effects = [];
  const window = {
    __ModuleLoader__: { load(value) { definition = value; } },
    localStorage: { getItem(key) { return key === 'pdf-reading-chat-zoom' ? '0.95' : null; } },
  };
  const scope = {
    window,
    fetch(url, options) { requests.push({ url, options }); return Promise.resolve({ ok: true }); },
    setInterval() { return 1; }, clearInterval() {},
    setTimeout() { throw new Error('Desktop should not select an embedded panel'); },
  };
  vm.runInNewContext(source, scope);
  definition.factory().apply({ layout: { selectPanel() { layoutChanges++; } }, effect(fn) { effects.push(fn()); } });
  assert.equal(requests.length, 1);
  assert.equal(requests[0].url, '/pdflight-bridge/zoom');
  assert.equal(JSON.parse(requests[0].options.body).zoom, 0.95);
  assert.equal(layoutChanges, 0);
  for (const dispose of effects) dispose?.();
});
