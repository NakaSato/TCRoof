// TCRoof Cloud Functions. `assistant` is the project assistant's proxy to Qwen: the app runs the tools on the device
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
import { logger } from 'firebase-functions/v2';
import { bangkokDay, checkMember, checkRequest, cleanReply, isQuestion, LIMITS } from './guard';

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
          tools: body.tools,
          tool_choice: 'auto',
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
