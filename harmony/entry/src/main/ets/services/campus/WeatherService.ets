/**
 * WeatherService — 海淀校区天气（Open-Meteo 公共 API，免登录免 key）
 * 坐标对齐原项目 weather.ts（清华园 39.9593, 116.2985）。
 * 模块级缓存 30 分钟：首页反复进入不重复请求。
 */
import { rcp } from '@kit.RemoteCommunicationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'WeatherSvc';
const DOMAIN: number = 0x0001;

const HAIDIAN_LATITUDE: number = 39.9593;
const HAIDIAN_LONGITUDE: number = 116.2985;
const CACHE_TTL_MS: number = 30 * 60 * 1000;

const WEATHER_URL: string =
  'https://api.open-meteo.com/v1/forecast' +
  `?latitude=${HAIDIAN_LATITUDE}&longitude=${HAIDIAN_LONGITUDE}` +
  '&current=temperature_2m,apparent_temperature,weather_code' +
  '&hourly=precipitation_probability' +
  '&daily=temperature_2m_max,temperature_2m_min' +
  '&timezone=Asia/Shanghai&forecast_days=1';

/** 首页所需的精简天气快照 */
export class HomeWeather {
  temperature: number = NaN;        // 当前气温 ℃
  apparent: number = NaN;           // 体感温度 ℃
  condition: string = '';           // 天气描述（中文）
  minTemp: number = NaN;            // 今日最低 ℃
  maxTemp: number = NaN;            // 今日最高 ℃
  precipProbability: number = NaN;  // 未来 3 小时最大降水概率 %
  updatedAt: string = '';
}

/** WMO weather code → 中文描述（对齐原项目 describeWeatherCode 语义） */
export function describeWeatherCode(code: number): string {
  if (Number.isNaN(code)) {
    return '未知';
  }
  if (code === 0) {
    return '晴';
  }
  if (code === 1 || code === 2) {
    return '多云';
  }
  if (code === 3) {
    return '阴';
  }
  if (code === 45 || code === 48) {
    return '雾';
  }
  if (code === 51 || code === 53 || code === 55 || code === 56 || code === 57) {
    return '小雨';
  }
  if (code === 61 || code === 63 || code === 80 || code === 81) {
    return '有雨';
  }
  if (code === 65 || code === 82) {
    return '大雨';
  }
  if (code === 66 || code === 67) {
    return '冻雨';
  }
  if (code === 71 || code === 73 || code === 75 || code === 77 || code === 85 || code === 86) {
    return '降雪';
  }
  if (code === 95 || code === 96 || code === 99) {
    return '雷阵雨';
  }
  return '天气多变';
}

function numField(rec: Record<string, Object>, key: string): number {
  const v: Object | undefined = rec[key];
  return typeof v === 'number' ? v : NaN;
}

function strField(rec: Record<string, Object>, key: string): string {
  const v: Object | undefined = rec[key];
  return typeof v === 'string' ? v : '';
}

function arrField(rec: Record<string, Object>, key: string): Object[] {
  const v: Object | undefined = rec[key];
  if (Array.isArray(v)) {
    return v as Object[];
  }
  return [];
}

function recField(rec: Record<string, Object>, key: string): Record<string, Object> {
  const v: Object | undefined = rec[key];
  if (typeof v === 'object' && v !== null) {
    return v as Record<string, Object>;
  }
  const empty: Record<string, Object> = {};
  return empty;
}

/** Open-Meteo current.time 形如 "2026-09-19T14:00"（Asia/Shanghai 本地时间） */
function findCurrentHourIndex(hourlyTimes: Object[], currentTime: string): number {
  if (hourlyTimes.length === 0) {
    return -1;
  }
  const hourKey: string = currentTime.length >= 13 ? currentTime.substring(0, 13) : '';
  if (hourKey.length > 0) {
    for (let i: number = 0; i < hourlyTimes.length; i++) {
      const t: string = typeof hourlyTimes[i] === 'string' ? hourlyTimes[i] as string : '';
      if (t.length >= 13 && t.substring(0, 13) === hourKey) {
        return i;
      }
    }
  }
  return 0;
}

