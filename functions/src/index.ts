// TCRoof Cloud Functions (`monitoringPoll`, `monitoringArchive` and `monitoringToken` are below). `assistant` is the project assistant's proxy to Qwen: the app runs the tools on the device
// (TCRoofCore/Assistant) and sends the conversation here; this function checks the caller is on the team, counts their
// requests per day and forwards the conversation with the API key, which never reaches a device.
//
// Set up once (Blaze plan):
//   firebase functions:secrets:set QWEN_API_KEY
//   npm run deploy            (QWEN_MODEL, QWEN_BASE_URL and ASSISTANT_DAILY_LIMIT are asked for or read from .env.<project>)
import { initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { defineInt, defineSecret, defineString } from 'firebase-functions/params';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions/v2';
import { bangkokDay, checkMember, checkRequest, cleanReply, isQuestion, LIMITS } from './guard';
import { bangkokDayText, failureMessage, GrowattClient, GrowattFailure, growattURL, Pairing, pairings, parseSettings, stationDoc } from './growatt';
import { ARCHIVE_DAYS, archiveDoc, archiveStation, checkTokenRequest, detailDue, isManager, pickDetail, pollStation, Previous, readFleet } from './monitoring';

initializeApp();

const QWEN_API_KEY = defineSecret('QWEN_API_KEY');
// free quota only: turn on "Free quota only" for this model in the Model Studio console (calls are refused, never billed)
const QWEN_MODEL = defineString('QWEN_MODEL', { default: 'qwen3.8-max', description: 'Qwen model id' });
const QWEN_BASE_URL = defineString('QWEN_BASE_URL', {
  default: 'https://maas.qwencloudapi.com/compatible-mode/v1',
  description: 'OpenAI-compatible base URL of the Qwen service',
});
const DAILY_LIMIT = defineInt('ASSISTANT_DAILY_LIMIT', { default: 50, description: 'Questions per person per day' });

export const assistant = onCall(
  { region: 'asia-southeast1', secrets: [QWEN_API_KEY], timeoutSeconds: 90, memory: '256MiB', maxInstances: 10 },
  async (request) => {
    const token = request.auth?.token;
    const email = token?.email?.toLowerCase();
    const db = getFirestore();
    const member = email ? (await db.doc(`members/${email}`).get()).data() : undefined;
    const refused = checkMember(email, token?.email_verified, member);
    if (refused) throw new HttpsError(refused.code, refused.message);

    const body = checkRequest(request.data);
    if ('code' in body) throw new HttpsError(body.code, body.message);

    // count before calling, so a failed call still counts: questions against the limit (a question's tool rounds are
    // free), and every request against the limit × the rounds a question may take, which stops a runaway loop
    const limit = DAILY_LIMIT.value();
    const question = isQuestion(body.messages);
    const usage = db.doc(`assistantUsage/${email}_${bangkokDay(new Date())}`);
    const { allowed, used } = await db.runTransaction(async (tx) => {
      const data = (await tx.get(usage)).data();
      const n = (data?.count as number | undefined) ?? 0;
      const requests = (data?.requests as number | undefined) ?? n;
      if ((question && n >= limit) || requests >= limit * LIMITS.roundsPerQuestion) return { allowed: false, used: n };
      tx.set(usage, { email, day: bangkokDay(new Date()), count: n + (question ? 1 : 0), requests: requests + 1,
        updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      return { allowed: true, used: n + (question ? 1 : 0) };
    });
    if (!allowed) throw new HttpsError('resource-exhausted', `ถามผู้ช่วยครบ ${limit} คำถามของวันนี้แล้ว`);

    let res: Response;
    try {
      res = await fetch(`${QWEN_BASE_URL.value().replace(/\/$/, '')}/chat/completions`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${QWEN_API_KEY.value()}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          model: QWEN_MODEL.value(),
          messages: body.messages,
          // a request without tools (the feed's daily summary) sends neither
          ...(body.tools.length ? { tools: body.tools, tool_choice: 'auto' } : {}),
          max_tokens: LIMITS.maxTokens,
          temperature: 0.2,
        }),
        signal: AbortSignal.timeout(80_000),
      });
    } catch (e) {
      logger.warn('qwen unreachable', { error: String(e) });
      throw new HttpsError('unavailable', 'ติดต่อผู้ช่วยไม่ได้ ลองอีกครั้ง');
    }
    if (!res.ok) {
      // the body may echo the request; log the status and Qwen's error code only
      const err = await res.json().catch(() => ({})) as { error?: { code?: unknown; type?: unknown } };
      logger.warn('qwen error', { status: res.status, code: err.error?.code, type: err.error?.type });
      throw new HttpsError(res.status === 429 ? 'resource-exhausted' : 'unavailable',
        res.status === 429 ? 'ผู้ช่วยมีคนใช้มาก ลองอีกครั้งในอีกสักครู่' : 'ผู้ช่วยขัดข้อง ลองอีกครั้ง');
    }
    const json = await res.json() as {
      choices?: { message?: unknown }[];
      usage?: { prompt_tokens?: number; completion_tokens?: number };
    };
    const message = cleanReply(json.choices?.[0]?.message);
    if (!message) throw new HttpsError('unavailable', 'ผู้ช่วยไม่ได้ตอบ ลองอีกครั้ง');

    // token counts only; the conversation is never stored
    await usage.set({
      promptTokens: FieldValue.increment(json.usage?.prompt_tokens ?? 0),
      completionTokens: FieldValue.increment(json.usage?.completion_tokens ?? 0),
    }, { merge: true });

    return { message, remainingToday: Math.max(limit - used, 0) };
  },
);

