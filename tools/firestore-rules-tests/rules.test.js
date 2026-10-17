// firestore.rules for the three roles (docs/reference/roles/user-roles.json).
// `npm install && npm test` in this folder; the emulator needs Java (Homebrew: PATH=/opt/homebrew/opt/openjdk/bin:$PATH).
import { readFileSync } from 'node:fs';
import { test, before, after, beforeEach } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, query, where, getDocs } from 'firebase/firestore';

const TEAM = 'team@tcroof.co', BOSS = 'boss@tcroof.co', CON = 'foreman@contractor.co', OTHER = 'other@contractor.co';
let env;

const db = (email) => env.authenticatedContext(email.replace(/\W/g, '_'), { email, email_verified: true }).firestore();

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-tcroof',
    firestore: { rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(async () => { await env.cleanup(); });

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, 'members', TEAM), {});
    await setDoc(doc(d, 'members', BOSS), { role: 'manager' });
    await setDoc(doc(d, 'members', CON), { role: 'external' });
    await setDoc(doc(d, 'members', OTHER), { role: 'external' });
    await setDoc(doc(d, 'jobs', 'mine'), { code: 'TC-1', externals: [CON], iecReport: null, status: 'installing' });
    await setDoc(doc(d, 'jobs', 'theirs'), { code: 'TC-2', externals: [OTHER] });
    await setDoc(doc(d, 'jobContacts', 'mine'), { phone: '081', address: 'x' });
    await setDoc(doc(d, 'installLogs', 'log1'), { jobID: 'mine', externals: [CON], report: '{}' });
    await setDoc(doc(d, 'installLogs', 'log2'), { jobID: 'theirs', externals: [OTHER], report: '{}' });
    await setDoc(doc(d, 'inspections', 'icl1'), { jobID: 'mine', externals: [CON] });
    await setDoc(doc(d, 'pwaSurveys', 's1'), { json: '{}', externals: [CON] });
    await setDoc(doc(d, 'pwaSurveyRevisions', 'r1'), { json: '{}' });
  });
});

test('the team reads and writes everything, as before roles', async () => {
  const d = db(TEAM);
  await assertSucceeds(getDocs(collection(d, 'jobs')));
  await assertSucceeds(getDoc(doc(d, 'jobContacts', 'mine')));
  await assertSucceeds(updateDoc(doc(d, 'jobs', 'mine'), { status: 'completed' }));
  await assertSucceeds(updateDoc(doc(d, 'installLogs', 'log1'), { engineerSignedAt: 1 }));
  await assertSucceeds(getDocs(collection(d, 'pwaSurveyRevisions')));
  await assertSucceeds(getDocs(collection(db(BOSS), 'jobs')));
});

test('a non-member reads nothing', async () => {
  await assertFails(getDoc(doc(db('stranger@gmail.com'), 'jobs', 'mine')));
});

test('an external member lists only their jobs and records', async () => {
  const d = db(CON);
  await assertSucceeds(getDocs(query(collection(d, 'jobs'), where('externals', 'array-contains', CON))));
  await assertSucceeds(getDocs(query(collection(d, 'installLogs'), where('externals', 'array-contains', CON))));
  await assertSucceeds(getDocs(query(collection(d, 'pwaSurveys'), where('externals', 'array-contains', CON))));
  await assertSucceeds(getDoc(doc(d, 'jobs', 'mine')));
  await assertFails(getDocs(collection(d, 'jobs')));
  await assertFails(getDoc(doc(d, 'jobs', 'theirs')));
  await assertFails(getDoc(doc(d, 'installLogs', 'log2')));
});

test('an external member never reads contacts, REVs or another job', async () => {
  const d = db(CON);
  await assertFails(getDoc(doc(d, 'jobContacts', 'mine')));
  await assertFails(getDocs(collection(d, 'pwaSurveyRevisions')));
});

test('an external member changes only the IEC test of their job', async () => {
  const d = db(CON);
  await assertSucceeds(setDoc(doc(d, 'jobs', 'mine'), { iecReport: '{"x":1}' }, { merge: true }));
  await assertFails(updateDoc(doc(d, 'jobs', 'mine'), { status: 'completed' }));
  await assertFails(updateDoc(doc(d, 'jobs', 'mine'), { externals: [CON, OTHER] }));
  await assertFails(setDoc(doc(d, 'jobs', 'theirs'), { iecReport: '{}' }, { merge: true }));
  await assertFails(setDoc(doc(d, 'jobs', 'new'), { code: 'TC-9', externals: [CON] }));
  await assertFails(deleteDoc(doc(d, 'jobs', 'mine')));
});

test('an external member fills daily reports but never signs them', async () => {
  const d = db(CON);
  await assertSucceeds(setDoc(doc(d, 'installLogs', 'log3'), { jobID: 'mine', externals: [CON], report: '{}' }));
  await assertSucceeds(updateDoc(doc(d, 'installLogs', 'log1'), { report: '{"a":1}' }));
  await assertFails(updateDoc(doc(d, 'installLogs', 'log1'), { engineerSignedAt: 1 }));
  await assertFails(updateDoc(doc(d, 'installLogs', 'log1'), { inspectorAckAt: 1 }));
  await assertFails(setDoc(doc(d, 'installLogs', 'log4'), { jobID: 'theirs', externals: [CON], report: '{}' }));
  await assertFails(deleteDoc(doc(d, 'installLogs', 'log1')));
});

