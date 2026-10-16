/**
 * ============================================================================
 * AIChatManager — AI 会话/消息状态管理与本地持久化
 * ============================================================================
 *
 * 【既有契约（保持不变）】createConversation(providerConfig?) /
 *   deleteConversation(id) / addMessage / updateLastMessage /
 *   getActiveConversation / getConversations / setActiveConversation。
 *   （Phase4SelfTest 依赖 create/delete 签名，勿改。）
 *
 * 【本特性扩展（ai-chat）】
 *   - 持久化：StorageKeys.AI_CONVERSATIONS（偏好 JSON）；每次增删改后异步
 *     落盘（失败记日志不抛）；loadConversations() 供页面启动恢复。
 *   - 消息状态：AIChatMessage 扩展 status（ok/streaming/aborted/error）；
 *     读取旧数据（无 status 字段）时归一为 'ok' —— 结构向后兼容。
 *   - 会话标题：首条用户消息摘要（超长截断），替代默认标题。
 * ============================================================================
 */
import { Conversation, ChatMessage, AIProviderConfig, ToolTrace } from '../domain/AIAgentTypes';
import { StateManager } from './StateManager';
import { generateUUID } from '../utils/CryptoUtils';
import { StorageKeys } from '../storage/StorageKeys';
import { PreferencesStorage } from '../storage/PreferencesStorage';
import { Log } from '../utils/Logger';

const LOG_TAG: string = 'AIChatMgr';
/** 会话标题摘要最大长度（字符） */
const TITLE_MAX_LEN: number = 20;
/** createConversation 的默认占位标题（首条用户消息到达后替换为摘要） */
const DEFAULT_TITLE: string = 'New Conversation';

/** 消息状态：正常 / 生成中 / 已中断 / 失败 */
export class AIChatMessageStatus {
  static readonly OK: string = 'ok';
  static readonly STREAMING: string = 'streaming';
  static readonly ABORTED: string = 'aborted';
  static readonly ERROR: string = 'error';
}

/**
 * 带状态的消息（继承领域模型以兼容既有 ChatMessage 消费方）：
 * status 仅为本特性扩展字段，旧数据/其他消费方不感知。
 */
export class AIChatMessage extends ChatMessage {
  status: string = AIChatMessageStatus.OK;
}

/** 持久化消息原始形态（JSON 读入断言；字段可能缺失，读取后归一） */
class ChatMessageRaw {
  id?: string;
  role?: string;
  content?: string;
  timestamp?: string;
  status?: string;
  traces?: ToolTraceRaw[];
}

/** 持久化工具轨迹原始形态（JSON 读入断言；字段可能缺失，读取后归一） */
class ToolTraceRaw {
  callId?: string;
  name?: string;
  params?: string;
  result?: string;
  timestamp?: string;
  success?: boolean;
  title?: string;
  status?: string;
  detail?: string;
}

/** 持久化会话原始形态（JSON 读入断言；字段可能缺失，读取后归一） */
class ConversationRaw {
  id?: string;
  title?: string;
  createdAt?: string;
  updatedAt?: string;
  messages?: ChatMessageRaw[];
}

export class AIChatManager {
  /**
   * 是否已从持久化恢复（loadConversations 完成前为 false）。
   * 启动期存在"先于恢复的临时增删"（如 Phase4SelfTest 的 create/delete）：
   * 若此时落盘会以空/临时列表覆盖用户既有会话，故在恢复前跳过写入。
   */
  private static loaded: boolean = false;

  // ============================================================
  // 持久化（StorageKeys.AI_CONVERSATIONS）
  // ============================================================

  /**
   * 启动恢复：读取持久化会话并归一（旧数据无 status → 'ok'；
   * 缺失字段回退安全值）；空/损坏数据保持空列表。失败记日志不抛。
   */
  static async loadConversations(): Promise<void> {
    let rawList: ConversationRaw[] | undefined = undefined;
    try {
      rawList = await PreferencesStorage.getJson<ConversationRaw[]>(StorageKeys.AI_CONVERSATIONS);
    } catch (e) {
      Log.e(LOG_TAG, 'CONV load failed');
      AIChatManager.loaded = true;
      return;
    }
    if (rawList === undefined || !Array.isArray(rawList)) {
      Log.i(LOG_TAG, 'CONV load none');
      AIChatManager.loaded = true;
      return;
    }
    const restored: Conversation[] = [];
    for (let i: number = 0; i < rawList.length; i++) {
      const conv: Conversation | undefined = AIChatManager.normalizeConversation(rawList[i]);
      if (conv !== undefined) {
        restored.push(conv);
      }
    }
    StateManager.conversations = restored;
    StateManager.activeConversationId = restored.length > 0 ? restored[0].id : '';
    AIChatManager.loaded = true;
    Log.i(LOG_TAG, 'CONV loaded count=%{public}d', restored.length);
  }