/** 未来 hours 小时内最大降水概率（%），无数据返回 NaN */
function maxPrecipProbability(probs: Object[], startIndex: number, hours: number): number {
  if (startIndex < 0 || probs.length === 0) {
    return NaN;
  }
  let max: number = NaN;
  const end: number = Math.min(startIndex + hours, probs.length);
  for (let i: number = startIndex; i < end; i++) {
    const v: Object = probs[i];
    if (typeof v === 'number') {
      const n: number = v as number;
      if (Number.isNaN(max) || n > max) {
        max = n;
      }
    }
  }
  return max;
}

let cachedWeather: HomeWeather | undefined = undefined;
let cachedAtMs: number = 0;

/**
 * 拉取海淀当前天气（带缓存）。
 * forceRefresh=true 时无视缓存重新请求。
 */
export async function fetchHomeWeather(forceRefresh: boolean): Promise<HomeWeather> {
  const now: number = Date.now();
  if (!forceRefresh && cachedWeather !== undefined && now - cachedAtMs < CACHE_TTL_MS) {
    return cachedWeather;
  }

  const session: rcp.Session = rcp.createSession();
  try {
    const config: rcp.Configuration = {
      transfer: {
        autoRedirect: true,
        timeout: { connectMs: 15000, transferMs: 15000 }
      }
    };
    const req: rcp.Request = new rcp.Request(WEATHER_URL, 'GET', {}, '', undefined, undefined, config);
    const resp: rcp.Response = await session.fetch(req);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw new Error(`weather http ${resp.statusCode}`);
    }
    const body: string = resp.toString() ?? '';
    const root: Record<string, Object> = JSON.parse(body) as Record<string, Object>;

    const current: Record<string, Object> = recField(root, 'current');
    const hourly: Record<string, Object> = recField(root, 'hourly');
    const daily: Record<string, Object> = recField(root, 'daily');

    const w: HomeWeather = new HomeWeather();
    w.temperature = numField(current, 'temperature_2m');
    w.apparent = numField(current, 'apparent_temperature');
    w.updatedAt = strField(current, 'time');
    const code: number = numField(current, 'weather_code');
    w.condition = describeWeatherCode(code);

    const dailyMax: Object[] = arrField(daily, 'temperature_2m_max');
    const dailyMin: Object[] = arrField(daily, 'temperature_2m_min');
    if (typeof dailyMax[0] === 'number') {
      w.maxTemp = dailyMax[0] as number;
    }
    if (typeof dailyMin[0] === 'number') {
      w.minTemp = dailyMin[0] as number;
    }

    const hourlyTimes: Object[] = arrField(hourly, 'time');
    const hourlyProbs: Object[] = arrField(hourly, 'precipitation_probability');
    const idx: number = findCurrentHourIndex(hourlyTimes, w.updatedAt);
    w.precipProbability = maxPrecipProbability(hourlyProbs, idx, 3);

    cachedWeather = w;
    cachedAtMs = now;
    hilog.info(DOMAIN, TAG, 'WEATHER ok temp=%{public}f code cond=%{public}s', w.temperature, w.condition);
    return w;
  } finally {
    session.close();
  }
}

/** 首页副标题："海淀 23° · 晴 · 今日 18/30°"（+ 降水概率高时提示带伞） */
export function buildWeatherSubtitle(w: HomeWeather): string {
  const parts: string[] = [];
  parts.push('海淀');
  if (!Number.isNaN(w.temperature)) {
    parts.push(`${Math.round(w.temperature)}°`);
  }
  if (w.condition.length > 0) {
    parts.push(w.condition);
  }
  let s: string = parts.join(' ');
  if (!Number.isNaN(w.minTemp) && !Number.isNaN(w.maxTemp)) {
    s += ` · 今日 ${Math.round(w.minTemp)}/${Math.round(w.maxTemp)}°`;
  }
  if (!Number.isNaN(w.precipProbability) && w.precipProbability >= 45) {
    s += ' · 建议带伞';
  }
  return s;
}
