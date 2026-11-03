// Adds or updates a user in Firestore `members/<email>` with a role (manager, internal, external).
//
// Usage:
//   node tools/add-member.mjs <email> [role]
// Example:
//   node tools/add-member.mjs enwuft@gmail.com external
//
// Requires `firebase login` in your terminal first.

import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';

const args = process.argv.slice(2);
const email = (args.find((a) => a.includes('@')) || '').trim().toLowerCase();
const role = (args.find((a) => ['manager', 'internal', 'external'].includes(a.toLowerCase())) || 'external').toLowerCase();

if (!email) {
  console.error('Usage: node tools/add-member.mjs <email> [manager|internal|external]');
  process.exit(1);
}

function project() {
  const rc = JSON.parse(readFileSync(new URL('../.firebaserc', import.meta.url), 'utf8'));
  return rc.projects.default;
}

async function token() {
  const storePath = `${homedir()}/.config/configstore/firebase-tools.json`;
  let store;
  try {
    store = JSON.parse(readFileSync(storePath, 'utf8'));
  } catch (e) {
    throw new Error('Firebase CLI credentials not found. Please run `npx firebase-tools login` first.');
  }
  const refresh = store.tokens?.refresh_token;
  if (!refresh) throw new Error('Firebase CLI is not signed in: run `npx firebase-tools login` first in your terminal.');
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: refresh,
      client_id: '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com',
      client_secret: 'j9iVZfS8kkCEFUPaAeJV0sAi',
    }),
  });
  const data = await r.json();
  if (!data.access_token) {
    throw new Error(`Failed to refresh token: ${data.error_description || data.error || 're-run npx firebase-tools login'}`);
  }
  return data.access_token;
}

async function setMember(email, role) {
  const t = await token();
  const proj = project();
  const url = `https://firestore.googleapis.com/v1/projects/${proj}/databases/(default)/documents/members/${encodeURIComponent(email)}`;
  const now = new Date().toISOString();
  const res = await fetch(url, {
    method: 'PATCH',
    headers: {
      authorization: `Bearer ${t}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      fields: {
        role: { stringValue: role },
        invitedBy: { stringValue: 'admin' },
        invitedAt: { timestampValue: now },
      },
    }),
  });
  const body = await res.json();
  if (!res.ok) {
    throw new Error(`Firestore error: ${body.error?.message || res.statusText}`);
  }
  console.log(`✓ Added ${email} to ${proj}/members with role "${role}"`);
}

try {
  await setMember(email, role);
} catch (err) {
  console.error('Error:', err.message);
  process.exit(1);
}
