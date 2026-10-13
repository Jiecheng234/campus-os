/**
 * ============================================================================
 * LLMService — OpenAI 兼容大模型流式对话客户端（多 provider）
 * ============================================================================
 *
 * 【预设】openai / deepseek / dashscope(通义千问) / moonshot / custom，
 *   各含 baseUrl 与默认 model（对齐参考实现 src/services/ai/agentService.ts
 *   的 AI_PRESETS 语义）；custom 由用户填写 OpenAI 兼容 baseUrl/model。
 *
 * 【流式实现】系统网络能力（@ohos.net.http）的 requestInStream：
 *   - 响应码经 Promise 返回；响应体经 on('dataReceive') 逐块回调（ArrayBuffer）
 *   - SSE 增量解析：按行缓冲 → 解析 `data:` 行 → JSON 增量 delta.content，
 *     `[DONE]` 收尾；兼容服务端忽略 stream:true 返回整体 JSON 的回退解析
 *   - 自定义 HTTPS baseUrl 直接可用（T001 已查证），无需降级非流式
 *
 * 【取消语义】返回 LLMStreamSession 取消句柄：cancel() 立即 destroy 请求
 *   并停止消费流，不再回调（页面保留已生成内容并自行标注"中断"）。
 *   停止按钮 / 离开页面 / 超时统一走该句柄（FR-006 / FR-013）。
 *
 * 【错误映射】onError 携带结构化 LLMErrorKind（非预烘焙文案），由页面
 *   经 i18n 映射为可读提示：401/403→密钥无效、429→频率限制、5xx/网络/
 *   超时→可读提示。错误信息与日志均不含 API Key 与鉴权头（FR-015）。
 * ============================================================================
 */
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { Log } from '../../utils/Logger';

const LOG_TAG: string = 'LLMService';
/** 随请求发送的最大历史轮数（上界保护，避免长会话载荷失控） */
const MAX_HISTORY_TURNS: number = 24;
/** 连接超时（ms）：更快暴露网络不可达 */
const CONNECT_TIMEOUT_MS: number = 15000;
/** 读取超时（ms）：需覆盖长回复的整体生成时长 */
const READ_TIMEOUT_MS: number = 300000;
/** dataEnd 后响应码仍未返回时的兜底等待（ms），超时按成功收尾 */
const CODE_FALLBACK_WAIT_MS: number = 2000;

/** 错误类别（页面按类别映射 i18n 可读文案；不承载预烘焙文案） */
export enum LLMErrorKind {
  /** 未配置（Key 为空）：不构造请求 */
  NOT_CONFIGURED = 'notConfigured',
  /** baseUrl 非法/缺失（custom 未填写等）：不构造请求 */
  BAD_BASE_URL = 'badBaseUrl',
  /** 401/403：密钥无效或已过期 */
  AUTH = 'auth',
  /** 429：频率限制 */
  RATE_LIMIT = 'rateLimit',
  /** 5xx：服务端错误 */
  SERVER = 'server',
  /** 网络不可用/连接失败 */
  NETWORK = 'network',
  /** 超时 */
  TIMEOUT = 'timeout',
  /** 请求成功但模型未返回任何内容 */
  EMPTY = 'empty',
}

/** provider 预设（baseUrl + 默认 model；label 由页面经 i18n 渲染） */
export class LLMProviderPreset {
  id: string = '';
  baseUrl: string = '';
  defaultModel: string = '';
}

/** provider 运行配置：预设标识 + 自定义 baseUrl/model（Key 不在此处） */
export class LLMProviderConfig {
  preset: string = 'openai';
  baseUrl: string = '';
  model: string = '';
}

/** 请求消息轮次（role: user/assistant/system） */
export class LLMChatTurn {
  role: string = '';
  content: string = '';
}

/** 流式回调契约：增量 / 完成 / 失败（详见各字段注释） */
export class LLMStreamHandlers {
  /** 每收到一段增量文本回调一次（已解码 UTF-8） */
  onDelta: (chunk: string) => void = (chunk: string) => {};
  /** 正常收尾：参数为完整回复文本（与全部增量拼接结果一致） */
  onDone: (fullText: string) => void = (fullText: string) => {};
  /** 失败：携带错误类别（页面映射可读文案）；用户主动取消不回调 */
  onError: (kind: LLMErrorKind) => void = (kind: LLMErrorKind) => {};
}

/** 请求体（OpenAI 兼容 /chat/completions；stream 固定开启） */
class LLMRequestBody {
  model: string = '';
  stream: boolean = true;
  messages: LLMChatTurn[] = [];
}

/** SSE data 行原始模型（JSON.parse 后一次性断言；字段可能缺失） */
class LLMStreamChunkRaw {
  choices?: LLMStreamChoiceRaw[];
}

