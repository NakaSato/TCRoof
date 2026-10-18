// Sets the developer key of จัดการผู้ใช้และสิทธิ์ (config/devKey): a PBKDF2-SHA256 hash and its salt, never the digits.
//
//   node tools/dev-key/make-dev-key.mjs <maintainer email>           prints the fields, to add in the Firebase console
//   node tools/dev-key/make-dev-key.mjs <maintainer email> --write   writes config/devKey (and an auditLog entry)
//
// Run it in your own terminal: it asks for the 6 digits twice without echoing them. `--write` uses the Firebase CLI's
// login (`firebase login`, a Maintainer's Google account) on the project of .firebaserc, or `--project <id>`. Give the
// digits to the other Maintainers in person; the app never stores them. The key expires in 30 days.
import { pbkdf2Sync, randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { createInterface } from 'node:readline';

const args = process.argv.slice(2);
const setBy = (args.find((a) => a.includes('@')) || '').trim().toLowerCase();
const write = args.includes('--write');
const projectArg = args.includes('--project') ? args[args.indexOf('--project') + 1] : undefined;
if (!setBy) {
  console.error('usage: node make-dev-key.mjs <maintainer email> [--write] [--project <id>]');
  process.exit(1);
}

let piped;
/** Asks without echoing what is typed: raw keys on a terminal, else the next line of the piped input. */
async function askHidden(prompt) {
  process.stdout.write(prompt);
  if (!process.stdin.isTTY) {
    piped ??= createInterface({ input: process.stdin })[Symbol.asyncIterator]();
    const { value } = await piped.next();
    process.stdout.write('\n');
    return (value || '').trim();
  }
  return new Promise((resolve) => {
    let typed = '';
    process.stdin.setRawMode(true);
    process.stdin.resume();
    const onData = (buf) => {
      for (const ch of buf.toString('utf8')) {
        if (ch === '\u0003') { process.stdout.write('\n'); process.exit(130); }   // Ctrl-C
        if (ch === '\r' || ch === '\n') {
          process.stdin.off('data', onData);
          process.stdin.setRawMode(false);
          process.stdin.pause();
          process.stdout.write('\n');
          return resolve(typed);
        }
        if (ch === '\u007f' || ch === '\b') typed = typed.slice(0, -1);
        else typed += ch;
      }
    };
    process.stdin.on('data', onData);
  });
}

function project() {
  if (projectArg && !projectArg.startsWith('--')) return projectArg;
  const rc = JSON.parse(readFileSync(new URL('../../.firebaserc', import.meta.url), 'utf8'));
  return rc.projects.default;
}

/** An access token from the Firebase CLI's login (its public OAuth client). */
async function token() {
  const store = JSON.parse(readFileSync(`${homedir()}/.config/configstore/firebase-tools.json`, 'utf8'));
  const refresh = store.tokens?.refresh_token;
  if (!refresh) throw new Error('Firebase CLI is not signed in: run `firebase login` first');
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'refresh_token', refresh_token: refresh,
      client_id: '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com',
      client_secret: 'j9iVZfS8kkCEFUPaAeJV0sAi',
    }),
  });
  const t = (await r.json()).access_token;
  if (!t) throw new Error('could not get a token from the Firebase CLI login: run `firebase login --reauth`');
  return t;
}

async function firestore(method, path, fields, t) {
  const url = `https://firestore.googleapis.com/v1/projects/${project()}/databases/(default)/documents/${path}`;
  const r = await fetch(url, { method, headers: { authorization: `Bearer ${t}`, 'content-type': 'application/json' },
    body: JSON.stringify({ fields }) });
  const body = await r.json();
  if (!r.ok) throw new Error(`${path}: ${body.error?.message || r.status}`);
  return body;
}

const digits = await askHidden('คีย์ 6 หลัก: ');
if (!/^\d{6}$/.test(digits)) { console.error('ต้องเป็นตัวเลข 6 หลัก'); process.exit(1); }
if ((await askHidden('ใส่คีย์อีกครั้ง: ')) !== digits) { console.error('คีย์สองครั้งไม่ตรงกัน'); process.exit(1); }

const iterations = 310000, salt = randomBytes(16);
const hash = pbkdf2Sync(digits, salt, iterations, 32, 'sha256');
const now = new Date(), expires = new Date(now.getTime() + 30 * 86400e3);

if (!write) {
  console.log(JSON.stringify({
    hash: hash.toString('base64'), salt: salt.toString('base64'), iterations,
    expiresAt: expires.toISOString() + ' (timestamp)', setBy, setAt: now.toISOString() + ' (timestamp)',
  }, null, 2));
  console.log('Firestore → config/devKey: hash, salt (string) · iterations (number) · expiresAt, setAt (timestamp) · setBy (string)');
  process.exit(0);
}

const t = await token();
await firestore('PATCH', 'config/devKey', {
  hash: { stringValue: hash.toString('base64') },
  salt: { stringValue: salt.toString('base64') },
  iterations: { integerValue: String(iterations) },
  expiresAt: { timestampValue: expires.toISOString() },
  setBy: { stringValue: setBy },
  setAt: { timestampValue: now.toISOString() },
}, t);
const day = (d) => `${d.getDate()}/${d.getMonth() + 1}/${d.getFullYear() + 543}`;
await firestore('POST', 'auditLog', {
  at: { timestampValue: now.toISOString() },
  by: { stringValue: setBy },
  kind: { stringValue: 'key' },
  title: { stringValue: 'เปลี่ยนคีย์นักพัฒนา' },
  detail: { stringValue: `หมดอายุ ${day(expires)} · tools/dev-key` },
}, t);
console.log(`✓ config/devKey ตั้งแล้วใน ${project()} · หมดอายุ ${day(expires)} · บันทึกใน auditLog`);
