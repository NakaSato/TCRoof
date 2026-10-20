// firestore.rules for the three roles and the Maintainer (docs/reference/roles/user-roles.json).
// `npm install && npm test` in this folder; the emulator needs Java (Homebrew: PATH=/opt/homebrew/opt/openjdk/bin:$PATH).
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { test, before, after, beforeEach } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, query, where, getDocs, serverTimestamp, deleteField, writeBatch } from 'firebase/firestore';

const TEAM = 'team@tcroof.co', BOSS = 'boss@tcroof.co', CON = 'foreman@contractor.co', OTHER = 'other@contractor.co';
const DEV = 'dev@tcroof.co', DEV2 = 'dev2@tcroof.co';
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
    await setDoc(doc(d, 'members', DEV), { role: 'maintainer' });
    await setDoc(doc(d, 'members', DEV2), { role: 'maintainer' });
    await setDoc(doc(d, 'config', 'app'), { installLink: 'x' });
    await setDoc(doc(d, 'config', 'devKey'), { hash: 'h', salt: 's', iterations: 100000 });
    await setDoc(doc(d, 'config', 'roleOverrides'), {});
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

test('the team deletes a job, a contractor never', async () => {
  await assertSucceeds(deleteDoc(doc(db(TEAM), 'jobs', 'mine')));
  await assertFails(deleteDoc(doc(db(CON), 'jobs', 'mine')));
  await assertSucceeds(deleteDoc(doc(db(BOSS), 'jobs', 'mine')));
  // the team still creates them
  await assertSucceeds(setDoc(doc(db(TEAM), 'jobs', 'new'), { code: 'TC-9' }));
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
  await assertSucceeds(setDoc(doc(d, 'jobs', 'mine'), { iecReport: '{"x":1}', iecState: 'open' }, { merge: true }));
  await assertFails(updateDoc(doc(d, 'jobs', 'mine'), { status: 'completed' }));
  await assertFails(updateDoc(doc(d, 'jobs', 'mine'), { externals: [CON, OTHER] }));
  await assertFails(setDoc(doc(d, 'jobs', 'theirs'), { iecReport: '{}', iecState: 'open' }, { merge: true }));
  await assertFails(setDoc(doc(d, 'jobs', 'new'), { code: 'TC-9', externals: [CON] }));
  await assertFails(deleteDoc(doc(d, 'jobs', 'mine')));
});

test('an external member edits and sends the IEC test while it is open, never closes or reopens it', async () => {
  const d = db(CON);
  const job = doc(d, 'jobs', 'mine');
  // an older app's write, without the state, is refused
  await assertFails(setDoc(job, { iecReport: '{"x":1}' }, { merge: true }));
  await assertFails(setDoc(job, { iecReport: '{"x":1}', iecState: 'closed' }, { merge: true }));
  await assertSucceeds(setDoc(job, { iecReport: '{"x":2}', iecState: 'sent' }, { merge: true }));
  // sent: no more edits, no taking it back
  await assertFails(setDoc(job, { iecReport: '{"x":3}', iecState: 'sent' }, { merge: true }));
  await assertFails(setDoc(job, { iecReport: '{"x":3}', iecState: 'open' }, { merge: true }));
  // the team closes it: still locked; the team reopens it: open to the contractor again
  await assertSucceeds(setDoc(doc(db(TEAM), 'jobs', 'mine'), { iecReport: '{"x":2,"result":{}}', iecState: 'closed' }, { merge: true }));
  await assertFails(setDoc(job, { iecReport: '{"x":4}', iecState: 'open' }, { merge: true }));
  await assertSucceeds(setDoc(doc(db(TEAM), 'jobs', 'mine'), { iecReport: '{"x":2}', iecState: 'open' }, { merge: true }));
  await assertSucceeds(setDoc(job, { iecReport: '{"x":5}', iecState: 'open' }, { merge: true }));
});