// MARK: Monitoring (CHA-93)
//
// Growatt is read here for every paired station of ตั้งค่า Monitoring (`config/monitoring`), whether or not an iPad is
// open: read-only calls, one after another. Every `pollMinutes` one `plant/list` per account gives the fleet's power
// now (`listPower`, `listAt`); a station's detail is read every `detailMinutes` (15), or every run while it is in
// alarm or offline, spread over the runs (monitoring.ts). Each
// station's answers go to `monitoring/{station}` as Growatt wrote them; the team's iPads read them there and map them
// as they would their own (`Monitoring.ServerReading`), polling Growatt themselves only while these are stale. With
// เก็บข้อมูลถาวรทุกคืน on, `monitoringArchive` keeps each day's 5-minute power for good (Growatt keeps ~95 days).
// The tokens are in `monitoringTokens/{server id}`, which the rules let no device read: a manager's ตั้งค่า Monitoring
// sends one through `monitoringToken`, and the app keeps showing only its last four characters.

const monitoringRegion = 'asia-southeast1';

async function monitoringSetup() {
  const db = getFirestore();
  const json = (await db.doc('config/monitoring').get()).data()?.json;
  const settings = typeof json === 'string' ? parseSettings(json) : null;
  if (!settings) return null;
  const ids = [...new Set(settings.servers.map((s) => s.id))];
  const tokens = new Map<string, string>();
  for (const id of ids) {
    const t = (await db.doc(`monitoringTokens/${id}`).get()).data()?.token;
    if (typeof t === 'string' && t) tokens.set(id, t);
  }
  return { db, settings, tokens };
}

function client(p: Pairing, tokens: Map<string, string>): GrowattClient | GrowattFailure {
  const token = tokens.get(p.server.id);
  if (!token) return new GrowattFailure('token', failureMessage('token'));
  const url = growattURL(p.server.url);
  if (!url) return new GrowattFailure('bad', 'ที่อยู่เซิร์ฟเวอร์ต้องเป็น https ของ growatt.com');
  return new GrowattClient(url, token);
}