  /** 单条原始会话 → 领域模型（向后兼容：缺 status 归一 'ok'；无 id 丢弃） */
  private static normalizeConversation(raw: ConversationRaw): Conversation | undefined {
    const id: string | undefined = raw.id;
    if (id === undefined || id.length === 0) {
      return undefined;
    }
    const conv: Conversation = new Conversation();
    conv.id = id;
    conv.title = raw.title !== undefined ? raw.title : DEFAULT_TITLE;
    conv.createdAt = raw.createdAt !== undefined ? raw.createdAt : '';
    conv.updatedAt = raw.updatedAt !== undefined ? raw.updatedAt : '';
    const rawMsgs: ChatMessageRaw[] | undefined = raw.messages;
    if (rawMsgs !== undefined) {
      for (let i: number = 0; i < rawMsgs.length; i++) {
        const rawMsg: ChatMessageRaw = rawMsgs[i];
        const msg: AIChatMessage = new AIChatMessage();
        msg.id = rawMsg.id !== undefined ? rawMsg.id : generateUUID();
        msg.role = rawMsg.role !== undefined ? rawMsg.role : 'user';
        msg.content = rawMsg.content !== undefined ? rawMsg.content : '';
        msg.timestamp = rawMsg.timestamp !== undefined ? rawMsg.timestamp : '';
        msg.status = rawMsg.status !== undefined ? rawMsg.status : AIChatMessageStatus.OK;
        const rawTraces: ToolTraceRaw[] | undefined = rawMsg.traces;
        if (rawTraces !== undefined && Array.isArray(rawTraces)) {
          for (let k: number = 0; k < rawTraces.length; k++) {
            const rt: ToolTraceRaw = rawTraces[k];
            const trace: ToolTrace = new ToolTrace();
            trace.callId = typeof rt.callId === 'string' ? rt.callId : '';
            trace.name = typeof rt.name === 'string' ? rt.name : '';
            trace.params = typeof rt.params === 'string' ? rt.params : '';
            trace.result = typeof rt.result === 'string' ? rt.result : '';
            trace.timestamp = typeof rt.timestamp === 'string' ? rt.timestamp : '';
            trace.success = rt.success === true;
            trace.title = typeof rt.title === 'string' ? rt.title : '';
            trace.status = typeof rt.status === 'string' ? rt.status : '';
            trace.detail = typeof rt.detail === 'string' ? rt.detail : '';
            msg.traces.push(trace);
          }
        }
        conv.messages.push(msg);
      }
    }
    return conv;
  }

  /** 异步落盘全部会话（失败记日志不抛，调用方可不 await） */
  static async saveConversations(): Promise<void> {
    if (!AIChatManager.loaded) {
      // 尚未从持久化恢复：跳过写入，避免启动自检等早期临时增删清空既有会话
      Log.w(LOG_TAG, 'CONV save skipped (not loaded)');
      return;
    }
    try {
      await PreferencesStorage.setJson<Conversation[]>(StorageKeys.AI_CONVERSATIONS,
        StateManager.conversations);
      Log.i(LOG_TAG, 'CONV saved count=%{public}d', StateManager.conversations.length);
    } catch (e) {
      Log.e(LOG_TAG, 'CONV save failed');
    }
  }

  // ============================================================
  // 会话 CRUD（既有签名保持不变）
  // ============================================================

  static createConversation(providerConfig?: AIProviderConfig): Conversation {
    const conv: Conversation = new Conversation();
    conv.id = generateUUID();
    conv.title = DEFAULT_TITLE;
    conv.createdAt = new Date().toISOString();
    conv.updatedAt = conv.createdAt;
    if (providerConfig !== undefined) {
      conv.providerConfig = providerConfig;
    }
    StateManager.conversations = [conv].concat(StateManager.conversations);
    StateManager.activeConversationId = conv.id;
    AIChatManager.saveConversations();
    return conv;
  }