test('an external member sends the weekly request of their own job, signed with their email', async () => {
  const d = db(CON);
  const job = doc(d, 'jobs', 'mine');
  await assertSucceeds(setDoc(job, { weeklyRequests: '[{"w":1}]', weeklyRequestsBy: CON }, { merge: true }));
  // with the IEC test in the same write, as the app sends them
  await assertSucceeds(setDoc(job, { iecReport: '{"x":1}', iecState: 'open', weeklyRequests: '[{"w":2}]', weeklyRequestsBy: CON }, { merge: true }));
  // someone else's name, or none
  await assertFails(setDoc(job, { weeklyRequests: '[{"w":3}]', weeklyRequestsBy: TEAM }, { merge: true }));
  await assertFails(setDoc(job, { weeklyRequests: '[{"w":3}]', weeklyRequestsBy: null }, { merge: true }));
  // another job, or other keys alongside
  await assertFails(setDoc(doc(d, 'jobs', 'theirs'), { weeklyRequests: '[]', weeklyRequestsBy: CON }, { merge: true }));
  await assertFails(setDoc(job, { weeklyRequests: '[{"w":4}]', weeklyRequestsBy: CON, status: 'completed' }, { merge: true }));
  await assertFails(setDoc(job, { weeklyRequests: '[{"w":4}]', weeklyRequestsBy: CON, routineSettings: '{}' }, { merge: true }));
  // a sent IEC test doesn't stop the weekly request, nor does the request reopen the test
  await assertSucceeds(setDoc(job, { iecReport: '{"x":2}', iecState: 'sent' }, { merge: true }));
  await assertSucceeds(setDoc(job, { weeklyRequests: '[{"w":5}]', weeklyRequestsBy: CON }, { merge: true }));
  await assertFails(setDoc(job, { iecReport: '{"x":3}', iecState: 'open', weeklyRequests: '[{"w":6}]', weeklyRequestsBy: CON }, { merge: true }));
  // the team writes the requests under any name
  await assertSucceeds(setDoc(doc(db(TEAM), 'jobs', 'mine'), { weeklyRequests: '[]', weeklyRequestsBy: TEAM }, { merge: true }));
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
  // nor changes what was signed: the MP plan counts signed reports
  await assertFails(updateDoc(doc(d, 'installLogs', 'signed'), { report: '{"edited":1}' }));
  await assertSucceeds(updateDoc(doc(db(TEAM), 'installLogs', 'signed'), { report: '{"fixed":1}' }));
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
  // listing themselves doesn't let them attach a photo to another contractor's report or to an ICL
  await assertFails(setDoc(doc(d, 'photos', 'p5'), { tag: 'x', drive: 'id', log: 'log2', externals: [CON] }));
  await assertFails(setDoc(doc(d, 'photos', 'p6'), { tag: 'x', drive: 'id', log: 'nope', externals: [CON] }));
  await assertFails(setDoc(doc(d, 'photos', 'p7'), { tag: 'x', drive: 'id', inspection: 'icl1', externals: [CON] }));
  await assertSucceeds(setDoc(doc(db(TEAM), 'photos', 'p8'), { tag: 'x', drive: 'id', inspection: 'icl1', externals: [CON] }));
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

// A new user, from before the invite to removal: what each step lets them do.
const NEW = 'new.person@gmail.com';

test('a new team member: nothing before the invite, everything after, nothing once removed', async () => {
  const boss = db(BOSS);
  // before the invite: their own (missing) membership is readable, as sign-in checks it; nothing else
  const before = await assertSucceeds(getDoc(doc(db(NEW), 'members', NEW)));
  assert.equal(before.exists(), false);
  await assertFails(getDoc(doc(db(NEW), 'jobs', 'mine')));
  await assertFails(getDocs(collection(db(NEW), 'jobs')));

  await assertSucceeds(setDoc(doc(boss, 'members', NEW), { role: 'internal', invitedBy: BOSS, invitedAt: new Date() }));
  const after = await assertSucceeds(getDoc(doc(db(NEW), 'members', NEW)));
  assert.equal(after.data().role, 'internal');
  await assertSucceeds(getDocs(collection(db(NEW), 'jobs')));
  await assertSucceeds(updateDoc(doc(db(NEW), 'jobs', 'mine'), { status: 'completed' }));
  await assertSucceeds(getDoc(doc(db(NEW), 'jobContacts', 'mine')));
  // a team member, not a manager: can't see or change the member list, their own role included
  await assertFails(getDocs(collection(db(NEW), 'members')));
  await assertFails(updateDoc(doc(db(NEW), 'members', NEW), { role: 'manager' }));

  await assertSucceeds(deleteDoc(doc(boss, 'members', NEW)));
  await assertFails(getDoc(doc(db(NEW), 'jobs', 'mine')));
});

test('a new member signs in with any capitals, but only with a verified email', async () => {
  await assertSucceeds(setDoc(doc(db(BOSS), 'members', NEW), { role: 'internal', invitedBy: BOSS }));
  const capitals = env.authenticatedContext('caps', { email: 'New.Person@Gmail.com', email_verified: true }).firestore();
  await assertSucceeds(getDoc(doc(capitals, 'jobs', 'mine')));
  const unverified = env.authenticatedContext('unverified', { email: NEW, email_verified: false }).firestore();
  await assertFails(getDoc(doc(unverified, 'jobs', 'mine')));
});

test('a new contractor sees a job only once assigned to it, and everything once made team', async () => {
  const boss = db(BOSS), d = db(NEW);
  await assertSucceeds(setDoc(doc(boss, 'members', NEW), { role: 'external', invitedBy: BOSS, invitedAt: new Date() }));
  // invited, not assigned: their query works and finds nothing; the job itself is closed to them
  const none = await assertSucceeds(getDocs(query(collection(d, 'jobs'), where('externals', 'array-contains', NEW))));
  assert.equal(none.size, 0);
  await assertFails(getDoc(doc(d, 'jobs', 'mine')));

  // the team assigns them next to the first contractor
  await assertSucceeds(updateDoc(doc(db(TEAM), 'jobs', 'mine'), { externals: [CON, NEW] }));
  const mine = await assertSucceeds(getDocs(query(collection(d, 'jobs'), where('externals', 'array-contains', NEW))));
  assert.deepEqual(mine.docs.map((x) => x.id), ['mine']);
  await assertFails(getDoc(doc(d, 'jobs', 'theirs')));
  await assertFails(getDoc(doc(d, 'jobContacts', 'mine')));
  // a record made before the assignment still lists only the first contractor, so it stays closed to them
  await assertFails(getDoc(doc(d, 'installLogs', 'log1')));
  await assertSucceeds(setDoc(doc(d, 'installLogs', 'log9'), { jobID: 'mine', externals: [CON, NEW], report: '{}' }));

  // made team: the whole list
  await assertSucceeds(updateDoc(doc(boss, 'members', NEW), { role: 'internal' }));
  await assertSucceeds(getDocs(collection(d, 'jobs')));
  await assertSucceeds(getDoc(doc(d, 'jobContacts', 'mine')));
});

test('the team names who works on a job; a contractor can\'t change it', async () => {
  await assertSucceeds(updateDoc(doc(db(TEAM), 'jobs', 'mine'), { teamMembers: [TEAM, BOSS] }));
  await assertSucceeds(updateDoc(doc(db(BOSS), 'jobs', 'mine'), { teamMembers: [] }));
  const d = db(CON);
  await assertFails(updateDoc(doc(d, 'jobs', 'mine'), { teamMembers: [CON] }));
  await assertFails(setDoc(doc(d, 'jobs', 'mine'), { iecReport: '{}', iecState: 'open', teamMembers: [CON] }, { merge: true }));
  // naming opens nothing: a contractor on the team list still can't read a job not assigned to them
  await assertSucceeds(updateDoc(doc(db(TEAM), 'jobs', 'theirs'), { teamMembers: [CON] }));
  await assertFails(getDoc(doc(d, 'jobs', 'theirs')));
});

test('the team directory: the team reads it, each writes their own, a manager anyone\'s', async () => {
  // each team member lists themselves, with a name
  await assertSucceeds(setDoc(doc(db(TEAM), 'directory', TEAM), { email: TEAM, name: 'สมชาย' }));
  await assertSucceeds(setDoc(doc(db(BOSS), 'directory', BOSS), { email: BOSS }));
  await assertSucceeds(getDocs(collection(db(TEAM), 'directory')));
  // an external member neither reads nor lists themselves
  await assertFails(getDocs(collection(db(CON), 'directory')));
  await assertFails(setDoc(doc(db(CON), 'directory', CON), { email: CON }));
  // a team member writes only their own; a manager writes any team member's, never an outsider's or an external's
  await assertFails(setDoc(doc(db(TEAM), 'directory', BOSS), { email: BOSS, name: 'x' }));
  await assertSucceeds(setDoc(doc(db(BOSS), 'directory', TEAM), { email: TEAM }, { merge: true }));
  await assertFails(setDoc(doc(db(BOSS), 'directory', CON), { email: CON }));
  await assertFails(setDoc(doc(db(BOSS), 'directory', 'nobody@gmail.com'), { email: 'nobody@gmail.com' }));
  // only the email and a name, the email being the entry's own
  await assertFails(setDoc(doc(db(TEAM), 'directory', TEAM), { email: TEAM, role: 'manager' }));
  await assertFails(setDoc(doc(db(TEAM), 'directory', TEAM), { email: BOSS }));
  // a manager removes an entry; a team member can't
  await assertFails(deleteDoc(doc(db(TEAM), 'directory', TEAM)));
  await assertSucceeds(deleteDoc(doc(db(BOSS), 'directory', TEAM)));
});

test('a job that names its people: only they or a manager sign its daily reports', async () => {
  const ENG = 'eng@tcroof.co';
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, 'members', ENG), { role: 'internal' });
    await updateDoc(doc(d, 'jobs', 'mine'), { teamMembers: [ENG], supervisor: '' });
    await setDoc(doc(d, 'installLogs', 'signed'), { jobID: 'mine', externals: [CON], report: '{}', engineerSignedAt: 5 });
  });
  // not on the job: no signing, but editing (keeping or clearing the signature) still goes
  await assertFails(updateDoc(doc(db(TEAM), 'installLogs', 'log1'), { engineerSignedAt: 1 }));
  await assertFails(updateDoc(doc(db(TEAM), 'installLogs', 'log1'), { inspectorAckAt: 1 }));
  await assertSucceeds(updateDoc(doc(db(TEAM), 'installLogs', 'log1'), { report: '{"a":1}' }));
  await assertSucceeds(updateDoc(doc(db(TEAM), 'installLogs', 'signed'), { report: '{"b":1}' }));
  await assertSucceeds(updateDoc(doc(db(TEAM), 'installLogs', 'signed'), { report: '{"c":1}', engineerSignedAt: null }));
  await assertFails(setDoc(doc(db(TEAM), 'installLogs', 'new'), { jobID: 'mine', report: '{}', engineerSignedAt: 1 }));
  // the job's team member, the manager, and the supervisor once named, sign
  await assertSucceeds(updateDoc(doc(db(ENG), 'installLogs', 'log1'), { engineerSignedAt: 2 }));
  await assertSucceeds(updateDoc(doc(db(BOSS), 'installLogs', 'log1'), { inspectorAckAt: 3 }));
  await assertSucceeds(updateDoc(doc(db(BOSS), 'jobs', 'mine'), { supervisor: TEAM }));
  await assertSucceeds(updateDoc(doc(db(TEAM), 'installLogs', 'log1'), { engineerSignedAt: 4 }));
  // a job naming none of ours: any team member (the first test signs log1 so)
  await assertSucceeds(updateDoc(doc(db(TEAM), 'installLogs', 'log2'), { engineerSignedAt: 5 }));
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

