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
/** 逐轮流式补全的取消轮询间隔（ms；数据静默期兜底响应停止操作） */
const ROUND_CANCEL_POLL_MS: number = 500;

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

/** 非流式带工具响应原始模型（JSON.parse 后一次性断言；字段可能缺失） */
class LLMToolsResponseRaw {
  choices?: LLMToolsChoiceRaw[];
}

class LLMToolsChoiceRaw {
  message?: LLMToolsMessageRaw;
}

class LLMToolsMessageRaw {
  content?: string;
  tool_calls?: LLMToolsCallRaw[];
}

class LLMToolsCallRaw {
  id?: string;
  function?: LLMToolsCallFunctionRaw;
}

class LLMToolsCallFunctionRaw {
  name?: string;
  arguments?: string;
}

/** 逐轮流式 SSE data 行原始模型（JSON.parse 后一次性断言；字段可能缺失） */
class LLMRoundChunkRaw {
  choices?: LLMRoundChoiceRaw[];
}

class LLMRoundChoiceRaw {
  delta?: LLMRoundDeltaRaw;
  message?: LLMRoundMessageRaw;
}

class LLMRoundDeltaRaw {
  content?: string;
  tool_calls?: LLMRoundToolCallDeltaRaw[];
}

/** delta.tool_calls[] 增量片段（id/function.name/function.arguments 均可能分片） */
class LLMRoundToolCallDeltaRaw {
  index?: number;
  id?: string;
  function?: LLMToolsCallFunctionRaw;
}

/** data 行内整体 message（个别服务端兼容形态；content/tool_calls 均为完整值） */
class LLMRoundMessageRaw {
  content?: string;
  tool_calls?: LLMToolsCallRaw[];
}

/** 整体 JSON 响应原始模型（服务端忽略 stream:true 时的回退） */
class LLMRoundFullResponseRaw {
  choices?: LLMRoundFullChoiceRaw[];
}

class LLMRoundFullChoiceRaw {
  message?: LLMRoundMessageRaw;
}

/** 流式 tool_calls 增量按 index 汇总的累积器（id/name/args 为分片拼接结果） */
class LLMRoundToolCallAcc {
  index: number = 0;
  id: string = '';
  name: string = '';
  args: string = '';
}

/** 非流式工具补全：模型返回的单个工具调用 */
export class LLMToolCall {
  id: string = '';
  name: string = '';
  /** 参数 JSON 文本（原样回传模型，未解析） */
  arguments: string = '{}';
}

/**
 * 带工具补全的结果（非流式 chatCompleteWithTools 与流式逐轮
 * streamRoundWithTools 共用）：
 * - ok=true：content/toolCalls 为模型输出（两者可能同时存在）
 * - ok=false：kind 为错误类别（沿用 LLMErrorKind 归一），detail 供日志
 * - cancelled=true：流式轮次被取消（用户停止/离开；仅 streamRoundWithTools 产出）
 */
export class LLMToolsOutcome {
  ok: boolean = false;
  kind: LLMErrorKind = LLMErrorKind.SERVER;
  detail: string = '';
  content: string = '';
  toolCalls: LLMToolCall[] = [];
  /** 流式轮次被取消（不抛；已收增量由调用方决定保留/丢弃） */
  cancelled: boolean = false;
}

/**
 * 逐轮流式补全选项（agent 循环专用；T019/FR-015）：
 * content 增量经 onContentDelta 外发；该轮出现 tool_calls 片段后停止外发
 * （中间工具轮正文不外发，正文仍完整累积供回灌模型）。
 */
