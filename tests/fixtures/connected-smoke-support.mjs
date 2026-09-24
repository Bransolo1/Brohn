// Pure/preflight helpers shared by the portable smoke and its focused tests.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';

export const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
export function overlaps(a, b) {
  const key = x => path.resolve(x).replaceAll('\\', '/').replace(/\/$/, '').toLowerCase();
  a = key(a); b = key(b);
  return a === b || a.startsWith(b + '/') || b.startsWith(a + '/');
}
export async function resolvedFuturePath(file) {
  let current = path.resolve(file); const missing = [];
  for (;;) {
    try {return path.join(await fs.realpath(current), ...missing.reverse());}
    catch (error) {if (error.code !== 'ENOENT') throw error;}
    const parent = path.dirname(current); assert.notEqual(parent, current, 'Cannot resolve path ancestry');
    missing.push(path.basename(current)); current = parent;
  }
}
export async function validateDestination(request) {
  const output = await resolvedFuturePath(request.output);
  const protectedPaths = [request.project, request.forbidden_workspace, request.node_tools_root,
    request.r_library, request.rscript, request.publication_python, request.publication_manifest,
    request.portability_python, request.configuration_path, request.browser_executable];
  for (const protectedPath of protectedPaths) assert.ok(!overlaps(output, await resolvedFuturePath(protectedPath)),
    'Choose fresh evidence outside the checkout, configured workspace and runtime/configuration paths');
  await assert.rejects(fs.lstat(output), {code: 'ENOENT'}, 'Evidence directory must not already exist');
  assert.ok((await fs.stat(path.dirname(output))).isDirectory(), 'Evidence parent directory must exist');
  return output;
}
export function runtimeEnvironment(request, folder) {
  // No inherited Brohn workspace, hosted credentials, scientific profile or
  // R startup configuration may silently redirect this isolated core run.
  const env = {...process.env};
  for (const name of Object.keys(env)) if (/^(BROHN_|R_LIBS|R_PROFILE|R_ENVIRON|R_USER$|R_HOME$|RESEARCH_PLATFORM_PORT$)/i.test(name)) delete env[name];
  return {...env, LC_ALL: 'C', LANG: 'C', R_LIBS_USER: request.r_library,
    R_USER: path.join(folder, 'r-user'), BROHN_APP_MODE: 'platform',
    BROHN_WORKSPACE: path.join(folder, 'workspace'),
    BROHN_PUBLICATION_PYTHON: request.publication_python,
    BROHN_PUBLICATION_NATIVE_MANIFEST: request.publication_manifest,
    BROHN_PYTHON: request.portability_python};
}
export async function pinnedTools(request) {
  assert.ok(Number(process.versions.node.split('.')[0]) >= 22, 'Use Node 22 or newer; this profile was exercised with Node 24');
  const manifest = JSON.parse(await fs.readFile(path.join(request.project, 'package.json'), 'utf8'));
  const modules = await fs.realpath(path.join(request.node_tools_root, 'node_modules'));
  const require = createRequire(pathToFileURL(path.join(request.node_tools_root, 'package.json')));
  const versions = {};
  for (const name of ['@playwright/test', '@axe-core/playwright']) {
    // Some supported packages intentionally do not export package.json. Inspect
    // the selected installation's manifest, then bind it to the resolved entry.
    const packageFile = await fs.realpath(path.join(modules, name, 'package.json'));
    assert.ok(packageFile.startsWith(modules + path.sep), 'Pinned tools must resolve inside the explicitly selected node_modules');
    const entry = await fs.realpath(require.resolve(name));
    assert.ok(entry.startsWith(path.dirname(packageFile) + path.sep), 'Resolved Node tool entry must belong to the verified package');
    const installed = JSON.parse(await fs.readFile(packageFile, 'utf8'));
    assert.equal(installed.version, manifest.devDependencies[name], `${name}: install the checkout's pinned tools with pnpm install --frozen-lockfile`);
    versions[name] = installed.version;
  }
  assert.ok((await fs.stat(request.browser_executable)).isFile(), 'Supply an installed Chromium browser executable; this test downloads nothing');
  return {playwright: require('@playwright/test'), AxeBuilder: require('@axe-core/playwright').default,
    versions, browser_sha256: sha256(await fs.readFile(request.browser_executable))};
}
export async function sourceHashes(project) {
  const files = ['app.R', 'renv.lock', 'package.json', 'pnpm-lock.yaml', 'tests/connected-smoke.mjs',
    'tests/fixtures/connected-smoke.R', 'tests/fixtures/connected-smoke-support.mjs'];
  const walk = async relative => {
    for (const entry of await fs.readdir(path.join(project, relative), {withFileTypes: true})) {
      const member = path.join(relative, entry.name);
      if (entry.isDirectory()) {if (entry.name !== '__pycache__') await walk(member);}
      else if (entry.isFile() && !/\.(pyc|pyo)$/.test(entry.name)) files.push(member);
    }
  };
  for (const directory of ['R', 'src', 'scripts', 'www']) await walk(directory);
  return Object.fromEntries(await Promise.all([...new Set(files)].sort().map(async file =>
    [file.replaceAll('\\', '/'), sha256(await fs.readFile(path.join(project, file)))])));
}