// ── the Maintainer, suspension, the developer key, role overrides and the audit log (จัดการผู้ใช้และสิทธิ์)

const suspend = (by) => ({ suspended: true, suspendedBy: by, suspendedAt: serverTimestamp() });
const reactivate = { suspended: deleteField(), suspendedBy: deleteField(), suspendedAt: deleteField() };

test('a Maintainer does what a manager does', async () => {
  const d = db(DEV);
  await assertSucceeds(getDocs(collection(d, 'members')));
  await assertSucceeds(deleteDoc(doc(d, 'jobs', 'theirs')));
  await assertSucceeds(setDoc(doc(d, 'members', NEW), { role: 'external', invitedBy: DEV, invitedAt: new Date() }));
  await assertSucceeds(updateDoc(doc(d, 'members', NEW), { role: 'internal' }));
  await assertSucceeds(updateDoc(doc(d, 'members', BOSS), { role: 'internal' }));
});

test('the maintainer role is never written from the app', async () => {
  for (const who of [BOSS, DEV]) {
    const d = db(who);
    await assertFails(setDoc(doc(d, 'members', 'x@gmail.com'), { role: 'maintainer', invitedBy: who }));
    await assertFails(updateDoc(doc(d, 'members', TEAM), { role: 'maintainer' }));
    // a Maintainer's document: no role change, no removal, by a manager or another Maintainer
    await assertFails(updateDoc(doc(d, 'members', who === DEV ? DEV2 : DEV), { role: 'manager' }));
    await assertFails(deleteDoc(doc(d, 'members', who === DEV ? DEV2 : DEV)));
  }
  await assertFails(updateDoc(doc(db(DEV), 'members', DEV), { role: 'manager' }));
});