class LLMStreamChoiceRaw {
  delta?: LLMStreamDeltaRaw;
  message?: LLMStreamDeltaRaw;
}

class LLMStreamDeltaRaw {
  content?: string;
}

/** 整体 JSON 响应原始模型（服务端忽略 stream:true 时的回退） */
class LLMFullResponseRaw {
  choices?: LLMFullChoiceRaw[];
}

class LLMFullChoiceRaw {
  message?: LLMStreamDeltaRaw;
}

/** 预设常量表（与参考实现 AI_PRESETS 对齐；dashscope=通义千问兼容模式） */
function buildPresets(): Record<string, LLMProviderPreset> {
  const openai: LLMProviderPreset = new LLMProviderPreset();
  openai.id = 'openai';
  openai.baseUrl = 'https://api.openai.com/v1';
  openai.defaultModel = 'gpt-4o-mini';

  const deepseek: LLMProviderPreset = new LLMProviderPreset();
  deepseek.id = 'deepseek';
  deepseek.baseUrl = 'https://api.deepseek.com/v1';
  deepseek.defaultModel = 'deepseek-v4-flash';

  const dashscope: LLMProviderPreset = new LLMProviderPreset();
  dashscope.id = 'dashscope';
  dashscope.baseUrl = 'https://dashscope.aliyuncs.com/compatible-mode/v1';
  dashscope.defaultModel = 'qwen3.7-max';

  const moonshot: LLMProviderPreset = new LLMProviderPreset();
  moonshot.id = 'moonshot';
  moonshot.baseUrl = 'https://api.moonshot.cn/v1';
  moonshot.defaultModel = 'kimi-k2.6';

  const custom: LLMProviderPreset = new LLMProviderPreset();
  custom.id = 'custom';
  custom.baseUrl = '';
  custom.defaultModel = 'gpt-4o-mini';

  const presets: Record<string, LLMProviderPreset> = {
    'openai': openai,
    'deepseek': deepseek,
    'dashscope': dashscope,
    'moonshot': moonshot,
    'custom': custom,
  };
  return presets;
}

const LLM_PRESETS: Record<string, LLMProviderPreset> = buildPresets();

/**
 * 流式会话（取消句柄）：页面持有实例，cancel() 中断请求并停止消费流。
 * 中断后不再产生任何回调；已生成的增量内容由页面保留并标注"中断"。
 */
export class LLMStreamSession {
  private httpRequest: http.HttpRequest | undefined = undefined;
  private handlers: LLMStreamHandlers = new LLMStreamHandlers();
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
  /** 跨块行缓冲（SSE 事件可能被 TCP 分段截断） */
  private lineBuffer: string = '';
  private fullText: string = '';
  /** 原始响应体积留档（仅用于整体 JSON 回退解析与日志长度） */
  private rawBody: string = '';
  private responseCode: number = -1;
  private dataEnded: boolean = false;
  private finished: boolean = false;
  private cancelled: boolean = false;

  /** 用户主动取消：立即终止请求并停止消费流；不回调（页面自行收尾） */
  cancel(): void {
    if (this.finished) {
      return;
    }
    this.cancelled = true;
    this.finished = true;
    Log.i(LOG_TAG, 'STREAM cancelled partial_len=%{public}d', this.fullText.length);
    this.cleanup();
  }

  /** 同步发起流式请求（内部为事件驱动；异步结果经 handlers 回调） */
  begin(config: LLMProviderConfig, apiKey: string, history: LLMChatTurn[],
    systemPrompt: string, handlers: LLMStreamHandlers): void {
    this.handlers = handlers;
    const baseUrl: string = LLMService.resolveBaseUrl(config);
    const model: string = LLMService.resolveModel(config);
    // 前置校验失败不构造请求、不触网（FR-008 加固）
    if (apiKey.length === 0) {
      this.fail(LLMErrorKind.NOT_CONFIGURED);
      return;
    }
    if (baseUrl.length === 0 || model.length === 0) {
      this.fail(LLMErrorKind.BAD_BASE_URL);
      return;
    }

    const body: LLMRequestBody = new LLMRequestBody();
    body.model = model;
    body.stream = true;
    const turns: LLMChatTurn[] = [];
    if (systemPrompt.length > 0) {
      const sysTurn: LLMChatTurn = new LLMChatTurn();
      sysTurn.role = 'system';
      sysTurn.content = systemPrompt;
      turns.push(sysTurn);
    }
    // 仅携带最近若干轮，避免长会话请求体失控
    const start: number = history.length > MAX_HISTORY_TURNS ? history.length - MAX_HISTORY_TURNS : 0;
    for (let i: number = start; i < history.length; i++) {
      turns.push(history[i]);
    }
    body.messages = turns;

    // 鉴权头仅进入请求，不进入任何日志（FR-015）
    const header: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      'Authorization': 'Bearer ' + apiKey,
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: header,
      extraData: JSON.stringify(body),
      connectTimeout: CONNECT_TIMEOUT_MS,
      readTimeout: READ_TIMEOUT_MS,
      usingCache: false,
    };

