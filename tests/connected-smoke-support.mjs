// Focused path/isolation checks; starts no R, browser, service or installer.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {overlaps, resolvedFuturePath, validateDestination, runtimeEnvironment, pinnedTools} from './fixtures/connected-smoke-support.mjs';
const root = await fs.mkdtemp(path.join(os.tmpdir(), 'brohn-portable-smoke-check-'));
const checks = []; const check = (value, label) => {assert.ok(value, label); checks.push(label);};
const request = Object.fromEntries(['project', 'forbidden_workspace', 'node_tools_root', 'r_library', 'rscript',
  'publication_python', 'publication_manifest', 'portability_python', 'configuration_path', 'browser_executable'].map(key => [key, path.join(root, key)]));
request.output = path.join(root, 'fresh evidence with spaces');
for (const [name, file] of Object.entries(request)) if (name !== 'output') {
  if (['project', 'node_tools_root', 'r_library'].includes(name)) await fs.mkdir(file); else if (name !== 'forbidden_workspace') await fs.writeFile(file, 'Original dummy runtime path, not executable.');
}
try {
  check(await validateDestination(request) === request.output, 'Fresh external evidence with spaces resolves without creating it');
  await assert.rejects(fs.stat(request.output), {code: 'ENOENT'});
  for (const target of [request.project, path.join(request.project, 'evidence'), request.forbidden_workspace,
    path.join(request.forbidden_workspace, 'child'), root, request.r_library, path.join(request.r_library, 'child')]) {
    await assert.rejects(validateDestination({...request, output: target}), /outside/); checks.push('Refuses protected overlap: ' + path.relative(root, target));
  }
  const existing = path.join(root, 'existing'); await fs.mkdir(existing);
  await assert.rejects(validateDestination({...request, output: existing}), /must not already exist/); checks.push('Existing evidence is never reused');
  await assert.rejects(validateDestination({...request, output: path.join(root, 'absent-parent', 'output')})); checks.push('Missing evidence parent is not silently created');
  const alias = path.join(root, 'alias'); await fs.symlink(request.project, alias, process.platform === 'win32' ? 'junction' : 'dir');
  await assert.rejects(validateDestination({...request, output: path.join(alias, 'evidence')}), /outside/); checks.push('Resolved junction into checkout cannot bypass evidence boundary');
  check(await resolvedFuturePath(path.join(alias, 'future', 'child')) === path.join(request.project, 'future', 'child'), 'Future path resolves existing junction ancestry');
  check(!overlaps(path.join(root, 'abc'), path.join(root, 'abcd')), 'Sibling prefix is not a false overlap');
  const previous = Object.fromEntries(['BROHN_HOSTED_PROFILE', 'BROHN_WORKSPACE', 'BROHN_PYTHON_METHODS', 'R_PROFILE', 'R_LIBS_SITE'].map(key => [key, process.env[key]]));
  try {
    for (const key of Object.keys(previous)) process.env[key] = 'Original sentinel that must not reach smoke children';
    const env = runtimeEnvironment(request, request.output);
    check(env.BROHN_WORKSPACE === path.join(request.output, 'workspace'), 'Actual configured workspace is replaced by isolated fresh workspace');
    check(env.BROHN_PUBLICATION_PYTHON === request.publication_python && env.BROHN_PUBLICATION_NATIVE_MANIFEST === request.publication_manifest, 'Native publication uses only explicit selected runtime paths');
    check(!env.BROHN_HOSTED_PROFILE && !env.BROHN_PYTHON_METHODS && !env.R_PROFILE && !env.R_LIBS_SITE, 'Inherited hosted/scientific/R startup overrides are removed');
    check(env.R_LIBS_USER === request.r_library && env.R_USER === path.join(request.output, 'r-user'), 'Explicit library and private R user directory reach children');
    check(Object.keys(previous).every(key => process.env[key].startsWith('Original sentinel')), 'Building child environment does not alter caller environment');
  } finally {for (const [key, value] of Object.entries(previous)) {if (value === undefined) delete process.env[key]; else process.env[key] = value;}}
  await fs.writeFile(path.join(request.project, 'package.json'), JSON.stringify({devDependencies: {'@playwright/test': '1.2.3', '@axe-core/playwright': '4.5.6'}}));
  await assert.rejects(pinnedTools(request), /ENOENT/); checks.push('Missing explicitly selected Node dependencies fail before browser launch');
  for (const [name, version] of Object.entries({'@playwright/test': '1.2.3', '@axe-core/playwright': '4.5.6'})) {
    const member = path.join(request.node_tools_root, 'node_modules', name); await fs.mkdir(member, {recursive: true});
    await fs.writeFile(path.join(member, 'package.json'), JSON.stringify({name, version, exports: {'.': './index.cjs'}}));
    await fs.writeFile(path.join(member, 'index.cjs'), 'module.exports = {default: function OriginalTestDouble(){}};');
  }
  check((await pinnedTools(request)).versions['@axe-core/playwright'] === '4.5.6', 'Exact package metadata can be checked when package.json is not exported');
  await fs.writeFile(path.join(request.project, 'package.json'), JSON.stringify({devDependencies: {'@playwright/test': '9.9.9', '@axe-core/playwright': '4.5.6'}}));
  await assert.rejects(pinnedTools(request), /pinned tools/); checks.push('Installed version mismatch refuses launch instead of silently using another version');
  console.log(JSON.stringify({status: 'passed', checks, scope: 'Path and runtime environment helper checks; no services or real research store'}));
} finally {
  // Native single-shell equivalent: delete only the exact mkdtemp-owned root.
  assert.ok(path.basename(root).startsWith('brohn-portable-smoke-check-') && path.dirname(root) === await fs.realpath(os.tmpdir()));
  await fs.rm(root, {recursive: true, force: true});
}
