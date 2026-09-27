import fs from 'node:fs/promises';
import path from 'node:path';
import net from 'node:net';
import {spawn} from 'node:child_process';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';

const [rscriptArg, outArg, sourceArg, dependenciesArg] = process.argv.slice(2);
assert(dependenciesArg, 'Arguments: Rscript output-directory module.R package.json-with-Playwright');
const out = path.resolve(outArg), source = path.resolve(sourceArg);
await fs.mkdir(out);
const require = createRequire(path.resolve(dependenciesArg));
const {chromium} = require('@playwright/test');
const listener = net.createServer();
await new Promise((resolve, reject) => {listener.once('error', reject); listener.listen(0, '127.0.0.1', resolve);});
const port = listener.address().port;
await new Promise(resolve => listener.close(resolve));
const child = spawn(path.resolve(rscriptArg), [path.join(path.dirname(fileURLToPath(import.meta.url)), 'http-response-wire.R'), out, String(port), source], {windowsHide: true, env: process.env});
let log = '', browser;
child.stdout.on('data', d => log += d); child.stderr.on('data', d => log += d);
const checks = [];
function check(label, ok) {assert(ok, label); checks.push(label);}
const sha = b => createHash('sha256').update(b).digest('hex');
function header(block) {
  const lines = block.toString('latin1').split('\r\n');
  const status = Number(/^HTTP\/1\.1 (\d{3})/.exec(lines.shift())?.[1]);
  const fields = {};
  for (const line of lines) {
    const split = line.indexOf(':'); assert(split > 0, 'valid header syntax');
    const key = line.slice(0, split).toLowerCase(); assert(!(key in fields), 'no duplicate header: ' + key);
    fields[key] = line.slice(split + 1).trim();
  }
  return {status, fields};
}
async function exchange(url, encoding) {
  const u = new URL(url), chunks = []; let failure = null;
  await new Promise(resolve => {
    let secondSent = false;
    const socket = net.connect({host: '127.0.0.1', port}, () => socket.write(`HEAD ${u.pathname + u.search} HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\nAccept-Encoding: ${encoding}\r\nConnection: keep-alive\r\n\r\n`));
    socket.setTimeout(5000, () => {failure = 'timeout'; socket.destroy();});
    socket.on('data', d => {
      chunks.push(d);
      if (!secondSent && Buffer.concat(chunks).includes('\r\n\r\n')) {
        secondSent = true;
        setImmediate(() => socket.write(`GET ${u.pathname + u.search} HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\nAccept-Encoding: ${encoding}\r\nConnection: close\r\n\r\n`));
      }
    });
    socket.on('error', e => failure = e.message); socket.on('close', resolve);
  });
  assert.equal(failure, null, 'sequential connection must finish');
  return Buffer.concat(chunks);
}
try {
  for (let i = 0; i < 150 && !log.includes('Listening on'); i++) {
    if (child.exitCode !== null) throw Error(log);
    await new Promise(r => setTimeout(r, 100));
  }
  assert(log.includes('Listening on'), 'owned synthetic loopback server started');
  const fixtureDoc = JSON.parse(await fs.readFile(path.join(out, 'fixtures.json'), 'utf8'));
  browser = await chromium.launch({channel: 'chrome', headless: true});
  const page = await browser.newPage(); await page.goto(`http://127.0.0.1:${port}`);
  await page.locator('#refused_404').waitFor();
  for (const fixture of fixtureDoc.fixtures) {
    const expected = await fs.readFile(path.join(out, fixture.file));
    assert.equal(sha(expected), fixture.sha256);
    const url = new URL(await page.locator('#' + fixture.name).getAttribute('href'), page.url()).href;
    for (const encoding of ['identity', 'gzip']) {
      const label = fixture.name + ' ' + encoding;
      const head = await page.request.head(url, {headers: {'Accept-Encoding': encoding}});
      check(label + ' client HEAD status/empty/exact decimal length', head.status() === fixture.status && (await head.body()).length === 0 && head.headers()['content-length'] === String(expected.length));
      const get = await page.request.get(url, {headers: {'Accept-Encoding': encoding}});
      check(label + ' client GET exact complete representation', get.status() === fixture.status && (await get.body()).equals(expected));
      const raw = await exchange(url, encoding); await fs.writeFile(path.join(out, label.replace(' ', '-') + '-wire.bin'), raw);
      const end = raw.indexOf('\r\n\r\n'); assert(end > 0);
      const first = header(raw.subarray(0, end)), rest = raw.subarray(end + 4);
      check(label + ' raw HEAD contains zero bytes before next response', rest.subarray(0, 9).toString('latin1') === 'HTTP/1.1 ');
      const secondEnd = rest.indexOf('\r\n\r\n'); assert(secondEnd > 0);
      const second = header(rest.subarray(0, secondEnd)), body = rest.subarray(secondEnd + 4);
      for (const [kind, h] of [['HEAD', first], ['GET', second]]) {
        check(label + ' raw ' + kind + ' metadata and identity framing', h.status === fixture.status && h.fields['content-length'] === String(expected.length) && h.fields['content-encoding'] === 'identity' && !('transfer-encoding' in h.fields) && h.fields['content-type'] === fixture.type && h.fields['cache-control'] === 'no-store' && h.fields['x-content-type-options'] === 'nosniff' && h.fields['x-saved-ref'] === fixture.name && h.fields['content-disposition'] === `attachment; filename="${fixture.name}.bin"`);
      }
      check(label + ' raw subsequent GET exact bytes', body.equals(expected));
    }
    check(fixture.name + ' retained synthetic source remains unchanged', sha(await fs.readFile(path.join(out, fixture.file))) === fixture.sha256);
  }
  const receipt = {schema: 'brohn-http-response-wire/0.1', passed: true, checks, source_sha256: sha(await fs.readFile(source)), encoding: fixtureDoc.encoding, runtime: {...fixtureDoc.runtime, node: process.version, chrome: await browser.version()}, scope: 'Actual installed Shiny/httpuv with private module loading, ten synthetic representations, two encoding negotiations, and raw sequential persistent HEAD-to-GET connections. No integrated Brohn callback, authentication, native lease, or production workspace claims.'};
  await fs.writeFile(path.join(out, 'results.json'), JSON.stringify(receipt, null, 2));
  console.log(JSON.stringify({passed: true, checks: checks.length, source_sha256: receipt.source_sha256}));
} catch (error) {
  await fs.writeFile(path.join(out, 'failure.json'), JSON.stringify({error: String(error), checks}, null, 2)); throw error;
} finally {
  if (browser) await browser.close();
  child.kill();
  if (child.exitCode === null) await new Promise(resolve => child.once('exit', resolve));
  await fs.writeFile(path.join(out, 'server.log'), log);
  const connection = await new Promise(resolve => {
    const socket = net.connect({host: '127.0.0.1', port});
    socket.setTimeout(1000, () => {socket.destroy(); resolve('timeout');});
    socket.once('connect', () => {socket.destroy(); resolve('unexpected-listener');});
    socket.once('error', e => resolve(e.code));
  });
  const cleanup = {schema: 'brohn-http-response-wire-cleanup/0.1', child_pid: child.pid, exit_code: child.exitCode, signal_code: child.signalCode, bound_host: '127.0.0.1', port, after_child_exit_connect_result: connection, owned_listener_closed: connection === 'ECONNREFUSED'};
  await fs.writeFile(path.join(out, 'cleanup.json'), JSON.stringify(cleanup, null, 2));
  assert(cleanup.owned_listener_closed, 'owned synthetic loopback listener must be closed');
}