test('only a Maintainer suspends and reactivates, never themselves or another Maintainer', async () => {
  await assertFails(updateDoc(doc(db(BOSS), 'members', TEAM), suspend(BOSS)));
  await assertFails(updateDoc(doc(db(TEAM), 'members', TEAM), suspend(TEAM)));
  await assertFails(updateDoc(doc(db(DEV), 'members', DEV), suspend(DEV)));
  await assertFails(updateDoc(doc(db(DEV), 'members', DEV2), suspend(DEV)));
  // as themselves, at the server's time
  await assertFails(updateDoc(doc(db(DEV), 'members', TEAM), suspend(BOSS)));
  await assertFails(updateDoc(doc(db(DEV), 'members', TEAM), { suspended: true, suspendedBy: DEV, suspendedAt: new Date(0) }));
  // the suspension alone, not a role change with it
  await assertFails(updateDoc(doc(db(DEV), 'members', TEAM), { ...suspend(DEV), role: 'manager' }));
  await assertSucceeds(updateDoc(doc(db(DEV), 'members', TEAM), suspend(DEV)));
  // a manager can't reactivate, or remove the account to invite it back
  await assertFails(updateDoc(doc(db(BOSS), 'members', TEAM), reactivate));
  await assertFails(deleteDoc(doc(db(BOSS), 'members', TEAM)));
  // reactivating takes the three keys away, nothing else
  await assertFails(updateDoc(doc(db(DEV2), 'members', TEAM), { suspended: false }));
  await assertSucceeds(updateDoc(doc(db(DEV2), 'members', TEAM), reactivate));
  await assertSucceeds(updateDoc(doc(db(DEV), 'members', CON), suspend(DEV)));
  await assertSucceeds(deleteDoc(doc(db(DEV), 'members', CON)));
  // a manager is suspended like anyone else
  await assertSucceeds(updateDoc(doc(db(DEV), 'members', BOSS), suspend(DEV)));
});

