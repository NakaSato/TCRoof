// Growatt's server OpenAPI v1 for the Monitoring poll (CHA-93), the same calls as the app's `GrowattAPI` and
// `MonitoringFeed`: every call is a read-only GET with the header `token`, and every answer is
// `{ data, error_code, error_msg }`. The answers are kept as Growatt wrote them, so the iPads map them with the
// app's own code (`Monitoring.GrowattMap`). Pure apart from `GrowattClient.get`, so growatt.test.ts covers it.

/** What `config/monitoring`'s JSON (`Monitoring.Settings`, written by the app) says that the poll needs. */
export type MonitoringSettings = {
  servers: { id: string; url: string }[];
  pollMinutes: number;
  archiveNightly: boolean;
  loggerOfflineMinutes: number;
  /** Station id → Growatt plant id (as text). */
  pairings: Record<string, string>;
  /** Station id → server id; none: the first server. */
  pairingServers: Record<string, string>;
};

/** Growatt answers 10012 to calls closer than this on the same plant. */
export const MINIMUM_POLL_MINUTES = 5;

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);
const num = (v: unknown, d: number) => (typeof v === 'number' && Number.isFinite(v) ? v : d);

/** The settings from their JSON, with the app's defaults for what is missing; null when it isn't JSON. */
export function parseSettings(json: string): MonitoringSettings | null {
  let o: unknown;
  try { o = JSON.parse(json); } catch { return null; }
  if (!isObject(o)) return null;
  const servers = (Array.isArray(o.servers) ? o.servers : [])
    .filter(isObject)
    .filter((s) => typeof s.id === 'string' && typeof s.url === 'string')
    .map((s) => ({ id: (s.id as string).toUpperCase(), url: s.url as string }));
  const strings = (v: unknown) => Object.fromEntries(Object.entries(isObject(v) ? v : {})
    .filter((e): e is [string, string] => typeof e[1] === 'string'));
  const pairingServers = Object.fromEntries(Object.entries(strings(o.pairingServers)).map(([k, v]) => [k, v.toUpperCase()]));
  return {
    servers,
    pollMinutes: Math.max(num(o.pollMinutes, 5), MINIMUM_POLL_MINUTES),
    archiveNightly: typeof o.archiveNightly === 'boolean' ? o.archiveNightly : true,
    loggerOfflineMinutes: num(o.loggerOfflineMinutes, 30),
    pairings: strings(o.pairings),
    pairingServers,
  };
}

export type Pairing = { stationID: string; plantID: number; server: { id: string; url: string } };

/** Every station with a plant (a number) and a server to read it from, as `Settings.pairing(of:)` decides. */
export function pairings(s: MonitoringSettings): Pairing[] {
  const out: Pairing[] = [];
  for (const [stationID, raw] of Object.entries(s.pairings)) {
    const plantID = Number(raw.trim());
    if (!raw.trim() || !Number.isInteger(plantID)) continue;
    const server = s.servers.find((x) => x.id === s.pairingServers[stationID]) ?? s.servers[0];
    if (server) out.push({ stationID, plantID, server });
  }
  return out;
}

/** A server's URL as the token may be sent to: https on Growatt's own hosts only. */
export function growattURL(url: string): URL | null {
  let u: URL;
  try { u = new URL(url); } catch { return null; }
  if (u.protocol !== 'https:' || !(u.hostname === 'growatt.com' || u.hostname.endsWith('.growatt.com'))) return null;
  if (!u.pathname.endsWith('/')) u.pathname += '/';
  return u;
}