test('an external member never takes our engineer\'s signature off', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'installLogs', 'signed'), { jobID: 'mine', externals: [CON], report: '{}', engineerSignedAt: 5, inspectorAckAt: 6 });
  });
  const d = db(CON);
  await assertFails(setDoc(doc(d, 'installLogs', 'signed'), { jobID: 'mine', externals: [CON], report: '{"edited":1}' }));
  await assertFails(updateDoc(doc(d, 'installLogs', 'signed'), { inspectorAckAt: null }));
  await assertSucceeds(updateDoc(doc(db(TEAM), 'installLogs', 'signed'), { engineerSignedAt: null, inspectorAckAt: null }));
});

test('a team member\'s job without externals (an older app) stays the team\'s and leaves the contractor out', async () => {
  await assertSucceeds(setDoc(doc(db(TEAM), 'jobs', 'mine'), { code: 'TC-1' }));
  await assertFails(getDoc(doc(db(CON), 'jobs', 'mine')));
});

test('an external member only reads the ICL', async () => {
  const d = db(CON);
  await assertSucceeds(getDoc(doc(d, 'inspections', 'icl1')));
  await assertFails(updateDoc(doc(d, 'inspections', 'icl1'), { currentStep: 2 }));
});

test('an external member edits their survey but not who it is open to', async () => {
  const d = db(CON);
  await assertSucceeds(updateDoc(doc(d, 'pwaSurveys', 's1'), { json: '{"b":1}' }));
  await assertFails(updateDoc(doc(d, 'pwaSurveys', 's1'), { externals: [] }));
  await assertFails(setDoc(doc(d, 'pwaSurveys', 's2'), { json: '{}', externals: [CON] }));
});

test('photos of their records', async () => {
  const d = db(CON);
  await assertSucceeds(setDoc(doc(d, 'photos', 'p1'), { tag: 'x', drive: 'id', log: 'log1', externals: [CON] }));
  await assertSucceeds(setDoc(doc(d, 'photos', 'p2'), { tag: 'x', drive: 'id', iecJob: 'mine', externals: [CON] }));
  await assertFails(setDoc(doc(d, 'photos', 'p3'), { tag: 'x', drive: 'id', iecJob: 'theirs', externals: [CON] }));
  await assertFails(setDoc(doc(d, 'photos', 'p4'), { tag: 'x', drive: 'id', log: 'log2' }));
});

test('a manager invites, changes the role of and removes members, never themselves', async () => {
  const d = db(BOSS);
  await assertSucceeds(getDocs(collection(d, 'members')));
  await assertSucceeds(setDoc(doc(d, 'members', 'new@gmail.com'), { role: 'external', invitedBy: BOSS, invitedAt: new Date() }));
  await assertSucceeds(updateDoc(doc(d, 'members', 'new@gmail.com'), { role: 'internal' }));
  await assertSucceeds(deleteDoc(doc(d, 'members', 'new@gmail.com')));
  await assertFails(setDoc(doc(d, 'members', 'Upper@gmail.com'), { role: 'internal', invitedBy: BOSS }));
  await assertFails(setDoc(doc(d, 'members', 'x@gmail.com'), { role: 'admin', invitedBy: BOSS }));
  await assertFails(setDoc(doc(d, 'members', 'y@gmail.com'), { role: 'internal', invitedBy: TEAM }));
  await assertFails(setDoc(doc(d, 'members', 'z@gmail.com'), { role: 'internal', invitedBy: BOSS, note: 'x' }));
  await assertFails(updateDoc(doc(d, 'members', BOSS), { role: 'internal' }));
  await assertFails(deleteDoc(doc(d, 'members', BOSS)));
  await assertFails(updateDoc(doc(d, 'members', TEAM), { invitedBy: BOSS }));
});

test('only a manager reads the member list or changes it', async () => {
  for (const who of [TEAM, CON, 'stranger@gmail.com']) {
    const d = db(who);
    await assertFails(getDocs(collection(d, 'members')));
    await assertFails(setDoc(doc(d, 'members', 'new@gmail.com'), { role: 'manager', invitedBy: who }));
    await assertFails(updateDoc(doc(d, 'members', who === TEAM ? TEAM : CON), { role: 'manager' }));
    await assertFails(deleteDoc(doc(d, 'members', OTHER)));
  }
  await assertSucceeds(getDoc(doc(db(TEAM), 'members', TEAM)));
  await assertSucceeds(getDoc(doc(db('stranger@gmail.com'), 'members', 'stranger@gmail.com')));
});

test('an issued REV goes only with its survey, or by a manager', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, 'pwaSurveys', 'S9'), { json: '{}' });
    await setDoc(doc(d, 'pwaSurveyRevisions', 'S9_REV 00'), { json: '{}' });
    await setDoc(doc(d, 'pwaSurveyRevisions', 'S8_REV 00'), { json: '{}' });
  });
  await assertFails(deleteDoc(doc(db(TEAM), 'pwaSurveyRevisions', 'S9_REV 00')));
  await assertFails(deleteDoc(doc(db(CON), 'pwaSurveyRevisions', 'S8_REV 00')));
  await assertSucceeds(deleteDoc(doc(db(TEAM), 'pwaSurveyRevisions', 'S8_REV 00')));
  await assertSucceeds(deleteDoc(doc(db(BOSS), 'pwaSurveyRevisions', 'S9_REV 00')));
});