    const request: http.HttpRequest = http.createHttp();
    this.httpRequest = request;
    request.on('dataReceive', (data: ArrayBuffer) => {
      this.handleChunk(data);
    });
    request.on('dataEnd', () => {
      this.handleDataEnd();
    });
    Log.i(LOG_TAG, 'STREAM start preset=%{public}s model=%{public}s turns=%{public}d',
      config.preset, model, turns.length);
    request.requestInStream(baseUrl + '/chat/completions', options)
      .then((code: number) => {
        this.handleCode(code);
      })
      .catch((e: BusinessError) => {
        this.handleFailure(e);
      });
  }

  // ============================================================
  // 内部：SSE 解析与状态机
  // ============================================================

  private handleChunk(data: ArrayBuffer): void {
    if (this.finished) {
      return;
    }
    const text: string = this.decoder.decodeToString(new Uint8Array(data), { stream: true });
    if (this.rawBody.length < 65536) {
      this.rawBody += text;
    }
    this.lineBuffer += text;
    const lines: string[] = this.lineBuffer.split('\n');
    // 末段可能是不完整行，留待下一块或 dataEnd 补齐
    this.lineBuffer = lines[lines.length - 1];
    for (let i: number = 0; i < lines.length - 1; i++) {
      this.consumeLine(lines[i]);
    }
  }

  /** 解析单行 SSE：`data: {...}` 增量 / `data: [DONE]` 收尾 */
  private consumeLine(line: string): void {
    const trimmed: string = line.trim();
    if (trimmed.indexOf('data:') !== 0) {
      return;
    }
    const payload: string = trimmed.substring(5).trim();
    if (payload.length === 0 || payload === '[DONE]') {
      return;
    }
    try {
      const parsed: LLMStreamChunkRaw = JSON.parse(payload) as LLMStreamChunkRaw;
      const choices: LLMStreamChoiceRaw[] | undefined = parsed.choices;
      if (choices === undefined || choices.length === 0) {
        return;
      }
      // 优先流式 delta；兼容个别服务端在 data 行内直接给 message
      const delta: LLMStreamDeltaRaw | undefined = choices[0].delta;
      if (delta !== undefined && delta.content !== undefined && delta.content.length > 0) {
        this.appendDelta(delta.content);
        return;
      }
      const message: LLMStreamDeltaRaw | undefined = choices[0].message;
      if (message !== undefined && message.content !== undefined && message.content.length > 0) {
        this.appendDelta(message.content);
      }
    } catch (e) {
      // 半包/脏行：忽略，等待后续块补齐
    }
  }

  private appendDelta(chunk: string): void {
    if (this.finished) {
      return;
    }
    this.fullText += chunk;
    this.handlers.onDelta(chunk);
  }

  private handleDataEnd(): void {
    if (this.finished) {
      return;
    }
    // 补齐残余半行
    if (this.lineBuffer.trim().length > 0) {
      this.consumeLine(this.lineBuffer);
      this.lineBuffer = '';
    }
    this.dataEnded = true;
    // 整体 JSON 回退：服务端忽略 stream:true 时（无任何 SSE 增量）尝试一次性解析
    if (this.fullText.length === 0 && this.rawBody.trim().length > 0) {
      this.tryParseFullJsonBody();
    }
    if (this.responseCode >= 200 && this.responseCode < 300) {
      this.finishSuccess();
      return;
    }
    if (this.responseCode >= 400) {
      this.fail(this.mapHttpStatus(this.responseCode));
      return;
    }
    // 响应码尚未返回：兜底等待（正常应在响应头阶段已回调），超时按成功收尾
    setTimeout(() => {
      if (!this.finished) {
        Log.w(LOG_TAG, 'STREAM code fallback fired');
        this.finishSuccess();
      }
    }, CODE_FALLBACK_WAIT_MS);
  }

  /** 无任何 SSE 增量时按整体 JSON 解析（choices[0].message.content） */
  private tryParseFullJsonBody(): void {
    try {
      const parsed: LLMFullResponseRaw = JSON.parse(this.rawBody) as LLMFullResponseRaw;
      const choices: LLMFullChoiceRaw[] | undefined = parsed.choices;
      if (choices !== undefined && choices.length > 0) {
        const message: LLMStreamDeltaRaw | undefined = choices[0].message;
        if (message !== undefined && message.content !== undefined && message.content.length > 0) {
          this.appendDelta(message.content);
        }
      }
    } catch (e) {
      // 非 JSON：保持空回复，由 finishSuccess 判定 EMPTY
    }
  }

  private handleCode(code: number): void {
    if (this.finished) {
      return;
    }
    this.responseCode = code;
    if (code >= 400) {
      Log.e(LOG_TAG, 'STREAM http error code=%{public}d', code);
      this.fail(this.mapHttpStatus(code));
      return;
    }
    if (this.dataEnded) {
      // 响应码晚于 dataEnd 到达的补收尾路径
      this.finishSuccess();
    }
  }

  private handleFailure(e: BusinessError): void {
    if (this.finished) {
      return;
    }
    Log.e(LOG_TAG, 'STREAM failed code=%{public}d msg=%{public}s', e.code, e.message);
    this.fail(this.mapTransportError(e));
  }

  /** HTTP 状态码 → 错误类别（401/403→AUTH；429→RATE_LIMIT；5xx→SERVER） */
  private mapHttpStatus(code: number): LLMErrorKind {
    if (code === 401 || code === 403) {
      return LLMErrorKind.AUTH;
    }
    if (code === 429) {
      return LLMErrorKind.RATE_LIMIT;
    }
    if (code >= 500) {
      return LLMErrorKind.SERVER;
    }
    // 其余 4xx（含 baseUrl 指向不存在的路径 404 等）按通用失败提示
    return LLMErrorKind.SERVER;
  }

  /** 传输层错误 → 错误类别（超时单独归类，其余按网络不可用） */
  private mapTransportError(e: BusinessError): LLMErrorKind {
    const message: string = e.message !== undefined ? e.message : '';
    if (e.code === 2300028 || message.indexOf('timed out') >= 0 || message.indexOf('timeout') >= 0) {
      return LLMErrorKind.TIMEOUT;
    }
    return LLMErrorKind.NETWORK;
  }

  private finishSuccess(): void {
    if (this.finished) {
      return;
    }
    if (this.fullText.length === 0) {
      this.fail(LLMErrorKind.EMPTY);
      return;
    }
    this.finished = true;
    Log.i(LOG_TAG, 'STREAM done len=%{public}d', this.fullText.length);
    this.handlers.onDone(this.fullText);
    this.cleanup();
  }

  private fail(kind: LLMErrorKind): void {
    if (this.finished) {
      return;
    }
    this.finished = true;
    Log.e(LOG_TAG, 'STREAM error kind=%{public}s', kind);
    this.handlers.onError(kind);
    this.cleanup();
  }

  private cleanup(): void {
    const request: http.HttpRequest | undefined = this.httpRequest;
    this.httpRequest = undefined;
    if (request === undefined) {
      return;
    }
    try {
      request.off('dataReceive');
      request.off('dataEnd');
      request.destroy();
    } catch (e) {
      // 清理失败不影响已定结果（fail/成功回调均已发出）
    }
  }
}

