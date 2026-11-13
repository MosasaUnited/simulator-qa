// The browser target. One long-lived process owns the browser and its page;
// every other call is a short client that sends it one command.
//
//   node web.mjs serve [url] [--browser chromium|firefox|webkit|chrome|msedge]
//                      [--device "iPhone 15"] [--locale ar-EG] [--viewport 1280x800] [--headed]
//   node web.mjs <command> [args…]      (the scripts call this; see `commands` below)
//
// A server rather than a reconnect per command, because in Firefox and WebKit
// a page does not outlive the client that opened it. It listens on 127.0.0.1
// only and asks for a random token, both written to $QA_DIR/web.json.
import { randomBytes } from 'node:crypto';
import { existsSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import http from 'node:http';
import { createRequire } from 'node:module';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';

const QA_DIR = (process.env.QA_DIR ?? join(process.env.TMPDIR ?? tmpdir(), 'simulator-qa')).replace(/\/+$/, '');
const QA_HOME = process.env.QA_HOME ?? join(homedir(), '.cache', 'simulator-qa');
const SESSION = join(QA_DIR, 'web.json');
const ENGINES = { chromium: 'chromium', firefox: 'firefox', webkit: 'webkit', chrome: 'chromium', msedge: 'chromium' };

// The project's own Playwright first, then the copy setup-web.sh installed.
function loadPlaywright() {
  for (const base of [process.cwd(), QA_HOME]) {
    for (const name of ['playwright', 'playwright-core']) {
      try {
        return createRequire(join(base, 'noop.js'))(name);
      } catch {
        // try the next place
      }
    }
  }
  return null;
}
const NEED_SETUP = 'Playwright is not installed — run setup-web.sh (next to this file), then use.sh web again.';

const [command, ...rest] = process.argv.slice(2);
if (!command) {
  console.error('usage: node web.mjs serve [url] [options] | <command> [args]');
  process.exit(2);
}

if (command === 'engines') {
  const pw = loadPlaywright();
  if (!pw) {
    console.log('  ' + NEED_SETUP);
    process.exit(0);
  }
  for (const name of ['chromium', 'firefox', 'webkit']) {
    console.log(`  ${existsSync(pw[name].executablePath()) ? 'ready    ' : 'missing  '}${name}`);
  }
  process.exit(0);
}

if (command !== 'serve') {
  // ── client ────────────────────────────────────────────────────────────
  if (!existsSync(SESSION)) {
    const logFile = join(QA_DIR, 'web.log');
    const ended = existsSync(logFile) && readFileSync(logFile, 'utf8').split('\n').filter((l) => l.startsWith('ENDED')).pop();
    console.error(`${ended ? ended.replace('ENDED', 'The browser session ended') : 'No browser session'} — start one with use.sh web [url].`);
    process.exit(1);
  }
  const { port, token } = JSON.parse(readFileSync(SESSION, 'utf8'));
  try {
    const res = await fetch(`http://127.0.0.1:${port}/`, {
      method: 'POST',
      headers: { 'x-qa-token': token, 'content-type': 'application/json' },
      body: JSON.stringify({ command, args: rest }),
    });
    const { ok, out } = await res.json();
    if (out) (ok ? console.log : console.error)(out);
    process.exit(ok ? 0 : 1);
  } catch {
    rmSync(SESSION, { force: true });
    console.error('The browser session has gone — start a new one with use.sh web [url].');
    process.exit(1);
  }
}

// ── server ──────────────────────────────────────────────────────────────
const pw = loadPlaywright();
if (!pw) {
  console.error(NEED_SETUP);
  process.exit(1);
}

const opts = { browser: 'chromium', device: null, locale: null, viewport: null, headed: false, scheme: null, url: null };
for (let i = 0; i < rest.length; i++) {
  const a = rest[i];
  if (a === '--headed') opts.headed = true;
  else if (a === '--browser') opts.browser = rest[++i];
  else if (a === '--device') opts.device = rest[++i];
  else if (a === '--locale') opts.locale = rest[++i];
  else if (a === '--viewport') opts.viewport = rest[++i];
  else if (!a.startsWith('--')) opts.url = a;
  else fail(`unknown option: ${a}`);
}
if (!ENGINES[opts.browser]) fail(`unknown browser: ${opts.browser} (chromium, firefox, webkit, chrome, msedge)`);
if (opts.device && !pw.devices[opts.device]) {
  const close = Object.keys(pw.devices).filter((d) => d.toLowerCase().includes(opts.device.toLowerCase().split(' ')[0]) && !d.includes('landscape'));
  fail(`unknown device preset: "${opts.device}". Similar: ${close.slice(0, 12).join(', ') || '(none — see playwright.dev/docs/emulation)'}`);
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

const engine = ENGINES[opts.browser];
let browser;
try {
  browser = await pw[engine].launch({
    headless: !opts.headed,
    channel: engine === opts.browser ? undefined : opts.browser,
  });
} catch (e) {
  fail(`Could not start ${opts.browser}: ${String(e.message).split('\n')[0]}\nIs the engine installed? setup-web.sh ${engine}`);
}

let context;
let page;
const logs = [];
const log = (line) => {
  logs.push(line.slice(0, 400));
  if (logs.length > 400) logs.shift();
};

function watch(p) {
  page = p;
  p.on('console', (m) => {
    // "Failed to load resource" does not say which one; the location does.
    const from = m.text().startsWith('Failed to load resource') ? ` — ${m.location().url}` : '';
    log(`${m.type()}: ${m.text()}${from}`);
  });
  p.on('pageerror', (e) => log(`uncaught: ${e.message}`));
  p.on('requestfailed', (r) => log(`request failed: ${r.method()} ${r.url()} (${r.failure()?.errorText})`));
  p.on('response', (r) => {
    if (r.status() >= 400) log(`http ${r.status()}: ${r.request().method()} ${r.url()}`);
  });
  p.on('close', () => {
    const open = context.pages();
    if (open.length) page = open[open.length - 1];
  });
}

// (Re)creates the context — a locale or device preset cannot change on a live
// one — keeping cookies and storage, and returning to the same address.
async function openContext(url) {
  const storageState = context ? await context.storageState() : undefined;
  if (context) await context.close();
  const preset = opts.device ? { ...pw.devices[opts.device] } : {};
  delete preset.defaultBrowserType;
  if (engine === 'firefox') delete preset.isMobile; // Firefox has no mobile mode
  if (opts.viewport) {
    const [width, height] = opts.viewport.split('x').map(Number);
    preset.viewport = { width, height };
  }
  context = await browser.newContext({
    ...preset,
    ...(opts.locale ? { locale: opts.locale } : {}),
    ...(opts.scheme ? { colorScheme: opts.scheme } : {}),
    storageState,
  });
  context.on('page', watch); // a link that opens a new tab moves the session to it
  await context.newPage();
  if (url && url !== 'about:blank') await page.goto(url, { waitUntil: 'load' });
}

// Screenshot pixels → layout pixels. They are the same except on a page with no
// viewport meta under a phone preset, which lays out wide and is shown shrunk.
const zoom = async () => (await page.evaluate(() => innerWidth).catch(() => 0)) / (page.viewportSize()?.width || 1) || 1;
const isTouch = () => Boolean(pw.devices[opts.device]?.hasTouch);

const where = async () => `${await page.title().catch(() => '')} — ${page.url()}`;
const settle = () => page.waitForLoadState('load', { timeout: 5000 }).catch(() => {});

// Runs in the page: what is under a point, for the line a tap prints.
const describeAt = ([x, y]) => {
  const e = document.elementFromPoint(x, y);
  if (!e) return 'nothing (outside the viewport?)';
  if (e.tagName === 'SELECT') return '<select> — its dropdown is drawn by the system and is in no screenshot: use `web.mjs select` (references/web.md)';
  const text = (e.getAttribute('aria-label') || e.innerText || e.labels?.[0]?.innerText || e.placeholder || e.alt || '').trim().replace(/\s+/g, ' ');
  return `<${e.tagName.toLowerCase()}>${text ? ` "${text.slice(0, 50)}"` : ''}`;
};

// Runs in the page: the visible elements with a role or a label, one per line.
const listUi = (k) => {
  const roles = { a: 'link', button: 'button', select: 'select', textarea: 'textbox', img: 'image', summary: 'button' };
  const lines = [];
  const selector = 'a[href],button,input,select,textarea,summary,img[alt],[role],[onclick],[tabindex],h1,h2,h3,h4,[aria-label],[contenteditable=""],[contenteditable="true"]';
  for (const e of document.querySelectorAll(selector)) {
    const r = e.getBoundingClientRect();
    const tag = e.tagName.toLowerCase();
    let [cx, cy] = [r.left + r.width / 2, r.top + r.height / 2];
    if (/^h[1-6]$/.test(tag) || tag === 'a') {
      // A block is as wide as its container; aim at the words themselves.
      const range = document.createRange();
      range.selectNodeContents(e);
      const t = range.getClientRects()[0];
      if (t && t.width > 0) [cx, cy] = [t.left + t.width / 2, t.top + t.height / 2];
    }
    // In view means its centre is: that is the point a tap would use.
    if (r.width < 1 || r.height < 1 || cx < 0 || cy < 0 || cx > innerWidth || cy > innerHeight) continue;
    const s = getComputedStyle(e);
    if (s.visibility === 'hidden' || s.display === 'none' || Number(s.opacity) === 0) continue;
    if (tag === 'input' && e.type === 'hidden') continue;
    const role = e.getAttribute('role') || (tag === 'input' ? e.type : roles[tag]) || tag;
    const field = tag === 'input' || tag === 'select' || tag === 'textarea';
    const toggle = e.type === 'checkbox' || e.type === 'radio';
    const label = e.labels?.[0];
    // The label's own words, without the text of a control nested inside it.
    const labelText = label && ([...label.childNodes].filter((n) => n.nodeType === 3).map((n) => n.textContent).join(' ').trim() || label.innerText);
    const own = field ? labelText || e.placeholder : e.innerText || e.alt;
    const name = (e.getAttribute('aria-label') || own || e.title || '').trim().replace(/\s+/g, ' ').slice(0, 70);
    if (!name && !field && !e.id) continue;
    let line = `${Math.round(cx / k)},${Math.round(cy / k)}  ${role}`;
    if (name) line += `  "${name}"`;
    if (field && e.value && !toggle && e.type !== 'password') line += `  = ${String(e.value).slice(0, 50)}`;
    if (tag === 'select') line += `  options: ${[...e.options].map((o) => o.label).join(' | ').slice(0, 120)}`;
    if (e.id) line += `  #${e.id}`;
    if (e.disabled) line += '  disabled';
    if (e.checked) line += '  checked';
    if (document.activeElement === e) line += '  focused';
    lines.push(line);
  }
  return lines.join('\n');
};

const KEYS = { enter: 'Enter', tab: 'Tab', delete: 'Backspace', escape: 'Escape', up: 'ArrowUp', down: 'ArrowDown', left: 'ArrowLeft', right: 'ArrowRight' };

const commands = {
  async info() {
    const v = page.viewportSize();
    return `${opts.browser}${opts.device ? ` as ${opts.device}` : ''} ${v?.width}x${v?.height}${opts.locale ? ` ${opts.locale}` : ''} — ${page.url()}`;
  },
  async goto(url) {
    const target = /^[a-z][a-z0-9+.-]*:/i.test(url) ? url : `http://${url}`;
    const response = await page.goto(target, { waitUntil: 'load' });
    return `${response ? `http ${response.status()} ` : ''}${await where()}`;
  },
  async shot(path, flag) {
    await page.screenshot({ path, scale: 'css', fullPage: flag === '--full' });
    const v = page.viewportSize();
    return flag === '--full' ? 'whole page captured — look, do not read tap coordinates off it' : '';
  },
  async tap(x, y, flag) {
    const shown = `${x},${y}`;
    const k = await zoom();
    [x, y] = [Number(x) * k, Number(y) * k];
    const target = await page.evaluate(describeAt, [x, y]).catch(() => '?');
    let how = '';
    if (flag === '--long' && isTouch() && engine === 'chromium') {
      // Playwright's touchscreen can only tap; hold a real touch point instead.
      const cdp = await context.newCDPSession(page);
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y }] });
      await page.waitForTimeout(1000);
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
      await cdp.detach();
    } else if (flag === '--long') {
      await page.mouse.move(x, y);
      await page.mouse.down();
      await page.waitForTimeout(1000);
      await page.mouse.up();
      if (isTouch()) how = ' (with the mouse: this engine cannot hold a touch)';
    } else if (isTouch()) {
      await page.touchscreen.tap(x, y);
    } else {
      await page.mouse.click(x, y);
    }
    await page.waitForTimeout(150);
    await settle();
    return `${flag === '--long' ? 'long-pressed' : 'tapped'} ${shown}${how} → ${target}`;
  },
  async swipe(x1, y1, x2, y2, ms, flag) {
    const k = await zoom();
    [x1, y1, x2, y2] = [x1, y1, x2, y2].map((v) => Number(v) * k);
    if (flag === '--drag') {
      await page.mouse.move(x1, y1);
      await page.mouse.down();
      await page.mouse.move(x2, y2, { steps: 12 });
      await page.mouse.up();
      return `dragged ${x1},${y1} → ${x2},${y2}`;
    }
    const [dx, dy] = [x1 - x2, y1 - y2];
    try {
      await page.mouse.move(x1, y1);
      await page.mouse.wheel(dx, dy);
    } catch {
      // Mobile WebKit has no wheel: scroll whatever scrolls under the point.
      await page.evaluate(([x, y, dx, dy]) => {
        let e = document.elementFromPoint(x, y);
        while (e && e !== document.documentElement) {
          const s = getComputedStyle(e);
          if (/(auto|scroll)/.test(s.overflowY + s.overflowX) && (e.scrollHeight > e.clientHeight || e.scrollWidth > e.clientWidth)) break;
          e = e.parentElement;
        }
        (e && e !== document.documentElement ? e : window).scrollBy(dx, dy);
      }, [x1, y1, dx, dy]);
    }
    await page.waitForTimeout(250);
    const at = await page.evaluate(() => `${Math.round(scrollY)}/${Math.max(0, document.documentElement.scrollHeight - innerHeight)}`);
    return `scrolled by ${dx},${dy} — page at ${at}`;
  },
  async type(text) {
    await page.keyboard.type(text);
    const into = await page.evaluate(() => {
      const e = document.activeElement;
      return e && e !== document.body ? `<${e.tagName.toLowerCase()}${e.id ? ` #${e.id}` : ''}>` : null;
    });
    return into ? `typed ${text.length} characters into ${into}` : `typed ${text.length} characters, but NOTHING has focus — tap a field first`;
  },
  async key(name) {
    if (name === 'back') await page.goBack();
    else if (name === 'forward') await page.goForward();
    else if (name === 'reload') await page.reload();
    else await page.keyboard.press(KEYS[name] ?? name);
    await settle();
    return `pressed ${name} — ${await where()}`;
  },
  async ui() {
    return (await page.evaluate(listUi, await zoom())) || '(nothing with a role or a label in view — rely on the screenshot)';
  },
  async logs(arg) {
    if (arg === '--clear') {
      logs.length = 0;
      return 'cleared';
    }
    const all = logs.splice(0);
    const out = (Number(arg) > 0 ? all.slice(-Number(arg)) : all).join('\n');
    return out || '(no console output, errors or failed requests since the last read)';
  },
  async appearance(mode) {
    opts.scheme = mode;
    for (const p of context.pages()) await p.emulateMedia({ colorScheme: mode });
    return `prefers-color-scheme: ${mode}`;
  },
  async locale(tag) {
    opts.locale = tag === 'reset' ? null : tag;
    await openContext(page.url());
    return `locale: ${opts.locale ?? 'browser default'} — page reloaded (login kept, anything typed is gone) — ${await where()}`;
  },
  async device(name) {
    if (name !== 'reset' && !pw.devices[name]) throw new Error(`unknown device preset: ${name}`);
    opts.device = name === 'reset' ? null : name;
    await openContext(page.url());
    return `${await commands.info()} — page reloaded (login kept, anything typed is gone)`;
  },
  async viewport(width, height) {
    await page.setViewportSize({ width: Number(width), height: Number(height) });
    return `viewport ${width}x${height}`;
  },
  // A native dropdown opens outside the page and is in no screenshot.
  async select(selector, option) {
    const chosen = await page.selectOption(selector, { label: option }, { timeout: 3000 });
    return `selected ${chosen.join(', ')} in ${selector}`;
  },
  async eval(source) {
    const value = await page.evaluate(source);
    return typeof value === 'string' ? value : JSON.stringify(value, null, 1);
  },
  async stop() {
    setTimeout(() => shutdown('stopped by stop.sh'), 50);
    return 'browser closed';
  },
};