/** The Firestore document id of a station: its id without `/`, which a document id can't hold. */
export const stationDoc = (stationID: string) => stationID.replace(/\//g, '_');

// MARK: days

const DAY = 86_400_000;
const BANGKOK = 7 * 3_600_000;

/** `yyyy-MM-dd` of the Bangkok day `back` days before `now`'s, as the plant's `date` (`MonitoringFeed.day`). */
export function bangkokDayText(now: Date, back = 0): string {
  return new Date(now.getTime() + BANGKOK - back * DAY).toISOString().slice(0, 10);
}

/** `yyyy-MM-01` of the Bangkok month `back` months before `now`'s. */
export function bangkokMonthStart(now: Date, back: number): string {
  const d = new Date(now.getTime() + BANGKOK);
  const m = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() - back, 1));
  return m.toISOString().slice(0, 10);
}

/** The ranges `plant/energy` by day is read in: the 29 days before today, a week at a time (10004 past that). */
export const DAY_CHUNKS: [number, number][] = [[29, 23], [22, 16], [15, 9], [8, 2], [1, 1]];

/** `GMT+7`, `UTC+07:00`, `UTC`: minutes east of UTC; GMT+8 (the guide's examples) when it says nothing readable. */
export function zoneOffsetMinutes(text: string): number {
  const t = text.trim().toUpperCase();
  if (t === 'UTC' || t === 'GMT' || t === 'Z') return 0;
  const m = /^(?:GMT|UTC)([+-])(\d{1,2})(?::?(\d{2}))?$/.exec(t);
  if (!m) return 8 * 60;
  return (m[1] === '-' ? -1 : 1) * (Number(m[2]) * 60 + Number(m[3] ?? 0));
}

/** `yyyy-MM-dd HH:mm[:ss]` on a clock `offset` minutes east of UTC; null for anything else. */
export function plantTime(text: string, offset: number): Date | null {
  const m = /^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?$/.exec(text.trim());
  if (!m) return null;
  const [y, mo, d, h, mi, s] = [m[1], m[2], m[3], m[4] ?? '0', m[5] ?? '0', m[6] ?? '0'].map(Number);
  if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59 || s > 60) return null;
  return new Date(Date.UTC(y, mo - 1, d, h, mi, s) - offset * 60_000);
}

// MARK: health

export type Health = 'normal' | 'alarm' | 'offline';

const numberOf = (v: unknown): number | null => {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string' && v.trim() !== '' && Number.isFinite(Number(v))) return Number(v);
  return null;
};

/**
 * What the app's `GrowattMap.station` raises from the logger and the inverters, so a station in trouble shows in
 * Firestore with every iPad closed: offline when `plant/data` has no reading or its last is older than the logger
 * threshold, else in alarm when an inverter is at fault (3) or lost (-1, or `lost`). `ผลิตต่ำกว่าที่คาด` needs the
 * fleet and stays the app's.
 */
export function health(data: unknown, devices: unknown, now: Date, offlineAfterMinutes: number): { health: Health; faults: number; lastReading: Date | null } {
  const d = isObject(data) ? data : {};
  const last = typeof d.last_update_time === 'string' ? plantTime(d.last_update_time, zoneOffsetMinutes(String(d.timezone ?? ''))) : null;
  const lastReading = last;
  if (last === null || now.getTime() - last.getTime() > offlineAfterMinutes * 60_000) return { health: 'offline', faults: 0, lastReading };
  const rows = isObject(devices) && Array.isArray(devices.devices) ? devices.devices.filter(isObject) : [];
  const faults = rows.filter((r) => {
    const type = numberOf(r.type);
    if (type === 2 || type === 3) return false;
    const status = numberOf(r.status);
    const lost = r.lost === true || r.lost === 'true' || r.lost === 1 || r.lost === '1';
    return status === 3 || status === -1 || lost;
  }).length;
  return { health: faults > 0 ? 'alarm' : 'normal', faults, lastReading };
}

// MARK: client

export class GrowattFailure extends Error {
  constructor(readonly code: string, message: string) { super(message); }
}

