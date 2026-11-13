// The Dart VM-service plumbing shared by vm.mjs, tap.mjs and scroll.mjs.
import { existsSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';

// Walks up from the current directory to the nearest file with that name.
function findUp(name) {
  let dir = process.cwd();
  for (;;) {
    if (existsSync(join(dir, name))) return join(dir, name);
    const parent = dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

// A QA_* setting: the environment first, then the project's .simulator-qa.env.
export function setting(name) {
  if (process.env[name]) return process.env[name];
  const file = findUp('.simulator-qa.env');
  if (!file) return undefined;
  for (const line of readFileSync(file, 'utf8').split('\n')) {
    if (line.startsWith(name + '=')) return line.slice(name.length + 1).trim().replace(/^"|"$/g, '');
  }
  return undefined;
}

export const QA_DIR = (process.env.QA_DIR ?? join(process.env.TMPDIR ?? tmpdir(), 'simulator-qa')).replace(/\/+$/, '');

// The library expressions are compiled in when no object is targeted. It has
// to import Flutter's widgets (Element, WidgetsBinding); main.dart always does.
export function rootLibrary() {
  const set = setting('QA_FLUTTER_ROOT_LIB');
  if (set) return set;
  const pubspec = findUp('pubspec.yaml');
  const name = pubspec && /^name:\s*(\S+)/m.exec(readFileSync(pubspec, 'utf8'))?.[1];
  if (!name) throw new Error('no pubspec.yaml here — run from the Flutter project, or set QA_FLUTTER_ROOT_LIB');
  return `package:${name}/main.dart`;
}

// Whole-line `//` comments are dropped; each line loses its indentation and the
// lines are joined with a space — the VM's expression compiler reads one line.
export const flat = (src) =>
  src
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('//'))
    .join(' ');

export function explain(e) {
  const details = e?.data?.details;
  if (details) {
    return 'COMPILE ERROR: ' + details.split('\n')[0].replace(/^org-dartlang-debug:synthetic_debug_expression:\d+:\d+: /, '');
  }
  return 'FAILED: ' + (e?.message ?? JSON.stringify(e)).slice(0, 1500);
}

// Connects, runs fn({ call, isolateId, libId, evaluate }), closes. The URI
// comes from $VM_WS, else $QA_DIR/ws.txt (written by wait_ready.sh / logtap).
export function withVm(fn) {
  let wsUri = process.env.VM_WS;
  if (!wsUri) {
    const file = join(QA_DIR, 'ws.txt');
    if (!existsSync(file)) {
      console.log('FAILED: no running Flutter app recorded — start one with flutter/launch.sh.');
      process.exit(1);
    }
    wsUri = readFileSync(file, 'utf8').trim();
  }
  const ws = new WebSocket(wsUri);
  let nextId = 1;
  const pending = new Map();
  ws.onmessage = (m) => {
    const msg = JSON.parse(m.data);
    const p = pending.get(msg.id);
    if (p) {
      pending.delete(msg.id);
      msg.error ? p.reject(msg.error) : p.resolve(msg.result);
    }
  };
  const call = (method, params = {}) =>
    new Promise((resolve, reject) => {
      const id = String(nextId++);
      pending.set(id, { resolve, reject });
      ws.send(JSON.stringify({ jsonrpc: '2.0', id, method, params }));
    });
  ws.onerror = () => {
    console.log(`FAILED: cannot reach the VM service at ${wsUri} — is the app still running? (flutter/wait_ready.sh)`);
    process.exit(1);
  };
  ws.onopen = async () => {
    try {
      const vm = await call('getVM');
      const isolateId = (vm.isolates.find((i) => i.name === 'main') ?? vm.isolates[0]).id;
      const iso = await call('getIsolate', { isolateId });
      const libId = (uri) => {
        const lib = iso.libraries.find((l) => l.uri === uri);
        if (!lib) throw new Error(`library not loaded: ${uri} — set QA_FLUTTER_ROOT_LIB to one the app imports`);
        return lib.id;
      };
      const evaluate = (targetId, expression) =>
        call('evaluate', { isolateId, targetId, expression, disableBreakpoints: true });
      await fn({ call, isolateId, libId, evaluate });
    } catch (e) {
      console.log(explain(e));
    } finally {
      ws.close();
    }
  };
}
