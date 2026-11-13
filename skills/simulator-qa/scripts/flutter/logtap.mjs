// Attaches to an app someone ELSE launched (an IDE debug run) and mirrors its
// console into $QA_DIR/run.log in `flutter run`'s format ("flutter: <line>"),
// so step.sh and the QA[...] probes work the same as with launch.sh. Run it in
// the background; it runs until killed.
//
//   node logtap.mjs <vm-service-ws-uri>      # also writes $QA_DIR/ws.txt
//
// The URI is the "Dart VM Service" / "Debug service" address the IDE or
// `flutter run` prints, with http:// swapped for ws:// and /ws appended.
// Only output printed AFTER the tap starts is captured.
import { appendFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { QA_DIR } from './vmclient.mjs';

let wsUri = process.argv[2];
if (!wsUri) {
  console.error('usage: node logtap.mjs <vm-service-uri>');
  process.exit(2);
}
if (wsUri.startsWith('http')) wsUri = wsUri.replace(/^http/, 'ws').replace(/\/?$/, '/ws').replace(/\/ws\/ws$/, '/ws');
mkdirSync(QA_DIR, { recursive: true });
writeFileSync(join(QA_DIR, 'ws.txt'), wsUri + '\n');
const LOG = join(QA_DIR, 'run.log');
writeFileSync(LOG, `[logtap] attached to ${wsUri} at ${new Date().toISOString()}\n`);

let partial = '';
const ws = new WebSocket(wsUri);
let n = 1;
ws.onopen = () => {
  for (const streamId of ['Stdout', 'Stderr']) {
    ws.send(JSON.stringify({ jsonrpc: '2.0', id: String(n++), method: 'streamListen', params: { streamId } }));
  }
  console.log(`logtap: mirroring ${wsUri} → ${LOG}`);
};
ws.onmessage = (m) => {
  const msg = JSON.parse(m.data);
  if (msg.method !== 'streamNotify') return;
  const ev = msg.params?.event;
  if (!ev?.bytes) return;
  // Events are chunks, not lines: keep the unfinished tail for the next one.
  const text = partial + Buffer.from(ev.bytes, 'base64').toString('utf8');
  const lines = text.split('\n');
  partial = lines.pop() ?? '';
  // iOS already prefixes app output with "flutter: " on this stream.
  const tagged = lines.map((l) => (l.startsWith('flutter: ') ? l : 'flutter: ' + l));
  if (tagged.length) appendFileSync(LOG, tagged.join('\n') + '\n');
};
ws.onclose = () => {
  if (partial) appendFileSync(LOG, (partial.startsWith('flutter: ') ? '' : 'flutter: ') + partial + '\n');
  appendFileSync(LOG, '[logtap] VM service closed\n');
  console.log('logtap: VM service closed');
  process.exit(0);
};
ws.onerror = () => {
  console.log(`logtap: cannot reach ${wsUri}`);
  process.exit(1);
};
