import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
const manifest = JSON.parse(await fs.readFile('package.json', 'utf8'));
const installed = [];
for (const [name, expected] of Object.entries(manifest.devDependencies)) {
  const pkg = JSON.parse(await fs.readFile(path.join('node_modules', name, 'package.json'), 'utf8'));
  assert.equal(pkg.version, expected, `${name} does not match the pinned version`);
  installed.push({ name, version: pkg.version, license: pkg.license });
}
console.log(JSON.stringify({ node: process.version, installed }, null, 2));
console.log('PASS: installed JavaScript tools match the manifest');
