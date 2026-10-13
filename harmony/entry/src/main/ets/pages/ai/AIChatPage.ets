/**
 * ============================================================================
 * AIChatPage — AI 真实对话页（流式、多会话、降级策略）
 * ============================================================================
 *
 * 【发送判定（FR-008/FR-009 零请求约束）】发送前依次判定：
 *   1. 演示模式 → 本地示例应答（零网络请求）；
 *   2. API Key 未配置（ASSET 读取为空）→ 展示引导（可跳设置页），
 *      不构造请求、不清空输入；
 *   3. custom baseUrl 缺失 → 可读提示，不构造请求。
 *
 * 【流式渲染（FR-005）】增量经页面级 @State streamingText 驱动独立"生成中"
 *   气泡实时渲染；完成/中断/失败后一次性落入会话消息（消息一旦入列不再
 *   原地变更，规避 V1 观察能力限制）。
 *
 * 【中断与错误（FR-006/FR-010/FR-013）】"停止"/切换会话/离开页面统一走
 *   cancelGeneration()：终止请求句柄、保留已生成内容并标注状态；
 *   错误映射为可读 i18n 提示且保留用户输入（输入框为空时回填上次发送内容）。
 *
 * 【会话（FR-007）】新建/切换/删除（二次确认）经 AIChatManager；
 *   消息区随会话切换；aboutToAppear 恢复既有会话（loadConversations）。
 *
 * 【状态胶囊即时刷新】设置页保存/清除配置（或切换演示模式）后，经
 *   SettingsManager 写入 AppStorage 'aiConfigTick' 时间戳信号，本页
 *   @StorageLink + @Watch 订阅并实时重读 SettingsManager 重算胶囊文案，
 *   无需重启即可更新 provider · model 展示（Tabs 切换不触发生命周期）。
 *
 * 【消息布局】用户消息右对齐（主色底白字、纯文本）；助手消息左对齐
 *   （灰底、MarkdownText 渲染、无头像）。
 * ============================================================================
 */
import { Theme, SafeTop, Space, Radius, FontSize } from '../Theme';
import { ScreenHeader } from '../../components/Ui';
import { I18n } from '../../utils/I18n';
import { LLMService, LLMStreamSession, LLMStreamHandlers, LLMProviderConfig,
  LLMChatTurn, LLMErrorKind } from '../../services/ai/LLMService';
import { ApiKeyStore } from '../../services/ai/ApiKeyStore';
import { AIChatManager, AIChatMessage, AIChatMessageStatus } from '../../state/AIChatManager';
import { SettingsManager, AIProviderSettings } from '../../state/SettingsManager';
import { MarkdownText } from '../common/components/MarkdownText';
import { ChatMessage, Conversation } from '../../domain/AIAgentTypes';
import { emitNavigate, NavTarget } from '../../state/UiEvents';

/** 推荐提问：词典键（渲染与发送时均经页面 tr() 按当前语言解析） */
const SUGGESTION_KEYS: string[] = [
  'ai.suggest.schedule',
  'ai.suggest.classroom',
  'ai.suggest.ddl',
  'ai.suggest.grades',
  'ai.suggest.card',
];

/** 演示模式本地应答延迟（ms），模拟"思考"节奏 */
const DEMO_REPLY_DELAY_MS: number = 800;