  static deleteConversation(id: string): void {
    const kept: Conversation[] = [];
    for (let i: number = 0; i < StateManager.conversations.length; i++) {
      if (StateManager.conversations[i].id !== id) {
        kept.push(StateManager.conversations[i]);
      }
    }
    StateManager.conversations = kept;
    if (StateManager.activeConversationId === id) {
      StateManager.activeConversationId = kept.length > 0 ? kept[0].id : '';
    }
    AIChatManager.saveConversations();
  }

  static getActiveConversation(): Conversation | undefined {
    for (let i: number = 0; i < StateManager.conversations.length; i++) {
      if (StateManager.conversations[i].id === StateManager.activeConversationId) {
        return StateManager.conversations[i];
      }
    }
    return undefined;
  }

  static getConversations(): Conversation[] {
    return StateManager.conversations;
  }

  static setActiveConversation(id: string): void {
    StateManager.activeConversationId = id;
  }

  // ============================================================
  // 消息 CRUD（扩展：状态 + 标题摘要）
  // ============================================================

  /** 追加消息（返回带 status 的扩展消息）；首条用户消息同步生成会话标题摘要 */
  static addMessage(conversationId: string, role: string, content: string): ChatMessage {
    const msg: AIChatMessage = new AIChatMessage();
    msg.id = generateUUID();
    msg.role = role;
    msg.content = content;
    msg.timestamp = new Date().toISOString();
    msg.status = AIChatMessageStatus.OK;
    for (let i: number = 0; i < StateManager.conversations.length; i++) {
      const conv: Conversation = StateManager.conversations[i];
      if (conv.id === conversationId) {
        conv.messages.push(msg);
        conv.updatedAt = msg.timestamp;
        // 会话标题取首条用户消息摘要（默认占位标题尚未被替换时）
        if (role === 'user' && (conv.title === DEFAULT_TITLE || conv.title.length === 0)) {
          conv.title = AIChatManager.summarizeTitle(content);
        }
        break;
      }
    }
    AIChatManager.saveConversations();
    return msg;
  }

  /** 更新指定消息状态（ok/streaming/aborted/error）；未找到静默忽略 */
  static updateMessageStatus(conversationId: string, messageId: string, status: string): void {
    const msg: ChatMessage | undefined = AIChatManager.findMessage(conversationId, messageId);
    if (msg instanceof AIChatMessage) {
      msg.status = status;
    }
    AIChatManager.saveConversations();
  }

  /**
   * 将工具轨迹关联到指定消息（US3：对话内渲染轨迹卡片）。
   * 以副本写入避免外部数组后续变更影响持久化；未找到消息静默忽略。
   */
  static attachTraces(conversationId: string, messageId: string, traces: ToolTrace[]): void {
    const msg: ChatMessage | undefined = AIChatManager.findMessage(conversationId, messageId);
    if (msg !== undefined) {
      msg.traces = traces.slice();
    }
    AIChatManager.saveConversations();
  }

  static updateLastMessage(conversationId: string, content: string): void {
    for (let i: number = 0; i < StateManager.conversations.length; i++) {
      if (StateManager.conversations[i].id === conversationId) {
        const msgs: ChatMessage[] = StateManager.conversations[i].messages;
        if (msgs.length > 0) {
          msgs[msgs.length - 1].content = content;
        }
        break;
      }
    }
  }

  /** 首条用户消息摘要：去首尾空白、压缩换行、超长截断（向后兼容旧标题） */
  private static summarizeTitle(content: string): string {
    const flat: string = content.trim().replace(/\s+/g, ' ');
    if (flat.length === 0) {
      return DEFAULT_TITLE;
    }
    if (flat.length <= TITLE_MAX_LEN) {
      return flat;
    }
    return flat.substring(0, TITLE_MAX_LEN) + '…';
  }

  private static findMessage(conversationId: string, messageId: string): ChatMessage | undefined {
    for (let i: number = 0; i < StateManager.conversations.length; i++) {
      const conv: Conversation = StateManager.conversations[i];
      if (conv.id !== conversationId) {
        continue;
      }
      for (let j: number = 0; j < conv.messages.length; j++) {
        if (conv.messages[j].id === messageId) {
          return conv.messages[j];
        }
      }
    }
    return undefined;
  }
}