export class LLMService {
  /** 预设 id 列表（设置页选择器渲染顺序） */
  static presetIds(): string[] {
    return ['openai', 'deepseek', 'dashscope', 'moonshot', 'custom'];
  }

  /** 取预设（未知 id 返回 undefined；调用方回退 custom） */
  static getPreset(id: string): LLMProviderPreset | undefined {
    return LLM_PRESETS[id];
  }

  /**
   * 解析实际请求 baseUrl：custom 用用户填写值（去尾部 '/'）；
   * 其余预设取预设 baseUrl；未知预设视为 custom 语义（取填写值）。
   */
  static resolveBaseUrl(config: LLMProviderConfig): string {
    const preset: LLMProviderPreset | undefined = LLM_PRESETS[config.preset];
    if (preset !== undefined && config.preset !== 'custom') {
      return preset.baseUrl;
    }
    const custom: string = config.baseUrl.trim();
    if (custom.length === 0) {
      return '';
    }
    return custom.endsWith('/') ? custom.substring(0, custom.length - 1) : custom;
  }

  /** 解析实际请求 model：用户填写优先，缺省回退预设默认 model */
  static resolveModel(config: LLMProviderConfig): string {
    const filled: string = config.model.trim();
    if (filled.length > 0) {
      return filled;
    }
    const preset: LLMProviderPreset | undefined = LLM_PRESETS[config.preset];
    if (preset !== undefined) {
      return preset.defaultModel;
    }
    return '';
  }

  /**
   * 发起 OpenAI 兼容流式对话（/chat/completions + Bearer + stream:true）。
   * 返回取消句柄（同步可用）：cancel() 中断请求并停止消费流。
   * 前置校验失败（Key/baseUrl/model 缺失）不构造请求，直接 onError。
   */
  static streamChat(config: LLMProviderConfig, apiKey: string, history: LLMChatTurn[],
    handlers: LLMStreamHandlers, systemPrompt: string = ''): LLMStreamSession {
    const session: LLMStreamSession = new LLMStreamSession();
    session.begin(config, apiKey, history, systemPrompt, handlers);
    return session;
  }
}