test('a suspended member reads nothing but their own membership', async () => {
  await assertSucceeds(updateDoc(doc(db(DEV), 'members', TEAM), suspend(DEV)));
  await assertFails(getDocs(collection(db(TEAM), 'jobs')));
  await assertFails(setDoc(doc(db(TEAM), 'jobs', 'new'), { code: 'x' }));
  await assertFails(getDoc(doc(db(TEAM), 'config', 'app')));
  const me = await assertSucceeds(getDoc(doc(db(TEAM), 'members', TEAM)));
  assert.equal(me.data().suspended, true);
  await assertSucceeds(updateDoc(doc(db(DEV), 'members', TEAM), reactivate));
  await assertSucceeds(getDocs(collection(db(TEAM), 'jobs')));
  // a suspended manager manages nothing
  await assertSucceeds(updateDoc(doc(db(DEV), 'members', BOSS), suspend(DEV)));
  await assertFails(getDocs(collection(db(BOSS), 'members')));
  await assertFails(deleteDoc(doc(db(BOSS), 'jobs', 'mine')));
});

test('the developer key: a Maintainer reads and sets it, as a hash', async () => {
  for (const who of [TEAM, BOSS, CON]) {
    await assertFails(getDoc(doc(db(who), 'config', 'devKey')));
    await assertFails(setDoc(doc(db(who), 'config', 'devKey'), { hash: 'h', salt: 's', iterations: 100000, setBy: who }));
  }
  await assertSucceeds(getDoc(doc(db(TEAM), 'config', 'app')));
  await assertSucceeds(getDoc(doc(db(DEV), 'config', 'devKey')));
  await assertSucceeds(setDoc(doc(db(DEV), 'config', 'devKey'), { hash: 'h2', salt: 's2', iterations: 100000, expiresAt: new Date(), setBy: DEV, setAt: new Date() }));
  await assertFails(setDoc(doc(db(DEV), 'config', 'devKey'), { hash: 'h', salt: 's', iterations: 100000, setBy: DEV, digits: '123456' }));
  await assertFails(setDoc(doc(db(DEV), 'config', 'devKey'), { hash: 'h', salt: 's', iterations: 10, setBy: DEV }));
  await assertFails(setDoc(doc(db(DEV), 'config', 'devKey'), { hash: 'h', salt: 's', iterations: 100000, setBy: DEV2 }));
  await assertFails(setDoc(doc(db(DEV), 'config', 'app'), { installLink: 'y' }));
});