/** ISO 时间 → HH:mm（无效/缺失返回空串） */
function formatTime(iso: string): string {
  if (iso.length === 0) {
    return '';
  }
  const d: Date = new Date(iso);
  if (Number.isNaN(d.getTime())) {
    return '';
  }
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

/** ISO 时间 → MM-dd HH:mm（会话列表元信息） */
function formatDate(iso: string): string {
  if (iso.length === 0) {
    return '';
  }
  const d: Date = new Date(iso);
  if (Number.isNaN(d.getTime())) {
    return '';
  }
  return `${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')} ` +
    `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

/**
 * 消息气泡：用户消息右对齐（主色底白字、纯文本）、助手消息左对齐
 * （灰底、Markdown 渲染）；助手无头像（无占位空间）。
 */
@Component
struct MessageBubble {
  @Prop content: string = '';
  @Prop role: string = 'user';
  @Prop timeText: string = '';
  @Prop status: string = AIChatMessageStatus.OK;
  /** 语言订阅：中断/失败状态标注随语言切换即时重渲染 */
  @StorageLink('locale') locale: string = 'zh';

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  /** 状态标注（ok 无标注；aborted/error 显示对应 i18n 文案） */
  private statusLabel(): string {
    if (this.status === AIChatMessageStatus.ABORTED) {
      return this.tr('ai.msgAborted');
    }
    if (this.status === AIChatMessageStatus.ERROR) {
      return this.tr('ai.msgFailed');
    }
    return '';
  }

  build() {
    Column() {
      if (this.role === 'user') {
        // 用户消息：右对齐、主色底白字、纯文本（长词/长链接可断行）
        Text(this.content)
          .fontSize(14)
          .fontColor(Theme.textInvert)
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .borderRadius({ topLeft: 16, topRight: 16, bottomLeft: 16, bottomRight: 4 })
          .backgroundColor(Theme.primary)
          .constraintSize({ maxWidth: '80%' })
          .wordBreak(WordBreak.BREAK_WORD)
      } else {
        // 助手消息：左对齐、灰底、Markdown 渲染（无头像及其占位）
        Column() {
          MarkdownText({ content: this.content })
        }
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius({ topLeft: 16, topRight: 16, bottomLeft: 4, bottomRight: 16 })
        .backgroundColor(Theme.surfaceAlt)
        .constraintSize({ maxWidth: '88%' })
      }

      if (this.statusLabel().length > 0) {
        Text(this.statusLabel())
          .fontSize(10)
          .fontColor(this.status === AIChatMessageStatus.ERROR ? Theme.error : Theme.textMuted)
          .margin({ top: 2 })
      }
      if (this.timeText.length > 0) {
        Text(this.timeText)
          .fontSize(10)
          .fontColor(Theme.textMuted)
          .margin({ top: 2 })
      }
    }
    .width('100%')
    .alignItems(this.role === 'user' ? HorizontalAlign.End : HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
  }
}

@Component
export struct AIChatPage {
  /** 语言订阅：语言切换即时重渲染（胶囊文案经 refreshChip 联动重算） */
  @StorageLink('locale') @Watch('refreshChip') locale: string = 'zh';
  /**
   * AI 配置变更信号（设置页保存/清除/演示开关时由 SettingsManager 写入
   * AppStorage 时间戳）：订阅后无需重启即时刷新状态胶囊，解决 Tabs 切换
   * 不触发页面生命周期导致的 provider·model 展示滞后。
   */
  @StorageLink('aiConfigTick') @Watch('refreshChip') aiConfigTick: number = 0;

  /** 当前会话消息（渲染副本；消息入列后不再原地变更） */
  @State messages: ChatMessage[] = [];
  @State inputText: string = '';
  /** 生成中（流式或演示本地应答） */
  @State busy: boolean = false;
  /** 流式增量文本（驱动"生成中"气泡实时渲染） */
  @State streamingText: string = '';
  /** 可读错误提示（横幅展示；空串隐藏） */
  @State errorText: string = '';
  /** 未配置引导卡片（发送时判定；跳设置或再次发送时收起） */
  @State showNotConfigured: boolean = false;
  /** 会话列表半模态 */
  @State showChatList: boolean = false;
  /** 状态胶囊文案（演示提示 / provider · model；实时读 SettingsManager 重算，不缓存 provider/model） */
  @State chipLabel: string = '';

  /** 流式请求取消句柄（busy 时有效） */
  private session: LLMStreamSession | undefined = undefined;
  /** 演示模式本地应答定时器句柄（<0 表示无待触发应答） */
  private demoTimer: number = -1;
  /** 当前流式/演示应答目标会话 id */
  private streamConvId: string = '';
  /** 最近一次发送内容（错误时回填输入框，保证输入不丢） */
  private lastSentText: string = '';
  /** 消息区滚动控制器（流式跟随滚动到底部） */
  private scroller: Scroller = new Scroller();

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  // ============================================================
  // 生命周期
  // ============================================================

  aboutToAppear(): void {
    // 初始化状态胶囊（实时读 SettingsManager；重启后同路径取到持久化配置）
    this.refreshChip();
    // 启动恢复既有会话（含旧数据归一），完成后刷新消息区
    AIChatManager.loadConversations().then((): void => {
      this.refreshMessages();
    }).catch((): void => {
      this.refreshMessages();
    });
  }

  aboutToDisappear(): void {
    // 离开页面终止请求，无悬挂（FR-013）；已生成内容落为"已中断"
    this.cancelGeneration();
  }

  // ============================================================
  // 发送主流程（判定顺序：演示 → 未配置 → baseUrl → 流式）
  // ============================================================

  private async sendMessage(): Promise<void> {
    const text: string = this.inputText.trim();
    if (text.length === 0 || this.busy) {
      return;
    }
    this.errorText = '';
    this.showNotConfigured = false;

    // 1) 演示模式：本地示例应答，零网络请求（FR-009/SC-006）
    if (SettingsManager.isDemoMode()) {
      this.sendDemo(text);
      return;
    }

    // 2) 未配置 Key：展示引导，不构造请求（FR-008/SC-005）；输入保留
    let apiKey: string = '';
    try {
      apiKey = await ApiKeyStore.get();
    } catch (e) {
      apiKey = '';
    }
    if (apiKey.length === 0) {
      this.showNotConfigured = true;
      return;
    }

    // 3) 配置形态校验（custom 缺 baseUrl 等）：可读提示，不构造请求
    const settings: AIProviderSettings = SettingsManager.getAIProviderSettings();
    const config: LLMProviderConfig = new LLMProviderConfig();
    config.preset = settings.preset;
    config.baseUrl = settings.baseUrl;
    config.model = settings.model;
    if (LLMService.resolveBaseUrl(config).length === 0) {
      this.errorText = this.tr('ai.errorBadBaseUrl');
      return;
    }

    // 4) 真实流式请求
    const conv: Conversation = this.ensureConversation();
    this.streamConvId = conv.id;
    AIChatManager.addMessage(conv.id, 'user', text);
    this.lastSentText = text;
    this.inputText = '';
    this.refreshMessages();
    this.scrollToEnd();
    this.startStream(conv, config, apiKey);
  }

  /** 演示模式本地应答（关键词命中 i18n 示例文案；零网络请求） */
  private sendDemo(text: string): void {
    const conv: Conversation = this.ensureConversation();
    this.streamConvId = conv.id;
    AIChatManager.addMessage(conv.id, 'user', text);
    this.lastSentText = text;
    this.inputText = '';
    this.refreshMessages();
    this.busy = true;
    const reply: string = this.getMockResponse(text);
    this.demoTimer = setTimeout(() => {
      this.demoTimer = -1;
      this.busy = false;
      AIChatManager.addMessage(conv.id, 'assistant', reply);
      if (this.activeConvId() === conv.id) {
        this.refreshMessages();
        this.scrollToEnd();
      }
    }, DEMO_REPLY_DELAY_MS);
  }

  /** 发起流式请求：增量实时渲染，完成/失败分别收尾 */
  private startStream(conv: Conversation, config: LLMProviderConfig, apiKey: string): void {
    this.busy = true;
    this.streamingText = '';
    // 历史快照（含刚追加的用户消息；仅 user/assistant 且内容非空）
    const history: LLMChatTurn[] = [];
    for (let i: number = 0; i < conv.messages.length; i++) {
      const m: ChatMessage = conv.messages[i];
      if (m.role !== 'user' && m.role !== 'assistant') {
        continue;
      }
      if (m.content.trim().length === 0) {
        continue;
      }
      const turn: LLMChatTurn = new LLMChatTurn();
      turn.role = m.role;
      turn.content = m.content;
      history.push(turn);
    }

    const handlers: LLMStreamHandlers = new LLMStreamHandlers();
    handlers.onDelta = (chunk: string): void => {
      this.streamingText += chunk;
      this.scrollToEnd();
    };
    handlers.onDone = (fullText: string): void => {
      this.finishStreamOk(fullText);
    };
    handlers.onError = (kind: LLMErrorKind): void => {
      this.handleStreamError(kind);
    };
    this.session = LLMService.streamChat(config, apiKey, history, handlers, '');
  }

  /** 流式正常收尾：完整回复入列（状态 ok） */
  private finishStreamOk(fullText: string): void {
    this.busy = false;
    this.session = undefined;
    this.streamingText = '';
    if (this.streamConvId.length > 0) {
      AIChatManager.addMessage(this.streamConvId, 'assistant', fullText);
    }
    this.refreshMessages();
    this.scrollToEnd();
  }

  /** 中断生成（停止按钮/切换会话/离开页面）：保留已生成内容并标注"已中断" */
  private cancelGeneration(): void {
    if (!this.busy) {
      return;
    }
    // 演示模式：取消待触发的本地应答
    if (this.demoTimer >= 0) {
      clearTimeout(this.demoTimer);
      this.demoTimer = -1;
      this.busy = false;
      return;
    }
    this.busy = false;
    const partial: string = this.streamingText;
    this.streamingText = '';
    const s: LLMStreamSession | undefined = this.session;
    this.session = undefined;
    if (s !== undefined) {
      s.cancel();
    }
    if (partial.length > 0 && this.streamConvId.length > 0) {
      const msg: ChatMessage = AIChatManager.addMessage(this.streamConvId, 'assistant', partial);
      AIChatManager.updateMessageStatus(this.streamConvId, msg.id, AIChatMessageStatus.ABORTED);
      this.refreshMessages();
    }
  }

  /** 流式失败：可读提示（i18n 映射）；保留已生成内容（标注"失败"）与用户输入 */
  private handleStreamError(kind: LLMErrorKind): void {
    this.busy = false;
    this.session = undefined;
    const partial: string = this.streamingText;
    this.streamingText = '';
    if (partial.length > 0 && this.streamConvId.length > 0) {
      const msg: ChatMessage = AIChatManager.addMessage(this.streamConvId, 'assistant', partial);
      AIChatManager.updateMessageStatus(this.streamConvId, msg.id, AIChatMessageStatus.ERROR);
    }
    if (kind === LLMErrorKind.NOT_CONFIGURED) {
      this.showNotConfigured = true;
    } else {
      this.errorText = this.errorTextFor(kind);
    }
    // 输入不丢（FR-010）：输入框为空时回填上次发送内容，便于修改重试
    if (this.inputText.trim().length === 0) {
      this.inputText = this.lastSentText;
    }
    this.refreshMessages();
  }

  /** 错误类别 → 可读 i18n 文案（不含 Key/鉴权头，FR-015） */
  private errorTextFor(kind: LLMErrorKind): string {
    if (kind === LLMErrorKind.AUTH) {
      return this.tr('ai.errorAuth');
    }
    if (kind === LLMErrorKind.RATE_LIMIT) {
      return this.tr('ai.errorRateLimit');
    }
    if (kind === LLMErrorKind.NETWORK) {
      return this.tr('ai.errorNetwork');
    }
    if (kind === LLMErrorKind.TIMEOUT) {
      return this.tr('ai.errorTimeout');
    }
    if (kind === LLMErrorKind.EMPTY) {
      return this.tr('ai.errorEmpty');
    }
    if (kind === LLMErrorKind.BAD_BASE_URL) {
      return this.tr('ai.errorBadBaseUrl');
    }
    if (kind === LLMErrorKind.SERVER) {
      return this.tr('ai.errorServer');
    }
    return this.tr('ai.errorGeneric');
  }

  // ============================================================
  // 会话操作（新建/切换/删除）
  // ============================================================

  /** 无活动会话时按需创建（保持既有 createConversation 签名） */
  private ensureConversation(): Conversation {
    const conv: Conversation | undefined = AIChatManager.getActiveConversation();
    if (conv !== undefined) {
      return conv;
    }
    return AIChatManager.createConversation();
  }

  private activeConvId(): string {
    const conv: Conversation | undefined = AIChatManager.getActiveConversation();
    return conv !== undefined ? conv.id : '';
  }

  /** 新建会话：当前会话为空时复用，否则创建新会话 */
  private startNewChat(): void {
    this.cancelGeneration();
    const conv: Conversation | undefined = AIChatManager.getActiveConversation();
    if (conv === undefined || conv.messages.length > 0) {
      AIChatManager.createConversation();
    }
    this.refreshMessages();
  }

  /** 切换会话（中断进行中的生成；消息区随会话切换） */
  private switchConversation(id: string): void {
    if (id === this.activeConvId()) {
      this.showChatList = false;
      return;
    }
    this.cancelGeneration();
    AIChatManager.setActiveConversation(id);
    this.errorText = '';
    this.showNotConfigured = false;
    this.showChatList = false;
    this.refreshMessages();
  }

  /** 删除会话（AlertDialog 二次确认；非弃用 UIContext API） */
  private confirmDeleteConversation(conv: Conversation): void {
    this.getUIContext().showAlertDialog({
      title: this.tr('ai.deleteChatTitle'),
      message: `${conv.title}\n\n${this.tr('ai.deleteChatMessage')}`,
      primaryButton: {
        value: this.tr('common.cancel'),
        action: (): void => {},
      },
      secondaryButton: {
        value: this.tr('ai.deleteChatOk'),
        fontColor: Theme.error,
        action: (): void => {
          this.deleteConversation(conv.id);
        },
      },
    });
  }

  private deleteConversation(id: string): void {
    this.cancelGeneration();
    AIChatManager.deleteConversation(id);
    this.errorText = '';
    this.showNotConfigured = false;
    this.showChatList = false;
    this.refreshMessages();
  }

  // ============================================================
  // 状态辅助
  // ============================================================

  /** 从活动会话刷新消息渲染副本（新数组引用触发 ForEach 重渲染） */
  private refreshMessages(): void {
    const conv: Conversation | undefined = AIChatManager.getActiveConversation();
    this.messages = conv !== undefined ? conv.messages.slice() : [];
  }

  /** 消息区滚动到底部（新消息/流式增量跟随） */
  private scrollToEnd(): void {
    this.scroller.scrollEdge(Edge.Bottom);
  }

  /** 消息状态（非扩展消息归一 ok） */
  private statusOf(msg: ChatMessage): string {
    if (msg instanceof AIChatMessage) {
      return msg.status;
    }
    return AIChatMessageStatus.OK;
  }

  /** 跳转设置页（配置 AI 模型） */
  private goSettings(): void {
    this.showNotConfigured = false;
    const target: NavTarget = new NavTarget();
    target.tab = 5;
    emitNavigate(target);
  }

  /**
   * 重算状态胶囊文案（语言/配置信号变化时触发；实时读 SettingsManager
   * 与 LLMService 解析，不缓存 provider/model 到普通成员）：
   * 演示模式提示 / 当前 provider · model。
   */
  private refreshChip(): void {
    if (SettingsManager.isDemoMode()) {
      this.chipLabel = this.tr('ai.demoNotice');
      return;
    }
    const settings: AIProviderSettings = SettingsManager.getAIProviderSettings();
    const config: LLMProviderConfig = new LLMProviderConfig();
    config.preset = settings.preset;
    config.baseUrl = settings.baseUrl;
    config.model = settings.model;
    const model: string = LLMService.resolveModel(config);
    const label: string = this.presetLabel(settings.preset);
    this.chipLabel = model.length > 0 ? label + ' · ' + model : label;
  }

  private presetLabel(id: string): string {
    if (id === 'openai') {
      return this.tr('settings.aiPresetOpenai');
    }
    if (id === 'deepseek') {
      return this.tr('settings.aiPresetDeepseek');
    }
    if (id === 'dashscope') {
      return this.tr('settings.aiPresetDashscope');
    }
    if (id === 'moonshot') {
      return this.tr('settings.aiPresetMoonshot');
    }
    return this.tr('settings.aiPresetCustom');
  }

  /** 演示模式本地应答（关键词命中 i18n 示例；与旧版行为一致） */
  private getMockResponse(prompt: string): string {
    const p: string = prompt.toLowerCase();
    if (prompt.indexOf('课') >= 0 || p.indexOf('class') >= 0 || p.indexOf('schedule') >= 0) {
      return this.tr('ai.mockCourses');
    }
    if (prompt.indexOf('教室') >= 0 || p.indexOf('classroom') >= 0 || p.indexOf('room') >= 0) {
      return this.tr('ai.mockClassroom');
    }
    if (prompt.indexOf('DDL') >= 0 || prompt.indexOf('作业') >= 0 || p.indexOf('ddl') >= 0
      || p.indexOf('deadline') >= 0 || p.indexOf('assignment') >= 0 || p.indexOf('homework') >= 0) {
      return this.tr('ai.mockDdl');
    }
    if (prompt.indexOf('成绩') >= 0 || p.indexOf('gpa') >= 0 || p.indexOf('grade') >= 0) {
      return this.tr('ai.mockGrades');
    }
    if (prompt.indexOf('校园卡') >= 0 || prompt.indexOf('余额') >= 0 || p.indexOf('card') >= 0
      || p.indexOf('balance') >= 0) {
      return this.tr('ai.mockCard');
    }
    return this.tr('ai.mockDefault');
  }

  // ============================================================
  // UI 构建
  // ============================================================

  @Builder
  headerActions() {
    Row({ space: Space.sm }) {
      Text(this.tr('ai.chats'))
        .fontSize(FontSize.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.primary)
        .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
        .borderRadius(Radius.pill)
        .backgroundColor(Theme.surfaceAlt)
        .onClick(() => {
          this.showChatList = true;
        })
      Text(this.tr('ai.newChat'))
        .fontSize(FontSize.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.primary)
        .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
        .borderRadius(Radius.pill)
        .backgroundColor(Theme.surfaceAlt)
        .onClick(() => {
          this.startNewChat();
        })
    }
  }

  @Builder
  typingIndicator() {
    Column() {
      Row() {
        Text('●').fontSize(6).fontColor(Theme.textMuted).margin({ right: 4 })
        Text('●').fontSize(6).fontColor(Theme.textMuted).margin({ right: 4 })
        Text('●').fontSize(6).fontColor(Theme.textMuted)
      }
      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
      .borderRadius(16)
      .backgroundColor(Theme.surfaceAlt)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 10 })
  }

  @Builder
  chatListSheetBuilder() {
    Column() {
      Text(this.tr('ai.chatListTitle'))
        .fontSize(FontSize.h3)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
        .margin({ bottom: Space.md })

      Scroll() {
        Column() {
          ForEach(AIChatManager.getConversations(), (conv: Conversation) => {
            Row({ space: Space.md }) {
              Column({ space: 2 }) {
                Text(conv.title.length > 0 ? conv.title : this.tr('ai.newChat'))
                  .fontSize(FontSize.label)
                  .fontColor(conv.id === this.activeConvId() ? Theme.primary : Theme.text)
                  .fontWeight(conv.id === this.activeConvId() ? FontWeight.Medium : FontWeight.Normal)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: '80%' })
                Text(`${formatDate(conv.updatedAt)} · ${conv.messages.length} 💬`)
                  .fontSize(FontSize.micro)
                  .fontColor(Theme.textMuted)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text('✕')
                .fontSize(FontSize.caption)
                .fontColor(Theme.textMuted)
                .padding(Space.sm)
                .onClick(() => {
                  this.confirmDeleteConversation(conv);
                })
            }
            .width('100%')
            .padding({ left: Space.md, right: Space.sm, top: Space.md, bottom: Space.md })
            .borderRadius(Radius.md)
            .backgroundColor(conv.id === this.activeConvId() ? Theme.primaryMuted : Theme.surfaceAlt)
            .margin({ bottom: Space.sm })
            .onClick(() => {
              this.switchConversation(conv.id);
            })
          }, (conv: Conversation) => conv.id + '_' + conv.messages.length + '_' + conv.updatedAt)
        }
        .width('100%')
      }
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding(Space.lg)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      SafeTop()

      Column() {
        ScreenHeader({
          eyebrow: this.tr('ai.eyebrow'),
          title: this.tr('ai.title'),
          right: (): void => this.headerActions()
        })
      }
      .width('100%')
      .padding({ left: Space.lg, right: Space.md, top: Space.lg, bottom: Space.sm })

      Divider().color(Theme.divider)

      // 状态胶囊：演示模式提示 / provider · model（点击跳设置；
      // 文案随语言与 aiConfigTick 配置信号即时重算，无需重启）
      Row() {
        Text(this.chipLabel)
          .fontSize(FontSize.micro)
          .fontColor(Theme.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '100%' })
      }
      .padding({ left: Space.md, right: Space.md, top: 6, bottom: 6 })
      .margin({ left: Space.md, top: Space.sm })
      .borderRadius(Radius.pill)
      .backgroundColor(Theme.primaryMuted)
      .onClick(() => {
        this.goSettings();
      })

      if (this.messages.length > 0) {
        Scroll(this.scroller) {
          Column() {
            ForEach(this.messages, (msg: ChatMessage) => {
              MessageBubble({
                content: msg.content,
                role: msg.role,
                timeText: formatTime(msg.timestamp),
                status: this.statusOf(msg),
              })
            }, (msg: ChatMessage) => msg.id)

            if (this.busy) {
              if (this.streamingText.length > 0) {
                // 流式增量：助手气泡（左对齐、灰底、Markdown 渲染、无头像）
                Column() {
                  Column() {
                    MarkdownText({ content: this.streamingText })
                  }
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .borderRadius({ topLeft: 16, topRight: 16, bottomLeft: 4, bottomRight: 16 })
                  .backgroundColor(Theme.surfaceAlt)
                  .constraintSize({ maxWidth: '88%' })

                  Text(this.tr('ai.generating'))
                    .fontSize(10)
                    .fontColor(Theme.textMuted)
                    .margin({ top: 2 })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding({ left: 16, right: 16, top: 6, bottom: 6 })
              } else {
                this.typingIndicator()
              }
            }

            Blank().height(8)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.TopStart)
      } else {
        Column() {
          Text('🤖')
            .fontSize(64)
            .margin({ bottom: 16 })

          Text(this.tr('ai.brandName'))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.text)

          Text(this.tr('ai.subtitle'))
            .fontSize(14)
            .fontColor(Theme.textMuted)
            .margin({ top: 6, bottom: 32 })

          Text(this.tr('ai.tryAsking'))
            .fontSize(13)
            .fontColor(Theme.textMuted)
            .margin({ bottom: 12 })

          ForEach(SUGGESTION_KEYS, (key: string) => {
            Text(this.tr(key))
              .fontSize(14)
              .fontColor(Theme.primary)
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .borderRadius(999)
              .backgroundColor('rgba(124,92,250,0.06)')
              .border({ width: 1, color: 'rgba(124,92,250,0.15)' })
              .margin({ bottom: 8 })
              .onClick(() => {
                this.inputText = this.tr(key);
                this.sendMessage();
              })
          })
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
      }

      // 未配置引导（发送时判定；可跳设置页；不发起请求）
      if (this.showNotConfigured) {
        Row({ space: Space.md }) {
          Text('⚙️')
            .fontSize(20)
          Column({ space: 2 }) {
            Text(this.tr('ai.notConfiguredTitle'))
              .fontSize(FontSize.label)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.text)
            Text(this.tr('ai.notConfiguredHint'))
              .fontSize(FontSize.micro)
              .fontColor(Theme.textMuted)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text(this.tr('ai.goSettings'))
            .fontSize(FontSize.caption)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.primary)
            .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
            .borderRadius(Radius.pill)
            .backgroundColor(Theme.primaryMuted)
            .onClick(() => {
              this.goSettings();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding(Space.md)
        .margin({ left: Space.md, right: Space.md, top: Space.sm })
        .borderRadius(Radius.md)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.border })
      }

      // 可读错误提示（点 ✕ 收起；下次发送自动清除）
      if (this.errorText.length > 0) {
        Row({ space: Space.sm }) {
          Text(`⚠️ ${this.errorText}`)
            .fontSize(FontSize.caption)
            .fontColor(Theme.error)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text('✕')
            .fontSize(FontSize.caption)
            .fontColor(Theme.textMuted)
            .padding(Space.xs)
            .onClick(() => {
              this.errorText = '';
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: Space.md, right: Space.sm, top: Space.sm, bottom: Space.sm })
        .margin({ left: Space.md, right: Space.md, top: Space.sm })
        .borderRadius(Radius.md)
        .backgroundColor(Theme.errorMuted)
      }

      Row() {
        TextInput({ placeholder: this.tr('ai.inputPlaceholder'), text: this.inputText })
          .type(InputType.Normal)
          .height(44)
          .fontSize(14)
          .fontColor(Theme.text)
          .caretColor(Theme.primary)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.border })
          .borderRadius(22)
          .padding({ left: 18, right: 8 })
          .layoutWeight(1)
          .onChange((v: string) => {
            this.inputText = v;
          })

        if (this.busy) {
          Button(this.tr('ai.stop'))
            .type(ButtonType.Capsule)
            .height(44)
            .fontSize(14)
            .fontColor(Theme.error)
            .backgroundColor(Theme.surface)
            .borderRadius(22)
            .margin({ left: 8 })
            .onClick(() => {
              this.cancelGeneration();
            })
        } else {
          Button(this.tr('ai.send'))
            .type(ButtonType.Capsule)
            .height(44)
            .fontSize(14)
            .fontColor(Theme.textInvert)
            .backgroundColor(Theme.primary)
            .borderRadius(22)
            .margin({ left: 8 })
            .enabled(this.inputText.trim().length > 0)
            .onClick(() => {
              this.sendMessage();
            })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 16 })
      .backgroundColor(Theme.surface)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
    .bindSheet($$this.showChatList, this.chatListSheetBuilder(), {
      height: 480,
      showClose: true,
      dragBar: true,
    })
  }
}
