#!/usr/bin/env node
// Preserve the complete local Harness theme plugin. Its real factory/apply
// lifecycle owns token overrides, shell CSS and the scroll sensor together.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const args = process.argv.slice(2);
if (args.length < 2 || args.length > 3 || (args[2] && args[2] !== '--check') || !args[1].endsWith('.js')) {
  console.error('Usage: node extract-theme.mjs <theme client.js> <output.js> [--check]');
  process.exit(2);
}
const sourcePath = path.resolve(args[0]);
const outputPath = path.resolve(args[1]);
const source = fs.readFileSync(sourcePath);
const manifest = JSON.parse(fs.readFileSync(path.join(path.dirname(sourcePath), 'package.json'), 'utf8'));
if (args[2] === '--check') {
  if (!fs.readFileSync(outputPath).equals(source)) throw new Error('Bundled theme plugin differs from its complete original source');
} else {
  fs.writeFileSync(outputPath, source);
}
console.log(JSON.stringify({ mode: args[2] === '--check' ? 'verified' : 'written', theme: manifest.name,
  version: manifest.version, bytes: source.length, sha256: crypto.createHash('sha256').update(source).digest('hex') }));