test('role overrides: every member reads them, a Maintainer writes them', async () => {
  for (const who of [TEAM, CON, BOSS, DEV]) await assertSucceeds(getDoc(doc(db(who), 'config', 'roleOverrides')));
  for (const who of [TEAM, CON, BOSS]) await assertFails(setDoc(doc(db(who), 'config', 'roleOverrides'), { 'internal|tools.register': 'view' }));
  await assertSucceeds(setDoc(doc(db(DEV), 'config', 'roleOverrides'), { 'internal|tools.register': 'view' }));
  await assertFails(getDoc(doc(db('stranger@gmail.com'), 'config', 'roleOverrides')));
});

const entry = (by, kind = 'role') => ({ at: serverTimestamp(), by, kind, title: 'เปลี่ยนบทบาท', detail: '' });

test('the audit log: written once as yourself by a manager or Maintainer, read by a Maintainer', async () => {
  await assertSucceeds(setDoc(doc(db(DEV), 'auditLog', 'a1'), entry(DEV)));
  await assertSucceeds(setDoc(doc(db(BOSS), 'auditLog', 'a2'), entry(BOSS, 'user')));
  await assertFails(setDoc(doc(db(TEAM), 'auditLog', 'a3'), entry(TEAM)));
  await assertFails(setDoc(doc(db(BOSS), 'auditLog', 'a4'), entry(DEV)));
  await assertFails(setDoc(doc(db(DEV), 'auditLog', 'a5'), { ...entry(DEV), at: new Date(0) }));
  await assertFails(setDoc(doc(db(DEV), 'auditLog', 'a6'), entry(DEV, 'other')));
  await assertFails(setDoc(doc(db(DEV), 'auditLog', 'a7'), { ...entry(DEV), extra: 1 }));
  await assertSucceeds(getDocs(collection(db(DEV), 'auditLog')));
  await assertFails(getDocs(collection(db(BOSS), 'auditLog')));
  await assertFails(updateDoc(doc(db(DEV), 'auditLog', 'a1'), { title: 'x' }));
  await assertFails(deleteDoc(doc(db(DEV), 'auditLog', 'a1')));
});

test('one save of the page: role, suspension, invite, overrides and their audit entries in a batch', async () => {
  const d = db(DEV), b = writeBatch(d);
  b.update(doc(d, 'members', TEAM), { role: 'manager' });
  b.update(doc(d, 'members', CON), suspend(DEV));
  b.set(doc(d, 'members', NEW), { role: 'external', invitedBy: DEV, invitedAt: serverTimestamp() });
  b.set(doc(d, 'config', 'roleOverrides'), { 'internal|tools.register': 'view' });
  for (let i = 0; i < 4; i++) b.set(doc(d, 'auditLog', 'b' + i), entry(DEV));
  await assertSucceeds(b.commit());
});

test('assistantUsage is the assistant function\'s only: no client reads or writes it', async () => {
  for (const who of [TEAM, BOSS, CON, DEV]) {
    const ref = doc(db(who), 'assistantUsage', `${who}_2026-10-19`);
    await assertFails(getDoc(ref));
    await assertFails(setDoc(ref, { count: 0 }));
  }
});

