// Makes the fields of config/devKey for a new developer key (จัดการผู้ใช้และสิทธิ์), to paste in the Firebase console.
// `node make-dev-key.mjs <you@email>` asks for the 6 digits without echoing them; only the PBKDF2-SHA256 hash and its
// salt are printed. Give the digits to the Maintainers in person; the app never stores them. The key expires in 30 days.
import { pbkdf2Sync, randomBytes } from 'node:crypto';
import { createInterface } from 'node:readline';

const setBy = (process.argv[2] || '').trim().toLowerCase();
if (!setBy.includes('@')) { console.error('usage: node make-dev-key.mjs <maintainer email>'); process.exit(1); }

const rl = createInterface({ input: process.stdin, output: process.stdout });
rl._writeToOutput = (s) => { if (s.includes('คีย์')) rl.output.write(s); };
rl.question('คีย์ 6 หลัก: ', (digits) => {
  rl.close();
  process.stdout.write('\n');
  if (!/^\d{6}$/.test(digits)) { console.error('ต้องเป็นตัวเลข 6 หลัก'); process.exit(1); }
  const iterations = 310000, salt = randomBytes(16);
  const hash = pbkdf2Sync(digits, salt, iterations, 32, 'sha256');
  const now = new Date(), expires = new Date(now.getTime() + 30 * 86400e3);
  console.log(JSON.stringify({
    hash: hash.toString('base64'), salt: salt.toString('base64'), iterations,
    expiresAt: expires.toISOString() + ' (timestamp)', setBy, setAt: now.toISOString() + ' (timestamp)',
  }, null, 2));
  console.log('Firestore → config/devKey: hash, salt (string) · iterations (number) · expiresAt, setAt (timestamp) · setBy (string)');
});