export class LLMRoundStreamOptions {
  /** content 增量回调（已解码 UTF-8；仅该轮未出现 tool_calls 片段时回调） */
  onContentDelta: (chunk: string) => void = (chunk: string): void => {};
  /** 取消信号（数据到达与定时轮询中检查；取消即中断请求并以 cancelled 收尾） */
  isCancelled: (() => boolean) | undefined = undefined;
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
    return LLMService.mapHttpErrorKind(code);
  }

  /** 传输层错误 → 错误类别（超时单独归类，其余按网络不可用） */
  private mapTransportError(e: BusinessError): LLMErrorKind {
    return LLMService.mapTransportErrorKind(e);
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

/**
 * 逐轮流式补全会话（agent 循环专用；T019/FR-015/SC-009）：
 * - 与既有 LLMStreamSession 的差异：请求体携带 tools/tool_choice（原始
 *   JSON 文本），SSE 解析在 content 增量之外【同时累积 tool_calls 增量】
 *   （OpenAI 兼容 choices[].delta.tool_calls[]，按 index 汇总 id/
 *   function.name/function.arguments 分片），轮次结束以 LLMToolsOutcome
 *   （Promise resolve）返回累积 content 与 toolCalls。
 * - content 增量经 options.onContentDelta 外发；该轮出现 tool_calls 片段
 *   后停止外发（中间工具轮正文不外发；正文仍完整累积回灌模型）。
 * - 取消：isCancelled 在数据到达与定时轮询中检查，取消即销毁请求并以
 *   cancelled=true 收尾（不抛、不再回调）。
 * - 兼容服务端忽略 stream:true 返回整体 JSON（含 message.tool_calls）。
 * - 错误按 LLMErrorKind 归一（ok=false）；鉴权头不进日志。
 */
export class LLMRoundStreamSession {
  private httpRequest: http.HttpRequest | undefined = undefined;
  private options: LLMRoundStreamOptions = new LLMRoundStreamOptions();
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
  /** 跨块行缓冲（SSE 事件可能被 TCP 分段截断） */
  private lineBuffer: string = '';
  private fullText: string = '';
  /** 原始响应体积留档（仅用于整体 JSON 回退解析与日志长度） */
  private rawBody: string = '';
  private responseCode: number = -1;
  private dataEnded: boolean = false;
  private finished: boolean = false;
  /** 该轮已出现 tool_calls 片段（其后 content 增量不再外发） */
  private toolCallSeen: boolean = false;
  /** tool_calls 增量按 index 汇总的累积器 */
  private toolCallAccs: LLMRoundToolCallAcc[] = [];
  private resolver: ((outcome: LLMToolsOutcome) => void) | undefined = undefined;
  /** 静默期取消轮询句柄（<0 表示未启动） */
  private cancelPoller: number = -1;

  /**
   * 发起逐轮流式补全：轮次结束时 Promise resolve 累积结果
   * （ok=true 携带 content/toolCalls；ok=false 携带错误类别；取消 cancelled=true）。
   */
  begin(config: LLMProviderConfig, apiKey: string, messagesJson: string, toolsJson: string,
    options: LLMRoundStreamOptions): Promise<LLMToolsOutcome> {
    this.options = options;
    return new Promise<LLMToolsOutcome>((resolve: (outcome: LLMToolsOutcome) => void) => {
      this.resolver = resolve;
      const baseUrl: string = LLMService.resolveBaseUrl(config);
      const model: string = LLMService.resolveModel(config);
      // 前置校验失败不构造请求、不触网
      if (apiKey.length === 0) {
        this.fail(LLMErrorKind.NOT_CONFIGURED);
        return;
      }
      if (baseUrl.length === 0 || model.length === 0 || messagesJson.length === 0) {
        this.fail(LLMErrorKind.BAD_BASE_URL);
        return;
      }

      // 请求体以原始 JSON 文本提交（messages/tools 由调用方构造，含 tool_calls 轮次）
      let bodyText: string = '{"model":' + JSON.stringify(model) +
        ',"stream":true,"messages":' + messagesJson;
      if (toolsJson.length > 0) {
        bodyText += ',"tools":' + toolsJson + ',"tool_choice":"auto"';
      }
      bodyText += '}';

      // 鉴权头仅进入请求，不进入任何日志
      const header: Record<string, string> = {
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'Authorization': 'Bearer ' + apiKey,
      };
      const httpOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: header,
        extraData: bodyText,
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
      this.startCancelPoller();
      Log.i(LOG_TAG, 'ROUND start preset=%{public}s model=%{public}s hasTools=%{public}s',
        config.preset, model, toolsJson.length > 0 ? 'true' : 'false');
      request.requestInStream(baseUrl + '/chat/completions', httpOptions)
        .then((code: number) => {
          this.handleCode(code);
        })
        .catch((e: BusinessError) => {
          this.handleFailure(e);
        });
    });
  }

  // ============================================================
  // 内部：SSE 解析与状态机（content + tool_calls 双累积）
  // ============================================================

  private handleChunk(data: ArrayBuffer): void {
    if (this.finished) {
      return;
    }
    if (this.isCancelledNow()) {
      this.cancelByUser();
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

  /** 解析单行 SSE：`data: {...}` 增量（content 外发 + tool_calls 累积） */
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
      const parsed: LLMRoundChunkRaw = JSON.parse(payload) as LLMRoundChunkRaw;
      const choices: LLMRoundChoiceRaw[] | undefined = parsed.choices;
      if (choices === undefined || choices.length === 0) {
        return;
      }
      // 优先流式 delta；兼容个别服务端在 data 行内直接给整体 message
      const delta: LLMRoundDeltaRaw | undefined = choices[0].delta;
      if (delta !== undefined) {
        this.consumeDeltaToolCalls(delta.tool_calls);
        if (delta.content !== undefined && delta.content.length > 0) {
          this.appendContent(delta.content);
        }
        return;
      }
      const message: LLMRoundMessageRaw | undefined = choices[0].message;
      if (message !== undefined) {
        this.consumeMessageToolCalls(message.tool_calls);
        if (message.content !== undefined && message.content.length > 0) {
          this.appendContent(message.content);
        }
      }
    } catch (e) {
      // 半包/脏行：忽略，等待后续块补齐
    }
  }

  /** delta.tool_calls[] 增量片段 → 按 index 汇总（id/name/arguments 分片拼接） */
  private consumeDeltaToolCalls(calls: LLMRoundToolCallDeltaRaw[] | undefined): void {
    if (calls === undefined || calls.length === 0) {
      return;
    }
    this.toolCallSeen = true;
    for (let i: number = 0; i < calls.length; i++) {
      const frag: LLMRoundToolCallDeltaRaw = calls[i];
      const idx: number = frag.index !== undefined ? frag.index : 0;
      let acc: LLMRoundToolCallAcc | undefined = undefined;
      for (let j: number = 0; j < this.toolCallAccs.length; j++) {
        if (this.toolCallAccs[j].index === idx) {
          acc = this.toolCallAccs[j];
          break;
        }
      }
      if (acc === undefined) {
        acc = new LLMRoundToolCallAcc();
        acc.index = idx;
        this.toolCallAccs.push(acc);
      }
      if (frag.id !== undefined && frag.id.length > 0) {
        acc.id += frag.id;
      }
      const fn: LLMToolsCallFunctionRaw | undefined = frag.function;
      if (fn !== undefined) {
        if (fn.name !== undefined && fn.name.length > 0) {
          acc.name += fn.name;
        }
        if (fn.arguments !== undefined) {
          acc.args += fn.arguments;
        }
      }
    }
  }

  /** 整体 message.tool_calls[]（非流式形态）→ 直接成调用 */
  private consumeMessageToolCalls(calls: LLMToolsCallRaw[] | undefined): void {
    if (calls === undefined || calls.length === 0) {
      return;
    }
    this.toolCallSeen = true;
    for (let i: number = 0; i < calls.length; i++) {
      const call: LLMToolsCallRaw = calls[i];
      const fn: LLMToolsCallFunctionRaw | undefined = call.function;
      if (fn === undefined || fn.name === undefined || fn.name.length === 0) {
        continue;
      }
      const acc: LLMRoundToolCallAcc = new LLMRoundToolCallAcc();
      acc.index = this.toolCallAccs.length;
      acc.id = call.id !== undefined && call.id.length > 0 ? call.id : '';
      acc.name = fn.name;
      acc.args = fn.arguments !== undefined ? fn.arguments : '';
      this.toolCallAccs.push(acc);
    }
  }

  /** content 完整累积；该轮未出现 tool_calls 片段时同步外发增量 */
  private appendContent(chunk: string): void {
    this.fullText += chunk;
    if (!this.toolCallSeen) {
      this.options.onContentDelta(chunk);
    }
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
    // 整体 JSON 回退：服务端忽略 stream:true 时（无任何 SSE 增量）一次性解析
    if (this.fullText.length === 0 && this.toolCallAccs.length === 0 && this.rawBody.trim().length > 0) {
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
        Log.w(LOG_TAG, 'ROUND code fallback fired');
        this.finishSuccess();
      }
    }, CODE_FALLBACK_WAIT_MS);
  }

  /** 无任何 SSE 增量时按整体 JSON 解析（choices[0].message 含 content/tool_calls） */
  private tryParseFullJsonBody(): void {
    try {
      const parsed: LLMRoundFullResponseRaw = JSON.parse(this.rawBody) as LLMRoundFullResponseRaw;
      const choices: LLMRoundFullChoiceRaw[] | undefined = parsed.choices;
      if (choices === undefined || choices.length === 0) {
        return;
      }
      const message: LLMRoundMessageRaw | undefined = choices[0].message;
      if (message === undefined) {
        return;
      }
      this.consumeMessageToolCalls(message.tool_calls);
      if (message.content !== undefined && message.content.length > 0) {
        this.appendContent(message.content);
      }
    } catch (e) {
      // 非 JSON：保持空结果，由 finishSuccess 判定 EMPTY
    }
  }

  private handleCode(code: number): void {
    if (this.finished) {
      return;
    }
    this.responseCode = code;
    if (code >= 400) {
      Log.e(LOG_TAG, 'ROUND http error code=%{public}d', code);
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
    Log.e(LOG_TAG, 'ROUND failed code=%{public}d msg=%{public}s', e.code, e.message);
    this.fail(this.mapTransportError(e));
  }

  private mapHttpStatus(code: number): LLMErrorKind {
    return LLMService.mapHttpErrorKind(code);
  }

  private mapTransportError(e: BusinessError): LLMErrorKind {
    return LLMService.mapTransportErrorKind(e);
  }

  /** 轮次正常收尾：累积 content 与 toolCalls 一并产出 */
  private finishSuccess(): void {
    if (this.finished) {
      return;
    }
    const outcome: LLMToolsOutcome = new LLMToolsOutcome();
    for (let i: number = 0; i < this.toolCallAccs.length; i++) {
      const acc: LLMRoundToolCallAcc = this.toolCallAccs[i];
      if (acc.name.length === 0) {
        // 无名称的残缺片段（如仅 index 的空帧）：丢弃
        continue;
      }
      const tc: LLMToolCall = new LLMToolCall();
      tc.id = acc.id.length > 0 ? acc.id : 'call_' + i;
      tc.name = acc.name;
      tc.arguments = acc.args.length > 0 ? acc.args : '{}';
      outcome.toolCalls.push(tc);
    }
    outcome.content = this.fullText;
    this.finished = true;
    if (outcome.content.length === 0 && outcome.toolCalls.length === 0) {
      outcome.ok = false;
      outcome.kind = LLMErrorKind.EMPTY;
      outcome.detail = 'empty round';
      Log.e(LOG_TAG, 'ROUND empty');
      this.resolveOutcome(outcome);
      this.cleanup();
      return;
    }
    outcome.ok = true;
    Log.i(LOG_TAG, 'ROUND done content_len=%{public}d tool_calls=%{public}d',
      outcome.content.length, outcome.toolCalls.length);
    this.resolveOutcome(outcome);
    this.cleanup();
  }

  private fail(kind: LLMErrorKind): void {
    if (this.finished) {
      return;
    }
    this.finished = true;
    const outcome: LLMToolsOutcome = new LLMToolsOutcome();
    outcome.ok = false;
    outcome.kind = kind;
    const clipped: string = this.rawBody.trim();
    outcome.detail = clipped.length > 200 ? clipped.substring(0, 200) : clipped;
    Log.e(LOG_TAG, 'ROUND error kind=%{public}s', kind);
    this.resolveOutcome(outcome);
    this.cleanup();
  }

  /** 用户取消：销毁请求并以 cancelled 结果收尾（不抛；已收增量不外发） */
  private cancelByUser(): void {
    if (this.finished) {
      return;
    }
    this.finished = true;
    const outcome: LLMToolsOutcome = new LLMToolsOutcome();
    outcome.ok = false;
    outcome.cancelled = true;
    Log.i(LOG_TAG, 'ROUND cancelled content_len=%{public}d', this.fullText.length);
    this.resolveOutcome(outcome);
    this.cleanup();
  }

  /** 静默期取消兜底：数据长时间不达时仍可及时响应停止操作 */
  private startCancelPoller(): void {
    if (this.options.isCancelled === undefined) {
      return;
    }
    this.cancelPoller = setInterval(() => {
      if (!this.finished && this.isCancelledNow()) {
        this.cancelByUser();
      }
    }, ROUND_CANCEL_POLL_MS);
  }

  private isCancelledNow(): boolean {
    const fn: (() => boolean) | undefined = this.options.isCancelled;
    return fn !== undefined && fn();
  }

  private resolveOutcome(outcome: LLMToolsOutcome): void {
    const resolver: ((outcome: LLMToolsOutcome) => void) | undefined = this.resolver;
    this.resolver = undefined;
    if (resolver !== undefined) {
      resolver(outcome);
    }
  }

  private cleanup(): void {
    if (this.cancelPoller >= 0) {
      clearInterval(this.cancelPoller);
      this.cancelPoller = -1;
    }
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
      // 清理失败不影响已定结果（结果回调均已发出）
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

  /**
   * 逐轮流式带工具补全（agent 循环专用；T019/FR-015/SC-009）：
   * - 每轮以 SSE 流式请求（stream:true + tools + tool_choice:'auto'），
   *   请求体以【原始 JSON 文本】提交（messages/tools 由调用方构造）。
   * - SSE 解析同时累积 content 与 tool_calls 增量（按 index 汇总）；
   *   content 增量经 options.onContentDelta 回调（该轮出现 tool_calls
   *   片段后停止回调——中间工具轮正文不外发）。
   * - 轮次结束以 LLMToolsOutcome resolve（ok=true 携带累积 content/toolCalls）；
   *   错误按 LLMErrorKind 归一（ok=false），取消以 cancelled=true 收尾（均不抛）。
   * - 兼容服务端忽略 stream:true 返回整体 JSON（含 message.tool_calls）。
   * - 不改变既有 streamChat 的签名与行为。
   */
  static streamRoundWithTools(config: LLMProviderConfig, apiKey: string,
    messagesJson: string, toolsJson: string, options: LLMRoundStreamOptions): Promise<LLMToolsOutcome> {
    const session: LLMRoundStreamSession = new LLMRoundStreamSession();
    return session.begin(config, apiKey, messagesJson, toolsJson, options);
  }

  /** HTTP 状态码 → 错误类别（401/403→AUTH；429→RATE_LIMIT；其余非 2xx→SERVER） */
  static mapHttpErrorKind(code: number): LLMErrorKind {
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
  static mapTransportErrorKind(e: BusinessError): LLMErrorKind {
    const message: string = e.message !== undefined ? e.message : '';
    if (e.code === 2300028 || message.indexOf('timed out') >= 0 || message.indexOf('timeout') >= 0) {
      return LLMErrorKind.TIMEOUT;
    }
    return LLMErrorKind.NETWORK;
  }

  /** 响应体 → 文本（string 直取；ArrayBuffer 解码；其余 JSON.stringify 兜底） */
  private static bodyToString(result: string | Object | ArrayBuffer): string {
    if (typeof result === 'string') {
      return result as string;
    }
    if (result instanceof ArrayBuffer) {
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
      return decoder.decodeToString(new Uint8Array(result));
    }
    try {
      return JSON.stringify(result);
    } catch (e) {
      return '';
    }
  }

  /** 截断错误详情（仅用于日志/诊断，绝不含鉴权头与 API Key） */
  private static clipDetail(text: string): string {
    const trimmed: string = text.trim();
    return trimmed.length > 200 ? trimmed.substring(0, 200) : trimmed;
  }

  /**
   * 非流式带工具补全（agent 循环专用；对齐参考实现 runAgent 的
   * postChatCompletion 语义）：
   * - 请求体以【原始 JSON 文本】提交：messages/tools 由调用方构造为 JSON
   *   片段（含 tool_calls / tool_call_id 等无法用强类型类表达的轮次），
   *   本方法仅拼装 model/stream:false/tool_choice:'auto'。
   * - 解析返回 content 与 toolCalls；错误按 LLMErrorKind 归一。
   * - 鉴权头仅进入请求，不进入任何日志（FR-015）。
   */
  static async chatCompleteWithTools(config: LLMProviderConfig, apiKey: string,
    messagesJson: string, toolsJson: string): Promise<LLMToolsOutcome> {
    const outcome: LLMToolsOutcome = new LLMToolsOutcome();
    const baseUrl: string = LLMService.resolveBaseUrl(config);
    const model: string = LLMService.resolveModel(config);
    // 前置校验失败不构造请求、不触网（FR-008 加固）
    if (apiKey.length === 0) {
      outcome.kind = LLMErrorKind.NOT_CONFIGURED;
      return outcome;
    }
    if (baseUrl.length === 0 || model.length === 0 || messagesJson.length === 0) {
      outcome.kind = LLMErrorKind.BAD_BASE_URL;
      return outcome;
    }

    let bodyText: string = '{"model":' + JSON.stringify(model) +
      ',"stream":false,"messages":' + messagesJson;
    if (toolsJson.length > 0) {
      bodyText += ',"tools":' + toolsJson + ',"tool_choice":"auto"';
    }
    bodyText += '}';

    const header: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + apiKey,
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: header,
      extraData: bodyText,
      connectTimeout: CONNECT_TIMEOUT_MS,
      readTimeout: READ_TIMEOUT_MS,
      usingCache: false,
    };

    const request: http.HttpRequest = http.createHttp();
    try {
      Log.i(LOG_TAG, 'TOOLS start preset=%{public}s model=%{public}s hasTools=%{public}s',
        config.preset, model, toolsJson.length > 0 ? 'true' : 'false');
      const resp: http.HttpResponse = await request.request(baseUrl + '/chat/completions', options);
      const code: number = resp.responseCode;
      const body: string = LLMService.bodyToString(resp.result);
      if (code < 200 || code >= 300) {
        Log.e(LOG_TAG, 'TOOLS http error code=%{public}d len=%{public}d', code, body.length);
        outcome.kind = LLMService.mapHttpErrorKind(code);
        outcome.detail = LLMService.clipDetail(body);
        return outcome;
      }
      const parsed: LLMToolsResponseRaw = JSON.parse(body) as LLMToolsResponseRaw;
      const choices: LLMToolsChoiceRaw[] | undefined = parsed.choices;
      if (choices === undefined || choices.length === 0) {
        outcome.kind = LLMErrorKind.EMPTY;
        outcome.detail = 'no choices';
        return outcome;
      }
      const message: LLMToolsMessageRaw | undefined = choices[0].message;
      if (message === undefined) {
        outcome.kind = LLMErrorKind.EMPTY;
        outcome.detail = 'no message';
        return outcome;
      }
      if (typeof message.content === 'string') {
        outcome.content = message.content;
      }
      const calls: LLMToolsCallRaw[] | undefined = message.tool_calls;
      if (calls !== undefined) {
        for (let i: number = 0; i < calls.length; i++) {
          const call: LLMToolsCallRaw = calls[i];
          const fn: LLMToolsCallFunctionRaw | undefined = call.function;
          if (fn === undefined || typeof fn.name !== 'string' || fn.name.length === 0) {
            continue;
          }
          const tc: LLMToolCall = new LLMToolCall();
          tc.id = typeof call.id === 'string' && call.id.length > 0 ? call.id : 'call_' + i;
          tc.name = fn.name;
          tc.arguments = typeof fn.arguments === 'string' ? fn.arguments : '{}';
          outcome.toolCalls.push(tc);
        }
      }
      if (outcome.content.length === 0 && outcome.toolCalls.length === 0) {
        outcome.kind = LLMErrorKind.EMPTY;
        outcome.detail = 'empty completion';
        return outcome;
      }
      outcome.ok = true;
      Log.i(LOG_TAG, 'TOOLS done content_len=%{public}d tool_calls=%{public}d',
        outcome.content.length, outcome.toolCalls.length);
      return outcome;
    } catch (e) {
      // JSON 解析失败或传输层错误
      const err: BusinessError = e as BusinessError;
      if (typeof err.code === 'number') {
        Log.e(LOG_TAG, 'TOOLS failed code=%{public}d msg=%{public}s', err.code, err.message);
        outcome.kind = LLMService.mapTransportErrorKind(err);
        outcome.detail = LLMService.clipDetail(err.message !== undefined ? err.message : '');
      } else {
        Log.e(LOG_TAG, 'TOOLS parse failed');
        outcome.kind = LLMErrorKind.SERVER;
        outcome.detail = 'response parse failed';
      }
      return outcome;
    } finally {
      request.destroy();
    }
  }
}