/** The app's `GrowattAPI.Failure.message`, so an iPad shows the server's failure as it would its own. */
export function failureMessage(code: string, msg = ''): string {
  if (code === '10011') return 'Growatt ไม่อนุญาต (token ไม่ถูกต้อง)';
  if (code === '10012') return 'เรียก Growatt ถี่เกินไป | ลองใหม่อีกครั้ง';
  if (code === 'offline') return 'ติดต่อ Growatt ไม่ได้';
  if (code === 'bad') return 'อ่านข้อมูลจาก Growatt ไม่ได้';
  if (code === 'token') return 'ยังไม่มี token ของบัญชีนี้บนเซิร์ฟเวอร์';
  if (code.startsWith('http')) return `Growatt ตอบกลับผิดพลาด (HTTP ${code.slice(4)})`;
  return `Growatt ตอบกลับผิดพลาด (${code}${msg ? ' ' + msg : ''})`;
}

type Fetch = (url: string, init: { headers: Record<string, string>; signal?: AbortSignal }) => Promise<{ ok: boolean; status: number; text(): Promise<string> }>;

export class GrowattClient {
  /** Retries after 10012, waiting `retryDelayMs` × the attempt, as the app's client does. */
  retries = 3;
  retryDelayMs = 6_000;
  /** Calls made, for the log. */
  calls = 0;

  constructor(readonly base: URL, private readonly token: string, private readonly fetcher: Fetch = fetch,
              private readonly sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))) {}

  /** The answer's text when `error_code` is 0; a `GrowattFailure` otherwise. GET only: nothing here writes. */
  async get(path: string, query: Record<string, string>): Promise<string> {
    const u = new URL(path, this.base);
    for (const k of Object.keys(query).sort()) u.searchParams.set(k, query[k]);
    for (let attempt = 1; ; attempt++) {
      this.calls++;
      let text: string;
      try {
        const res = await this.fetcher(u.toString(), { headers: { token: this.token }, signal: AbortSignal.timeout(20_000) });
        if (!res.ok) throw new GrowattFailure(`http ${res.status}`, failureMessage(`http ${res.status}`));
        text = await res.text();
      } catch (e) {
        if (e instanceof GrowattFailure) throw e;
        throw new GrowattFailure('offline', failureMessage('offline'));
      }
      let o: unknown;
      try { o = JSON.parse(text); } catch { throw new GrowattFailure('bad', failureMessage('bad')); }
      if (!isObject(o)) throw new GrowattFailure('bad', failureMessage('bad'));
      const code = String(numberOf(o.error_code) ?? 0);
      if (code === '10012' && attempt <= this.retries) { await this.sleep(this.retryDelayMs * attempt); continue; }
      if (code !== '0') throw new GrowattFailure(code, failureMessage(code, typeof o.error_msg === 'string' ? o.error_msg : ''));
      if (!isObject(o.data)) throw new GrowattFailure('bad', failureMessage('bad'));
      return text;
    }
  }

  /** `plant/list`: every plant of the token with its power now, 100 a page; the poll's one call for the whole fleet. */
  plants = (page: number) => this.get('plant/list', { page: String(page), perpage: '100' });
  data = (plantID: number) => this.get('plant/data', { plant_id: String(plantID) });
  power = (plantID: number, date: string) => this.get('plant/power', { plant_id: String(plantID), date });
  devices = (plantID: number) => this.get('device/list', { plant_id: String(plantID), page: '1', perpage: '100' });
  energy = (plantID: number, start: string, end: string, unit: 'day' | 'month') =>
    this.get('plant/energy', { plant_id: String(plantID), start_date: start, end_date: end, time_unit: unit });
}

/** `data` of an answer `get` returned. */
export const body = (text: string): unknown => (JSON.parse(text) as { data: unknown }).data;

/**
 * Several `plant/energy` answers as one, as the app joins the day chunks: `{ error_code: 0, data: { energys } }`
 * with every chunk's rows in order.
 */
export function joinEnergy(texts: string[]): string {
  const energys = texts.flatMap((t) => {
    const d = body(t);
    return isObject(d) && Array.isArray(d.energys) ? d.energys : [];
  });
  return JSON.stringify({ error_code: 0, error_msg: '', data: { energys } });
}
