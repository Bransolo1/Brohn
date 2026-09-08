import { spawn } from 'node:child_process';
import { existsSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const work = path.resolve(root, '../../work');
const localR = path.join(work, 'native-r/bin/Rscript.exe');
const executable = process.env.RESEARCH_RSCRIPT || (existsSync(localR) ? localR : 'Rscript');
const storage = path.join(root, 'data/browser-tests', `${Date.now()}-${process.pid}`);
mkdirSync(storage, { recursive: true });
const env = { ...process.env, LC_ALL: 'C', RESEARCH_PLATFORM_PORT: '3849', RESEARCH_PLATFORM_DATA: storage };
if (executable === localR) {
  env.R_LIBS_USER = path.join(work, 'r-library');
  env.R_USER = work;
}
const child = spawn(executable, ['--vanilla', 'scripts/run-local.R'], {
  cwd: root, env, stdio: 'inherit', windowsHide: true
});
child.on('error', error => { console.error(error.message); process.exitCode = 1; });
child.on('exit', code => { process.exitCode = code ?? 1; });
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => child.kill());
process.on('exit', () => child.kill());
