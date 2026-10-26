// What the assistant function accepts, checked before anything reaches Qwen. Pure, so guard.test.ts covers it.
import allowedTools from './allowed-tools.json';

export const LIMITS = {
  /** Messages per request, the system prompt included (the app keeps 30 after it). */
  messages: 40,
  /** Characters of the whole request (messages and tools, as JSON). */
  chars: 80_000,
  /** Tokens the model may answer with. */
  maxTokens: 1_500,
  /** Requests one question may take (the app's tool rounds), so a day allows at most this × the daily limit. */
  roundsPerQuestion: 5,
};

/** A request starting a new question (it ends with the person's message), as opposed to a tool round of one. */
export function isQuestion(messages: Message[]): boolean {
  return messages[messages.length - 1]?.role === 'user';
}

export const ALLOWED_TOOLS: ReadonlySet<string> = new Set(allowedTools);

export type Refusal = { code: 'unauthenticated' | 'permission-denied' | 'invalid-argument'; message: string };

type Member = { role?: unknown; suspended?: unknown } | undefined;

/** The team, managers and the Maintainer use the assistant; contractors, suspended and unknown accounts don't. */
export function checkMember(email: string | undefined, verified: boolean | undefined, member: Member): Refusal | null {
  if (!email || verified !== true) return { code: 'unauthenticated', message: 'ต้องเข้าสู่ระบบด้วยบัญชี Google ที่ยืนยันแล้ว' };
  if (!member || member.suspended === true) return { code: 'permission-denied', message: 'บัญชีนี้ไม่ได้เป็นสมาชิกทีม' };
  if (member.role === 'external') return { code: 'permission-denied', message: 'ผู้ช่วยโครงการใช้ได้เฉพาะทีมภายในและผู้จัดการ' };
  return null;
}

export type ToolCall = { id: string; type: 'function'; function: { name: string; arguments: string } };
export type Message = {
  role: 'system' | 'user' | 'assistant' | 'tool';
  content: string | null;
  tool_calls?: ToolCall[];
  tool_call_id?: string;
};
export type Tool = { type: 'function'; function: { name: string; description?: string; parameters?: unknown } };

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);

function toolCall(v: unknown): ToolCall | null {
  if (!isObject(v) || typeof v.id !== 'string' || !isObject(v.function)) return null;
  const { name, arguments: args } = v.function;
  if (typeof name !== 'string' || !ALLOWED_TOOLS.has(name) || typeof args !== 'string') return null;
  return { id: v.id, type: 'function', function: { name, arguments: args } };
}

/** The model's message with only the fields the app reads (Qwen may add others, such as reasoning text). */
export function cleanReply(v: unknown): Message | null {
  if (!isObject(v)) return null;
  const content = typeof v.content === 'string' ? v.content : null;
  const calls = Array.isArray(v.tool_calls) ? v.tool_calls.map(toolCall) : [];
  if (calls.some((c) => c === null)) return { role: 'assistant', content: content ?? 'ผู้ช่วยขอใช้เครื่องมือที่ไม่ได้รับอนุญาต' };
  const out: Message = { role: 'assistant', content };
  if (calls.length) out.tool_calls = calls as ToolCall[];
  return out;
}

/** The request rebuilt from known fields only, or why it is refused. */
export function checkRequest(data: unknown): { messages: Message[]; tools: Tool[] } | Refusal {
  const bad = (message: string): Refusal => ({ code: 'invalid-argument', message });
  if (!isObject(data) || !Array.isArray(data.messages) || !Array.isArray(data.tools)) return bad('ต้องมี messages และ tools');
  if (data.messages.length === 0 || data.messages.length > LIMITS.messages) return bad(`messages ต้องมี 1–${LIMITS.messages} ข้อความ`);
  if (JSON.stringify(data).length > LIMITS.chars) return bad('คำขอยาวเกินไป');

  const messages: Message[] = [];
  for (const [i, m] of data.messages.entries()) {
    if (!isObject(m)) return bad(`ข้อความที่ ${i} ไม่ถูกต้อง`);
    const content = m.content === null || m.content === undefined ? null : m.content;
    if (content !== null && typeof content !== 'string') return bad(`ข้อความที่ ${i}: content ต้องเป็นข้อความ`);
    switch (m.role) {
      case 'system':
        if (i !== 0 || content === null) return bad('system ได้เฉพาะข้อความแรก');
        messages.push({ role: 'system', content });
        break;
      case 'user':
        if (content === null) return bad(`ข้อความที่ ${i} ว่าง`);
        messages.push({ role: 'user', content });
        break;
      case 'assistant': {
        const calls = Array.isArray(m.tool_calls) ? m.tool_calls.map(toolCall) : [];
        if (calls.some((c) => c === null)) return bad(`ข้อความที่ ${i}: เครื่องมือไม่ได้รับอนุญาต`);
        const out: Message = { role: 'assistant', content };
        if (calls.length) out.tool_calls = calls as ToolCall[];
        messages.push(out);
        break;
      }
      case 'tool':
        if (typeof m.tool_call_id !== 'string' || content === null) return bad(`ข้อความที่ ${i}: tool ต้องมี tool_call_id`);
        messages.push({ role: 'tool', content, tool_call_id: m.tool_call_id });
        break;
      default:
        return bad(`ข้อความที่ ${i}: role ไม่ถูกต้อง`);
    }
  }
  if (messages[messages.length - 1].role === 'assistant') return bad('ข้อความสุดท้ายต้องเป็นของผู้ใช้หรือผลของเครื่องมือ');

  const tools: Tool[] = [];
  for (const t of data.tools) {
    if (!isObject(t) || t.type !== 'function' || !isObject(t.function)) return bad('tools ไม่ถูกต้อง');
    const { name, description, parameters } = t.function;
    if (typeof name !== 'string' || !ALLOWED_TOOLS.has(name)) return bad(`ไม่อนุญาตเครื่องมือ ${String(name)}`);
    tools.push({ type: 'function', function: { name, description: typeof description === 'string' ? description : undefined, parameters } });
  }
  if (new Set(tools.map((t) => t.function.name)).size !== tools.length) return bad('tools ซ้ำ');
  return { messages, tools };
}

/** The usage document's day, in Bangkok time. */
export function bangkokDay(now: Date): string {
  return new Date(now.getTime() + 7 * 3600_000).toISOString().slice(0, 10);
}