test('tank standard: every member reads it, a manager saves a newer revision signed by themselves', async () => {
  const ref = (who) => doc(db(who), 'config', 'tankStandard');
  const std = (by, revision) => ({ json: '{"rowGap":3}', revision, savedBy: by, updatedAt: serverTimestamp() });
  await assertFails(setDoc(ref(TEAM), std(TEAM, 1)));
  await assertFails(setDoc(ref(CON), std(CON, 1)));
  await assertFails(setDoc(ref(BOSS), std(TEAM, 1)));
  await assertSucceeds(setDoc(ref(BOSS), std(BOSS, 1)));
  for (const who of [TEAM, CON, BOSS]) await assertSucceeds(getDoc(ref(who)));
  await assertFails(getDoc(doc(db('stranger@gmail.com'), 'config', 'tankStandard')));
  await assertFails(setDoc(ref(BOSS), std(BOSS, 1)));
  await assertFails(setDoc(ref(BOSS), { ...std(BOSS, 2), extra: 1 }));
  await assertSucceeds(setDoc(ref(BOSS), std(BOSS, 2)));
  await assertSucceeds(setDoc(ref(DEV), std(DEV, 3)));
  await assertFails(deleteDoc(ref(BOSS)));
});

test('standard designs: every member reads them, only the team saves, never an older revision', async () => {
  const design = { json: '{}', revision: 2, savedBy: TEAM };
  await assertSucceeds(setDoc(doc(db(TEAM), 'standardDesigns', 'team-1'), design));
  await assertSucceeds(getDoc(doc(db(CON), 'standardDesigns', 'team-1')));
  await assertSucceeds(getDocs(collection(db(CON), 'standardDesigns')));
  await assertFails(setDoc(doc(db(CON), 'standardDesigns', 'team-2'), design));
  await assertFails(updateDoc(doc(db(CON), 'standardDesigns', 'team-1'), { revision: 3 }));
  await assertSucceeds(updateDoc(doc(db(BOSS), 'standardDesigns', 'team-1'), { revision: 3, json: '{"a":1}' }));
  await assertFails(updateDoc(doc(db(TEAM), 'standardDesigns', 'team-1'), { revision: 2 }));
  await assertFails(deleteDoc(doc(db(BOSS), 'standardDesigns', 'team-1')));
  await assertFails(getDoc(doc(db('stranger@gmail.com'), 'standardDesigns', 'team-1')));
});

test('a standard design\'s sheet pages: every member reads, the team writes', async () => {
  const page = { design: 'team-1', data: 'AAAA', width: 10, height: 10 };
  await assertSucceeds(setDoc(doc(db(TEAM), 'standardDesignSheets', 'p1'), page));
  await assertSucceeds(getDoc(doc(db(CON), 'standardDesignSheets', 'p1')));
  await assertFails(setDoc(doc(db(CON), 'standardDesignSheets', 'p2'), page));
  await assertFails(setDoc(doc(db(TEAM), 'standardDesignSheets', 'p3'), { width: 1 }));
  await assertFails(deleteDoc(doc(db(BOSS), 'standardDesignSheets', 'p1')));
});