export const monitoringPoll = onSchedule(
  { region: monitoringRegion, schedule: 'every 5 minutes', timeZone: 'Asia/Bangkok', timeoutSeconds: 540, memory: '256MiB',
    maxInstances: 1, retryCount: 0 },
  async () => {
    const setup = await monitoringSetup();
    if (!setup) return;
    const { db, settings, tokens } = setup;
    const now = new Date();
    const list = pairings(settings);
    if (list.length === 0) return;
    const refs = list.map((p) => db.doc(`monitoring/${stationDoc(p.stationID)}`));
    const docs = await db.getAll(...refs);
    const entries = list.map((p, i) => {
      const prev = docs[i].data();
      const previous: Previous = prev ? { plantID: prev.plantID, attemptedAt: prev.attemptedAt?.toDate?.(), historyDay: prev.historyDay,
        health: prev.health } : undefined;
      return { p, ref: refs[i], previous };
    });
    let calls = 0, read = 0, fleet = 0;

    // the fleet's power now: one plant/list read per account, every run
    const byServer = new Map<string, typeof entries>();
    for (const e of entries) byServer.set(e.p.server.id, [...(byServer.get(e.p.server.id) ?? []), e]);
    for (const group of byServer.values()) {
      const api = client(group[0].p, tokens);
      if (api instanceof GrowattFailure) continue;
      const power = await readFleet(api, new Set(group.map((e) => e.p.plantID)));
      calls += api.calls;
      for (const e of group) {
        // only onto a document of the same plant: a re-paired station's first detail read writes it whole
        if (e.previous?.plantID !== e.p.plantID || !power.has(e.p.plantID)) continue;
        await e.ref.set({ listPower: power.get(e.p.plantID), listAt: now }, { merge: true });
        fleet++;
      }
    }

    // the detail: troubled stations every run, the rest every detailMinutes, spread over the runs
    const dueOnes = entries.filter((e) => detailDue(e.previous, e.p.plantID, now, settings));
    for (const { p, ref, previous } of pickDetail(dueOnes, entries.length, settings)) {
      const api = client(p, tokens);
      if (api instanceof GrowattFailure) {
        await ref.set({ stationID: p.stationID, plantID: p.plantID, serverID: p.server.id, attemptedAt: now,
          failure: { code: api.code, message: api.message } }, { merge: true });
        continue;
      }
      const poll = await pollStation(api, p, previous, new Date(), settings.loggerOfflineMinutes);
      calls += api.calls;
      if (poll.fields.readAt) read++;
      await ref.set(poll.fields, { merge: !poll.replace });
    }
    logger.info('monitoring poll', { stations: list.length, fleet, read, calls });
  },
);

export const monitoringArchive = onSchedule(
  // after midnight in Bangkok, clear of the poll's minutes
  { region: monitoringRegion, schedule: '2 1 * * *', timeZone: 'Asia/Bangkok', timeoutSeconds: 540, memory: '256MiB',
    maxInstances: 1, retryCount: 0 },
  async () => {
    const setup = await monitoringSetup();
    if (!setup || !setup.settings.archiveNightly) return;
    const { db, settings, tokens } = setup;
    const now = new Date();
    let saved = 0;
    for (const p of pairings(settings)) {
      const api = client(p, tokens);
      if (api instanceof GrowattFailure) continue;
      const docID = stationDoc(p.stationID);
      const have = new Set<string>();
      // the days by id, so no index is needed
      const days = Array.from({ length: ARCHIVE_DAYS }, (_, i) => bangkokDayText(now, i + 1));
      const recent = await db.getAll(...days.map((d) => db.doc(`monitoringArchive/${archiveDoc(docID, d)}`)));
      for (const d of recent) if (d.exists && d.data()?.plantID === p.plantID) have.add(d.data()?.date);
      for (const day of await archiveStation(api, p, have, now)) {
        await db.doc(`monitoringArchive/${archiveDoc(docID, day.date)}`).set({
          stationID: p.stationID, plantID: p.plantID, date: day.date, power: day.power, archivedAt: FieldValue.serverTimestamp(),
        });
        saved++;
      }
    }
    logger.info('monitoring archive', { stations: pairings(settings).length, saved });
  },
);

/** A manager's token for a monitoring server, kept where no device reads it; '' removes it. */
export const monitoringToken = onCall(
  { region: monitoringRegion, timeoutSeconds: 30, memory: '256MiB', maxInstances: 5 },
  async (request) => {
    const token = request.auth?.token;
    const email = token?.email?.toLowerCase();
    if (!email || token?.email_verified !== true) throw new HttpsError('unauthenticated', 'ต้องเข้าสู่ระบบด้วยบัญชี Google ที่ยืนยันแล้ว');
    const db = getFirestore();
    const member = (await db.doc(`members/${email}`).get()).data();
    if (!isManager(member)) throw new HttpsError('permission-denied', 'เฉพาะผู้จัดการตั้งค่า Monitoring ได้');
    const body = checkTokenRequest(request.data);
    if ('message' in body) throw new HttpsError('invalid-argument', body.message);
    const ref = db.doc(`monitoringTokens/${body.serverID}`);
    if (!body.token) {
      await ref.delete();
      return { suffix: '' };
    }
    const suffix = body.token.slice(-4);
    await ref.set({ token: body.token, suffix, setBy: email, setAt: FieldValue.serverTimestamp() });
    return { suffix };
  },
);
