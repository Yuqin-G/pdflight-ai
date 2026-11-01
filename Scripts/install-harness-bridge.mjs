#!/usr/bin/env node
// Install only PDFlight's own local bundle. Do not run a package-manager
// reconciliation over the user's other Harness plugins.
import { createHash, randomUUID } from 'node:crypto';
import { copyFile, lstat, mkdir, readFile, readlink, rename, symlink, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const source = path.resolve(process.argv[2] || path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'Services', 'harness-chat'));
const home = process.env.DSH_HOME || path.join(os.homedir(), '.dsh');
const profile = process.env.PDFLIGHT_HARNESS_PROFILE || 'desktop';
const profileDirectory = path.join(home, 'profiles', profile);
const manifestPath = path.join(profileDirectory, 'package.json');
const pluginName = '@local/pdflight-harness-chat';
const files = ['package.json', 'cordis.patch.yml', 'index.js', 'client.js'];
const bytes = await Promise.all(files.map(name => readFile(path.join(source, name))));
const digest = createHash('sha256').update(Buffer.concat(bytes)).digest('hex').slice(0, 16);
const pluginRoot = path.join(home, 'local-plugins', 'pdflight-harness-chat');
const destination = path.join(pluginRoot, digest);
const manifestText = await readFile(manifestPath, 'utf8');
const manifest = JSON.parse(manifestText);
if (!Array.isArray(manifest.dsh?.profile?.bundles) || !manifest.dsh.profile.bundles.includes('@local/pdf-reading-mode')) {
  throw new Error('The Harness profile must have its PDF reading plugin enabled first.');
}
const existingDependency = manifest.dependencies?.[pluginName];
if (existingDependency && !existingDependency.startsWith(`link:${pluginRoot}/`)) {
  throw new Error('A different PDFlight Harness plugin is already installed; its configuration was left unchanged.');
}
await mkdir(destination, { recursive: true, mode: 0o700 });
for (let i = 0; i < files.length; i++) await copyFile(path.join(source, files[i]), path.join(destination, files[i]));
const moduleDirectory = path.join(profileDirectory, 'node_modules', '@local');
const modulePath = path.join(moduleDirectory, 'pdflight-harness-chat');
await mkdir(moduleDirectory, { recursive: true });
try {
  const info = await lstat(modulePath);
  if (!info.isSymbolicLink()) throw new Error('An unrelated plugin already exists at the target path.');
  const old = path.resolve(moduleDirectory, await readlink(modulePath));
  if (!old.startsWith(`${pluginRoot}/`)) throw new Error('An unrelated plugin link already exists at the target path.');
} catch (error) { if (error.code !== 'ENOENT') throw error; }
manifest.dependencies ??= {};
manifest.dependencies[pluginName] = `link:${destination}`;
if (!manifest.dsh.profile.bundles.includes(pluginName)) manifest.dsh.profile.bundles.push(pluginName);
if (await readFile(manifestPath, 'utf8') !== manifestText) throw new Error('Harness profile changed during installation; retry.');
const suffix = randomUUID();
const linkTemporary = `${modulePath}.${suffix}.tmp`;
const manifestTemporary = `${manifestPath}.${suffix}.tmp`;
await mkdir(path.join(pluginRoot, 'profile-backups'), { recursive: true, mode: 0o700 });
await writeFile(path.join(pluginRoot, 'profile-backups', `package-${suffix}.json`), manifestText, { mode: 0o600, flag: 'wx' });
await symlink(destination, linkTemporary);
await writeFile(manifestTemporary, `${JSON.stringify(manifest, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
await rename(linkTemporary, modulePath);
await rename(manifestTemporary, manifestPath);

// A newly added bundle is loaded by Harness immediately, but changing an
// existing link alone does not reload it. Cycle only this bundle when an older
// bridge is still running, preserving unrelated profile edits.
const support = process.env.PDFLIGHT_HARNESS_SUPPORT_DIRECTORY
  || path.join(os.homedir(), 'Library', 'Application Support', 'dev.pdflight.reader');
const markerPath = path.join(support, 'harness-bridge', 'desktop.json');
let marker;
try { marker = JSON.parse(await readFile(markerPath, 'utf8')); } catch { /* Host is not running. */ }
let running = false;
if (Number.isInteger(marker?.pid) && marker.pid > 0) {
  try { process.kill(marker.pid, 0); running = true; } catch { /* Stale marker. */ }
}
if (running && marker.revision !== digest) {
  async function updateBundle(enabled) {
    const current = JSON.parse(await readFile(manifestPath, 'utf8'));
    const bundles = current.dsh.profile.bundles;
    current.dsh.profile.bundles = bundles.filter(name => name !== pluginName);
    if (enabled) current.dsh.profile.bundles.push(pluginName);
    const temporary = `${manifestPath}.${randomUUID()}.tmp`;
    await writeFile(temporary, `${JSON.stringify(current, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
    await rename(temporary, manifestPath);
  }
  await updateBundle(false);
  try {
    for (let i = 0; i < 30; i++) {
      try { await lstat(markerPath); } catch (error) { if (error.code === 'ENOENT') break; throw error; }
      await new Promise(resolve => setTimeout(resolve, 200));
    }
  } finally { await updateBundle(true); }
}
console.log(`Installed the PDFlight Harness bridge in profile ${profile}.`);