async function shutdown(reason) {
  // The client reads the last ENDED line to say why there is no session.
  console.log(`ENDED at ${new Date().toTimeString().slice(0, 8)}: ${typeof reason === 'string' ? reason : 'stopped'}`);
  rmSync(SESSION, { force: true });
  await browser.close().catch(() => {});
  process.exit(0);
}

await openContext(opts.url);
const token = randomBytes(16).toString('hex');
let queue = Promise.resolve();
const server = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    const reply = (ok, out) => res.end(JSON.stringify({ ok, out: String(out) }));
    if (req.headers['x-qa-token'] !== token) return reply(false, 'wrong token');
    let message;
    try {
      message = JSON.parse(body);
    } catch {
      return reply(false, 'bad request');
    }
    const run = commands[message.command];
    if (!run) return reply(false, `unknown command: ${message.command} (${Object.keys(commands).join(', ')})`);
    // One command at a time, in arrival order.
    queue = queue.then(() =>
      run(...(message.args ?? [])).then(
        (out) => reply(true, out),
        (e) => reply(false, `FAILED: ${String(e.message).split('\n')[0]}`),
      ),
    );
  });
});
server.listen(0, '127.0.0.1', () => {
  writeFileSync(SESSION, JSON.stringify({ port: server.address().port, token, pid: process.pid }), { mode: 0o600 });
  console.log(`serving ${opts.browser} on 127.0.0.1:${server.address().port}`);
});
browser.on('disconnected', () =>
  shutdown(
    opts.browser === 'chrome' && !opts.headed
      ? 'Chrome closed itself. An installed Chrome can quit after ~30 s when run hidden: add --headed, or use --browser chromium'
      : `${opts.browser} closed or crashed`,
  ),
);
process.on('SIGTERM', () => shutdown('killed'));
process.on('SIGINT', () => shutdown('killed'));