test('the travel log is personal: its owner and managers read it, only the owner writes it', async () => {
  const MATE = 'mate@tcroof.co';
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, 'members', MATE), {});
    await setDoc(doc(d, 'expenses', 'e1'), { ownerEmail: TEAM, amount: 5000 });
    await setDoc(doc(d, 'trips', 't1'), { ownerEmail: TEAM, stops: '[]' });
    await setDoc(doc(d, 'claims', 'c1'), { ownerEmail: TEAM, month: '2026-10' });
  });
  const me = db(TEAM), mate = db(MATE);
  // the owner lists theirs with the app's query, writes and deletes them
  await assertSucceeds(getDocs(query(collection(me, 'expenses'), where('ownerEmail', '==', TEAM))));
  await assertSucceeds(getDocs(query(collection(me, 'trips'), where('ownerEmail', '==', TEAM))));
  await assertSucceeds(getDocs(query(collection(me, 'claims'), where('ownerEmail', '==', TEAM))));
  await assertSucceeds(updateDoc(doc(me, 'expenses', 'e1'), { amount: 6000 }));
  await assertSucceeds(setDoc(doc(me, 'expenses', 'e2'), { ownerEmail: TEAM, amount: 100 }));
  await assertFails(setDoc(doc(me, 'expenses', 'e3'), { ownerEmail: TEAM, amount: '100' }));
  // nobody makes a record in someone else's name, or hands theirs over
  await assertFails(setDoc(doc(me, 'expenses', 'e4'), { ownerEmail: MATE, amount: 100 }));
  await assertFails(updateDoc(doc(me, 'trips', 't1'), { ownerEmail: MATE }));
  // another team member neither reads nor changes them
  await assertFails(getDoc(doc(mate, 'expenses', 'e1')));
  await assertFails(getDocs(collection(mate, 'expenses')));
  await assertFails(updateDoc(doc(mate, 'expenses', 'e1'), { amount: 1 }));
  await assertFails(deleteDoc(doc(mate, 'trips', 't1')));
  // a manager reads everyone's, but doesn't write them
  await assertSucceeds(getDocs(collection(db(BOSS), 'expenses')));
  await assertSucceeds(getDoc(doc(db(BOSS), 'claims', 'c1')));
  await assertFails(updateDoc(doc(db(BOSS), 'expenses', 'e1'), { amount: 1 }));
  // contractors have no travel log here
  await assertFails(getDoc(doc(db(CON), 'expenses', 'e1')));
  await assertFails(setDoc(doc(db(CON), 'expenses', 'e9'), { ownerEmail: CON, amount: 1 }));
  await assertSucceeds(deleteDoc(doc(me, 'expenses', 'e1')));
});

test('a claim decision: managers write it, never on their own, and the claimant reads theirs', async () => {
  const MATE = 'mate@tcroof.co';
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'members', MATE), {});
  });
  const r = (o) => ({ ownerEmail: TEAM, month: '2026-10', submittedAt: 1000, decision: 'approved', note: '', total: 500,
                      reviewedBy: BOSS, reviewerName: '', reviewedAt: 2000, ...o });
  const id = `${TEAM}_2026-10`;
  await assertSucceeds(setDoc(doc(db(BOSS), 'claimReviews', id), r()));
  await assertSucceeds(setDoc(doc(db(BOSS), 'claimReviews', id), r({ decision: 'returned', note: 'ใบเสร็จไม่ชัด' })));
  // signed as someone else, a wrong id, an unknown decision or a text time
  await assertFails(setDoc(doc(db(BOSS), 'claimReviews', id), r({ reviewedBy: 'x@tcroof.co' })));
  await assertFails(setDoc(doc(db(BOSS), 'claimReviews', `${MATE}_2026-10`), r()));
  await assertFails(setDoc(doc(db(BOSS), 'claimReviews', id), r({ decision: 'paid' })));
  await assertFails(setDoc(doc(db(BOSS), 'claimReviews', id), r({ submittedAt: '1000' })));
  // a manager's own claim
  await assertFails(setDoc(doc(db(BOSS), 'claimReviews', `${BOSS}_2026-10`), r({ ownerEmail: BOSS })));
  // the claimant and the rest of the team don't write it
  await assertFails(setDoc(doc(db(TEAM), 'claimReviews', id), r({ reviewedBy: TEAM })));
  await assertFails(updateDoc(doc(db(TEAM), 'claimReviews', id), { decision: 'approved' }));
  await assertFails(setDoc(doc(db(MATE), 'claimReviews', id), r({ reviewedBy: MATE })));
  // the claimant reads theirs with the app's query, the others don't, managers read all
  await assertSucceeds(getDocs(query(collection(db(TEAM), 'claimReviews'), where('ownerEmail', '==', TEAM))));
  await assertFails(getDoc(doc(db(MATE), 'claimReviews', id)));
  await assertFails(getDoc(doc(db(CON), 'claimReviews', id)));
  await assertSucceeds(getDocs(collection(db(BOSS), 'claimReviews')));
  await assertFails(deleteDoc(doc(db(BOSS), 'claimReviews', id)));
});
