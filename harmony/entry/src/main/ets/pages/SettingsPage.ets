/**
 * SettingsPage — 设置页（对齐原项目 SettingsScreen：组标题 + 白卡行组）
 *
 * 功能对接（settings-integration 特性）：
 *  - 偏好项（演示模式/信任设备/语言）经 SettingsManager 写入即持久化；
 *    演示模式写内存即全应用生效（状态对象为单一事实源）。
 *  - 全部文案走 I18n（@StorageLink('locale') 订阅语言即时重渲染）。
 *  - 账号信息只读展示（学号取自本地凭证）；未登录/演示模式展示状态文案。
 *  - 退出登录：AlertDialog 二次确认 → 注销会话（凭证按信任策略：信任→保留，
 *    登录页可回填一键直达；未信任→清除，不留残留）。
 *  - 数据清理：AI 会话 / 学习缓存（AlertDialog 二次确认 + 结果提示）。
 *  - 版本号读取自身应用包信息（bundleManager，禁止硬编码）。
 *  - "AI 记忆 / 操作记录 / 智能监控"标注"暂不支持"（禁用态，无跳转）。
 *  - AI 模型配置（ai-chat 特性）：预设/自定义 provider + 掩码 API Key；
 *    Key 入系统关键资产存储（ApiKeyStore，不落偏好明文），provider 配置
 *    经 SettingsManager 持久化；保存时校验 baseUrl 形态。
 */
import { Theme, SafeTop, Space, Radius, FontSize } from './Theme';
import { ScreenHeader, SectionHeader, InfoRow } from '../components/Ui';
import { bundleManager } from '@kit.AbilityKit';
import { SettingsManager, AIProviderSettings } from '../state/SettingsManager';
import { AuthManager } from '../state/AuthManager';
import { SessionManager } from '../services/auth/SessionManager';
import { SecureStorage, SecureCredentials } from '../storage/SecureStorage';
import { LocalDataCleaner } from '../storage/LocalDataCleaner';
import { ApiKeyStore } from '../services/ai/ApiKeyStore';
import { LLMService, LLMProviderPreset } from '../services/ai/LLMService';
import { I18n } from '../utils/I18n';

/** 导航行：label + 右侧值 + › */
@Component
struct SettingRow {
  @Prop label: string = '';
  @Prop value: string = '';
  onItemClick: () => void = () => {};

  build() {
    Row() {
      Text(this.label)
        .fontSize(FontSize.body)
        .fontColor(Theme.text)
        .layoutWeight(1)

      if (this.value.length > 0) {
        Text(this.value)
          .fontSize(FontSize.caption)
          .fontColor(Theme.textSecondary)
      }
      Text('›')
        .fontSize(20)
        .fontWeight(FontWeight.Lighter)
        .fontColor(Theme.textMuted)
        .margin({ left: Space.sm })
    }
    .width('100%')
    .padding({ left: Space.md, right: Space.md, top: 14, bottom: 14 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.onItemClick(); })
  }
}

/** 开关行：label + Switch */
@Component
struct SettingSwitch {
  @Prop label: string = '';
  @Link isOn: boolean;
  onToggle: (v: boolean) => void = (v: boolean) => {};

  build() {
    Row() {
      Text(this.label)
        .fontSize(FontSize.body)
        .fontColor(Theme.text)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: $$this.isOn })
        .onChange((v: boolean) => { this.onToggle(v); })
    }
    .width('100%')
    .padding({ left: Space.md, right: Space.md, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }
}

/** 未支持功能行：label + “暂不支持”标注（禁用态，无跳转、无误导描述） */
@Component
struct UnsupportedRow {
  @Prop label: string = '';
  @Prop value: string = '';

  build() {
    Row() {
      Text(this.label)
        .fontSize(FontSize.body)
        .fontColor(Theme.textMuted)
        .layoutWeight(1)
      Text(this.value)
        .fontSize(FontSize.caption)
        .fontColor(Theme.textMuted)
    }
    .width('100%')
    .padding({ left: Space.md, right: Space.md, top: 14, bottom: 14 })
    .alignItems(VerticalAlign.Center)
    .opacity(0.65)
  }
}

@Component
export struct SettingsPage {
  /** 语言运行时状态（AppStorage）：切换即时重渲染整页文案 */
  @StorageLink('locale') locale: string = 'zh';
  /** 设置弹层驱动：单节点单 bindSheet + 模式枚举（'language' | 'ai' | ''），
   *  避免同节点多次 bindSheet 后者覆盖前者导致的"点击无响应/延迟弹出"。
   *  visible 采用单向绑定（不用 $$）：交互关闭统一经 shouldDismiss 进入
   *  本页关闭流程，框架不再回写 visible，杜绝上一轮关闭的过期 false
   *  回写把新一轮弹层"连坐关闭"的竞态。 */
  @State sheetMode: string = '';
  @State sheetVisible: boolean = false;
  /** 打开序号令牌：每次打开递增。用于识别过期的关闭事件——
   *  onDisappear 仅在令牌未被更新的打开刷新时才复位模式。 */
  private sheetOpenToken: number = 0;
  /** 当前关闭流程所属令牌（进入关闭流程时记录为当时的打开令牌）；
   *  -1 表示无在途关闭流程（新打开时复位，使旧 onDisappear 必然失配）。 */
  private sheetClosingToken: number = -1;
  @State demoMode: boolean = false;
  @State trustDevice: boolean = false;
  @State isSignedIn: boolean = false;
  @State accountStudentId: string = '';
  @State versionName: string = '';

  // ── AI 模型配置（ai-chat 特性）──
  @State aiPreset: string = 'openai';
  @State aiBaseUrl: string = '';
  @State aiModel: string = '';
  @State aiKeyInput: string = '';
  @State aiKeyVisible: boolean = false;
  /** 安全存储中已存在 Key（输入留空时保存语义为"保持不变"） */
  @State aiKeyConfigured: boolean = false;

  aboutToAppear(): void {
    this.demoMode = SettingsManager.isDemoMode();
    this.trustDevice = SettingsManager.isTrustDevice();
    this.isSignedIn = AuthManager.isLoggedIn();
    this.loadAccountStudentId();
    this.loadVersionInfo();
    this.loadAIConfig();
  }

  /**
   * 翻译（页面唯一入口）：显式读取 this.locale，使每个调用它的 UI 元素
   * 与 @StorageLink('locale') 建立渲染依赖，语言切换时即时刷新本页文案。
   */
  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  // ============================================================
  // 账号信息（只读）：学号取自本地凭证；姓名/邮箱无既有获取能力，省略
  // ============================================================

  private loadAccountStudentId(): void {
    if (this.demoMode || !this.isSignedIn) {
      return;
    }
    SecureStorage.getCredentials().then((creds: SecureCredentials | undefined): void => {
      if (creds !== undefined) {
        this.accountStudentId = creds.studentId;
      }
    }).catch((): void => {
      // 凭证读取失败：学号行由 InfoRow 空值兜底显示占位，不报错
    });
  }

  /** 账号行标签：未登录为「状态」，已登录为「学号」 */
  private accountLabel(): string {
    if (!this.isSignedIn) {
      return this.tr('settings.accountStatus');
    }
    return this.tr('settings.accountStudentId');
  }

  /** 账号行取值：未登录优先（演示态附提示），已登录显示学号 */
  private accountValue(): string {
    if (!this.isSignedIn) {
      if (this.demoMode) {
        return this.tr('settings.statusLoggedOut') + ' · ' + this.tr('settings.statusDemo');
      }
      return this.tr('settings.statusLoggedOut');
    }
    return this.accountStudentId;
  }

  // ============================================================
  // 版本信息：读取自身应用包信息（禁止硬编码）；失败回退可读占位
  // ============================================================

  private loadVersionInfo(): void {
    bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      .then((info: bundleManager.BundleInfo): void => {
        this.versionName = info.versionName;
      })
      .catch((): void => {
        this.versionName = '';
      });
  }

  private versionText(): string {
    if (this.versionName.length > 0) {
      return `${this.tr('settings.appName')} v${this.versionName}`;
    }
    return `${this.tr('settings.appName')}（${this.tr('settings.versionUnknown')}）`;
  }

  // ============================================================
  // 偏好开关：SettingsManager setter（内存 + 持久化）；失败可读提示
  // ============================================================

  private handleDemoToggle(enabled: boolean): void {
    this.demoMode = enabled;
    // 写内存即全应用生效（既有判定读同一设置对象）；持久化由 setter 内部完成
    SettingsManager.setDemoMode(enabled);
    this.confirmPersisted();
    // 关闭演示模式后：若已登录则补加载账号信息（学号仅在非演示且已登录时展示，
    // 否则页面会停留在「—」占位；aboutToAppear 时若处于演示模式会跳过加载）
    if (!enabled) {
      this.loadAccountStudentId();
    }
  }

  private handleTrustToggle(enabled: boolean): void {
    this.trustDevice = enabled;
    SettingsManager.setTrustDevice(enabled);
    SettingsManager.markTrustChoiceMade();
    if (enabled) {
      // 重新开启信任 → 复位"待清除"标记（后续登录恢复凭证持久化）
      SettingsManager.setPendingClear(false);
      this.showToast(this.tr('settings.trustOnNotice'));
    } else {
      // 取消信任 → 仅置"待清除"标记：本次运行内会话继续可用（不清会话、
      // 不清 Cookie、不打断任何请求/漫游）；已持久化凭证在应用退出时清除
      // （EntryAbility 退出钩子），被强杀则由下次启动兜底清除
      SettingsManager.setPendingClear(true);
      this.showToast(this.tr('settings.trustOffNotice'));
    }
    this.confirmPersisted();
  }

  private confirmPersisted(): void {
    SettingsManager.flush().then((ok: boolean): void => {
      if (!ok) {
        this.showToast(this.tr('settings.saveFailed'));
      }
    });
  }

  private selectLanguage(locale: string): void {
    // 校验 + 写 AppStorage（即时重渲染）+ 经 SettingsManager 持久化
    I18n.setLocale(locale);
    this.closeSettingsSheet();
  }

  /** 打开设置弹层（语言/AI 预设共用单弹层，模式互斥）。
   *  时序：先递增令牌并作废在途关闭标记 → 写入新模式 → 最后由 visible 驱动弹出。
   *  打开不依赖上一轮残留状态（无论上一轮关闭动画/onDisappear 是否走完均立即生效）。 */
  private openSettingsSheet(mode: string): void {
    this.sheetOpenToken += 1;
    this.sheetClosingToken = -1;
    this.sheetMode = mode;
    this.sheetVisible = true;
  }

  /** 关闭设置弹层：关闭流程开始即记录令牌（所有关闭路径统一走此处，两入口互不串扰）。
   *  模式不在此时复位，交由 onDisappear 按令牌守卫复位——若关闭期间发生了新的
   *  打开（令牌已变），过期 onDisappear 不会清掉新一轮的模式/状态。 */
  private closeSettingsSheet(): void {
    this.sheetClosingToken = this.sheetOpenToken;
    this.sheetVisible = false;
  }

  // ============================================================
  // AI 模型配置（ai-chat）：预设/自定义 + Key 入安全存储（ASSET）
  // ============================================================

  /** 载入持久化 provider 配置与 Key 配置态（Key 内容不进入页面状态） */
  private loadAIConfig(): void {
    const settings: AIProviderSettings = SettingsManager.getAIProviderSettings();
    this.aiPreset = settings.preset;
    this.aiBaseUrl = settings.baseUrl;
    this.aiModel = settings.model;
    // 非自定义预设且未填模型时回填预设默认模型
    if (this.aiPreset !== 'custom' && this.aiModel.length === 0) {
      const preset: LLMProviderPreset | undefined = LLMService.getPreset(this.aiPreset);
      if (preset !== undefined) {
        this.aiModel = preset.defaultModel;
      }
    }
    ApiKeyStore.get().then((key: string): void => {
      this.aiKeyConfigured = key.length > 0;
    }).catch((): void => {
      this.aiKeyConfigured = false;
    });
  }

  /** 预设显示名（i18n 渲染） */
  private presetLabel(id: string): string {
    if (id === 'deepseek') {
      return this.tr('settings.aiPresetDeepseek');
    }
    if (id === 'dashscope') {
      return this.tr('settings.aiPresetDashscope');
    }
    if (id === 'moonshot') {
      return this.tr('settings.aiPresetMoonshot');
    }
    if (id === 'custom') {
      return this.tr('settings.aiPresetCustom');
    }
    return this.tr('settings.aiPresetOpenai');
  }

  /** 选择预设：非自定义回填预设 baseUrl/默认模型；自定义留空由用户填写 */
  private selectAiPreset(id: string): void {
    this.aiPreset = id;
    if (id === 'custom') {
      this.aiBaseUrl = '';
      // 选择即持久化 + 广播信号：AI 页胶囊无需再点“保存配置”即时更新
      SettingsManager.setAIProviderSettings('custom', '', this.aiModel);
      return;
    }
    const preset: LLMProviderPreset | undefined = LLMService.getPreset(id);
    if (preset !== undefined) {
      this.aiBaseUrl = preset.baseUrl;
      this.aiModel = preset.defaultModel;
      SettingsManager.setAIProviderSettings(id, preset.baseUrl, preset.defaultModel);
    }
    this.closeSettingsSheet();
  }

  /** 保存配置：先入 Key（ASSET，失败可读提示且不落明文），再持久化 provider 配置 */
  private handleAiSave(): void {
    const presetId: string = this.aiPreset;
    const baseUrl: string = this.aiBaseUrl.trim();
    const model: string = this.aiModel.trim();
    const key: string = this.aiKeyInput.trim();
    if (presetId === 'custom') {
      // 自定义 baseUrl 形态校验：必须带 http(s):// 协议（FR：保存时校验）
      if (!(baseUrl.startsWith('http://') || baseUrl.startsWith('https://')) || baseUrl.length <= 8) {
        this.showToast(this.tr('settings.aiBaseUrlInvalid'));
        return;
      }
      if (model.length === 0) {
        this.showToast(this.tr('settings.aiModelRequired'));
        return;
      }
    }
    // 输入为空且安全存储无 Key：要求填写（无"保持不变"可回退）
    if (key.length === 0 && !this.aiKeyConfigured) {
      this.showToast(this.tr('settings.aiKeyRequired'));
      return;
    }
    if (key.length > 0) {
      ApiKeyStore.save(key).then((saved: boolean): void => {
        if (!saved) {
          this.showToast(this.tr('settings.aiSaveFailed'));
          return;
        }
        this.persistAiProvider(presetId, baseUrl, model);
      }).catch((): void => {
        this.showToast(this.tr('settings.aiSaveFailed'));
      });
      return;
    }
    this.persistAiProvider(presetId, baseUrl, model);
  }

  private persistAiProvider(presetId: string, baseUrl: string, model: string): void {
    // 预设的 baseUrl 由服务层按预设解析持久化值只存自定义（避免配置漂移）
    SettingsManager.setAIProviderSettings(presetId, presetId === 'custom' ? baseUrl : '', model);
    SettingsManager.flush().then((ok: boolean): void => {
      if (!ok) {
        this.showToast(this.tr('settings.aiSaveFailed'));
        return;
      }
      this.aiKeyConfigured = true;
      // 清空输入态：掩码回占位（已配置 · 留空保持不变），不残留明文
      this.aiKeyInput = '';
      this.showToast(this.tr('settings.aiSaveSuccess'));
    });
  }

  private confirmAiClear(): void {
    this.getUIContext().showAlertDialog({
      title: this.tr('settings.aiClearTitle'),
      message: this.tr('settings.aiClearMessage'),
      primaryButton: {
        value: this.tr('common.cancel'),
        action: (): void => {}
      },
      secondaryButton: {
        value: this.tr('settings.aiClearOk'),
        fontColor: Theme.error,
        action: (): void => { this.doAiClear(); }
      }
    });
  }

  private async doAiClear(): Promise<void> {
    await ApiKeyStore.clear();
    SettingsManager.resetAIProviderSettings();
    this.aiPreset = 'openai';
    this.aiBaseUrl = '';
    this.aiModel = '';
    const preset: LLMProviderPreset | undefined = LLMService.getPreset('openai');
    if (preset !== undefined) {
      this.aiModel = preset.defaultModel;
    }
    this.aiKeyInput = '';
    this.aiKeyConfigured = false;
    this.showToast(this.tr('settings.aiClearSuccess'));
  }

  // ============================================================
  // 退出登录：二次确认 → 仅注销会话 → 可读提示
  // （凭证策略由 SessionManager.logout 按信任态处理：信任→保留凭证，
  //   登录页回填后可一键直达主页；未信任→清除，不留残留）
  // ============================================================

  private confirmLogout(): void {
    // 确认文案按信任态区分：信任开启时明示"凭证将保留，可直接一键登录"
    const keepCreds: boolean = SettingsManager.isTrustDevice();
    this.getUIContext().showAlertDialog({
      title: this.tr('settings.logoutConfirmTitle'),
      message: keepCreds ?
        this.tr('settings.logoutConfirmKeepMessage') : this.tr('settings.logoutConfirmMessage'),
      primaryButton: {
        value: this.tr('common.cancel'),
        action: (): void => {}
      },
      secondaryButton: {
        value: this.tr('settings.logoutConfirmOk'),
        fontColor: Theme.error,
        action: (): void => { this.doLogout(); }
      }
    });
  }

  private async doLogout(): Promise<void> {
    try {
      // 信任开启 → 仅清会话态（凭证保留，FR-012 修订）；
      // 未信任 → 由 logout 内部清除凭证并复位"待清除"标记
      await SessionManager.logout();
      this.isSignedIn = false;
      this.accountStudentId = '';
      this.showToast(this.tr('settings.logoutSuccess'));
    } catch (e) {
      this.showToast(this.tr('settings.logoutFailed'));
    }
  }

  // ============================================================
  // 数据清理：二次确认 → LocalDataCleaner → 结果提示（含条数）
  // ============================================================

  private confirmClearData(): void {
    this.getUIContext().showAlertDialog({
      title: this.tr('settings.clearDataTitle'),
      message: this.tr('settings.clearDataMessage'),
      primaryButton: {
        value: this.tr('common.cancel'),
        action: (): void => {}
      },
      secondaryButton: {
        value: this.tr('settings.clearDataConfirm'),
        fontColor: Theme.error,
        action: (): void => { this.doClearData(); }
      }
    });
  }

  private async doClearData(): Promise<void> {
    const aiCount: number = await LocalDataCleaner.clearAiConversations();
    const learnCount: number = await LocalDataCleaner.clearLearningCache();
    this.showToast(this.buildClearResult(aiCount, learnCount));
  }

  private buildClearResult(aiCount: number, learnCount: number): string {
    if (aiCount === 0 && learnCount === 0) {
      return this.tr('settings.clearResultNone');
    }
    const parts: string[] = [];
    if (aiCount > 0) {
      parts.push(`${this.tr('settings.clearItemAi')} ${aiCount} ${this.tr('settings.countUnit')}`);
    }
    if (learnCount > 0) {
      parts.push(`${this.tr('settings.clearItemLearning')} ${learnCount} ${this.tr('settings.countUnit')}`);
    }
    return this.tr('settings.clearResultDone') + parts.join(this.tr('settings.clearListSep'));
  }

  // ============================================================
  // 通用
  // ============================================================

  private statusText(): string {
    if (!this.isSignedIn) {
      if (this.demoMode) {
        return this.tr('settings.statusLoggedOut') + ' · ' + this.tr('settings.statusDemo');
      }
      return this.tr('settings.statusLoggedOut');
    }
    if (this.demoMode) {
      return this.tr('settings.statusLoggedIn') + ' · ' + this.tr('settings.statusDemo');
    }
    return this.tr('settings.statusLoggedIn');
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (e) {
      /* ignore：UI 上下文不可用时静默跳过提示 */
    }
  }

  build() {
    Scroll() {
      Column() {
        SafeTop()

        Column() {
          ScreenHeader({
            eyebrow: this.tr('settings.eyebrow'),
            title: this.tr('settings.title'),
            subtitle: this.statusText()
          })
        }
        .width('100%')
        .padding({ left: Space.lg, right: Space.lg, top: Space.lg, bottom: Space.sm })

        // ── 账号信息（只读）──
        SectionHeader({ title: this.tr('settings.sectionAccount') })
          .padding({ left: Space.lg, right: Space.lg })

        Column() {
          InfoRow({ label: this.accountLabel(), value: this.accountValue() })
        }
        .width('100%')
        .constraintSize({ maxWidth: '100%' })
        .borderRadius(Radius.lg)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.borderSubtle })
        .margin({ left: Space.lg, right: Space.lg })
        .padding({ left: Space.md, right: Space.md })

        // ── 偏好设置组 ──
        SectionHeader({ title: this.tr('settings.sectionPreferences') })
          .padding({ left: Space.lg, right: Space.lg })

        Column() {
          SettingSwitch({
            label: this.tr('settings.demoMode'),
            isOn: $demoMode,
            onToggle: (v: boolean) => { this.handleDemoToggle(v); }
          })
          Divider().color(Theme.divider)
            .width('100%')
            .constraintSize({ maxWidth: '100%' })
            .margin({ left: Space.md })
          SettingSwitch({
            label: this.tr('settings.trustDevice'),
            isOn: $trustDevice,
            onToggle: (v: boolean) => { this.handleTrustToggle(v); }
          })
          Divider().color(Theme.divider)
            .width('100%')
            .constraintSize({ maxWidth: '100%' })
            .margin({ left: Space.md })
          SettingRow({
            label: this.tr('settings.language'),
            value: this.locale === 'en' ? this.tr('settings.langEn') : this.tr('settings.langZh'),
            onItemClick: () => { this.openSettingsSheet('language'); }
          })
        }
        .width('100%')
        .constraintSize({ maxWidth: '100%' })
        .borderRadius(Radius.lg)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.borderSubtle })
        .margin({ left: Space.lg, right: Space.lg })

        // ── AI 模型配置（ai-chat：预设/自定义 provider + Key 入安全存储）──
        SectionHeader({ title: this.tr('settings.sectionAI') })
          .padding({ left: Space.lg, right: Space.lg })

        Column() {
          // 预设选择行（弹层选择）
          Row() {
            Text(this.tr('settings.aiPreset'))
              .fontSize(FontSize.body)
              .fontColor(Theme.text)
              .layoutWeight(1)
            Text(this.presetLabel(this.aiPreset))
              .fontSize(FontSize.caption)
              .fontColor(Theme.textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '60%' })
            Text('›')
              .fontSize(20)
              .fontWeight(FontWeight.Lighter)
              .fontColor(Theme.textMuted)
              .margin({ left: Space.sm })
          }
          .width('100%')
          .padding({ left: Space.md, right: Space.md, top: 14, bottom: 14 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => { this.openSettingsSheet('ai'); })

          Divider().color(Theme.divider)

          // 自定义 baseUrl 输入（仅自定义预设显示；保存时校验形态）
          if (this.aiPreset === 'custom') {
            Column() {
              Text(this.tr('settings.aiBaseUrl'))
                .fontSize(FontSize.caption)
                .fontColor(Theme.textMuted)
                .margin({ top: Space.md })
              TextInput({ placeholder: this.tr('settings.aiBaseUrlPlaceholder'), text: this.aiBaseUrl })
                .type(InputType.Normal)
                .height(42)
                .fontSize(FontSize.body)
                .fontColor(Theme.text)
                .caretColor(Theme.primary)
                .backgroundColor(Theme.surfaceAlt)
                .borderRadius(Radius.sm)
                .padding({ left: Space.md, right: Space.md })
                .margin({ top: Space.sm })
                .onChange((v: string) => { this.aiBaseUrl = v; })
              Text(this.tr('settings.aiCustomHint'))
                .fontSize(FontSize.micro)
                .fontColor(Theme.textMuted)
                .margin({ top: Space.sm, bottom: Space.md })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: Space.md, right: Space.md })

            Divider().color(Theme.divider)
          }

          // 模型输入（预设默认模型自动回填，可改）
          Column() {
            Text(this.tr('settings.aiModel'))
              .fontSize(FontSize.caption)
              .fontColor(Theme.textMuted)
              .margin({ top: Space.md })
            TextInput({ placeholder: this.tr('settings.aiModelPlaceholder'), text: this.aiModel })
              .type(InputType.Normal)
              .height(42)
              .fontSize(FontSize.body)
              .fontColor(Theme.text)
              .caretColor(Theme.primary)
              .backgroundColor(Theme.surfaceAlt)
              .borderRadius(Radius.sm)
              .padding({ left: Space.md, right: Space.md })
              .margin({ top: Space.sm, bottom: Space.md })
              .onChange((v: string) => { this.aiModel = v; })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: Space.md, right: Space.md })

          Divider().color(Theme.divider)

          // API Key 掩码输入 + 显隐切换（Key 仅入安全存储，不落偏好明文）
          Column() {
            Text(this.tr('settings.aiApiKey'))
              .fontSize(FontSize.caption)
              .fontColor(Theme.textMuted)
              .margin({ top: Space.md })
            Row() {
              TextInput({
                placeholder: this.aiKeyConfigured ?
                  this.tr('settings.aiApiKeyKeep') : this.tr('settings.aiApiKeyPlaceholder'),
                text: this.aiKeyInput
              })
                .type(this.aiKeyVisible ? InputType.Normal : InputType.Password)
                .height(42)
                .fontSize(FontSize.body)
                .fontColor(Theme.text)
                .caretColor(Theme.primary)
                .backgroundColor(Theme.surfaceAlt)
                .borderRadius(Radius.sm)
                .padding({ left: Space.md, right: Space.md })
                .layoutWeight(1)
                .onChange((v: string) => { this.aiKeyInput = v; })

              Text(this.aiKeyVisible ? this.tr('settings.aiHideKey') : this.tr('settings.aiShowKey'))
                .fontSize(FontSize.caption)
                .fontColor(Theme.primary)
                .padding({ left: Space.sm, right: Space.sm, top: Space.sm, bottom: Space.sm })
                .margin({ left: Space.sm })
                .onClick(() => { this.aiKeyVisible = !this.aiKeyVisible; })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: Space.sm })

            // 配置状态（已配置/未配置）
            Text(this.aiKeyConfigured ? this.tr('settings.aiConfigured') : this.tr('settings.aiNotConfigured'))
              .fontSize(FontSize.micro)
              .fontColor(this.aiKeyConfigured ? Theme.success : Theme.textMuted)
              .margin({ top: Space.sm, bottom: Space.md })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: Space.md, right: Space.md })

          Divider().color(Theme.divider)

          // 保存 / 清除
          Row() {
            Button(this.tr('settings.aiSave'))
              .type(ButtonType.Capsule)
              .height(40)
              .fontSize(FontSize.body)
              .fontColor(Theme.textInvert)
              .backgroundColor(Theme.primary)
              .layoutWeight(1)
              .onClick(() => { this.handleAiSave(); })

            Button(this.tr('settings.aiClear'))
              .type(ButtonType.Capsule)
              .height(40)
              .fontSize(FontSize.body)
              .fontColor(Theme.error)
              .backgroundColor(Theme.surface)
              .border({ width: 1, color: Theme.error })
              .layoutWeight(1)
              .margin({ left: Space.md })
              .onClick(() => { this.confirmAiClear(); })
          }
          .width('100%')
          .padding({ left: Space.md, right: Space.md, top: Space.md, bottom: Space.md })
        }
        .width('100%')
        .constraintSize({ maxWidth: '100%' })
        .borderRadius(Radius.lg)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.borderSubtle })
        .margin({ left: Space.lg, right: Space.lg })

        // ── 功能组 ──
        SectionHeader({ title: this.tr('settings.sectionFeatures') })
          .padding({ left: Space.lg, right: Space.lg })

        Column() {
          UnsupportedRow({
            label: this.tr('settings.aiMemory'),
            value: this.tr('settings.notSupported')
          })
          Divider().color(Theme.divider)
            .width('100%')
            .constraintSize({ maxWidth: '100%' })
            .margin({ left: Space.md })
          UnsupportedRow({
            label: this.tr('settings.actionHistory'),
            value: this.tr('settings.notSupported')
          })
          Divider().color(Theme.divider)
            .width('100%')
            .constraintSize({ maxWidth: '100%' })
            .margin({ left: Space.md })
          UnsupportedRow({
            label: this.tr('settings.smartMonitor'),
            value: this.tr('settings.notSupported')
          })
          Divider().color(Theme.divider)
            .width('100%')
            .constraintSize({ maxWidth: '100%' })
            .margin({ left: Space.md })
          SettingRow({
            label: this.tr('settings.clearLocalData'),
            value: '',
            onItemClick: () => { this.confirmClearData(); }
          })
        }
        .width('100%')
        .constraintSize({ maxWidth: '100%' })
        .borderRadius(Radius.lg)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.borderSubtle })
        .margin({ left: Space.lg, right: Space.lg })

        // ── 退出登录（ghost 按钮）──
        Text(this.tr('settings.logout'))
          .fontSize(FontSize.label)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.error)
          .width('100%')
          .constraintSize({ maxWidth: '100%' })
          .textAlign(TextAlign.Center)
          .padding(Space.md)
          .borderRadius(Radius.lg)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.border })
          .margin({ left: Space.lg, right: Space.lg, top: Space.xl })
          .onClick(() => { this.confirmLogout(); })

        // ── 版本信息（读取自身应用包信息，禁止硬编码）──
        Column({ space: Space.xs }) {
          Text(this.versionText())
            .fontSize(FontSize.caption)
            .fontColor(Theme.textMuted)
          Text(this.tr('settings.platformLine'))
            .fontSize(FontSize.micro)
            .fontColor(Theme.textMuted)
        }
        .width('100%')
        .padding({ top: Space.lg, bottom: Space.xxl })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
    .scrollBar(BarState.Off)
    .bindSheet(this.sheetVisible, this.settingsSheetBuilder(), {
      height: this.sheetMode === 'ai' ? 340 : 260,
      showClose: true,
      dragBar: true,
      // 交互关闭（蒙层/下拉/关闭图标/返回）统一拦截：先进入本页关闭流程
      // （记录令牌 + visible=false），再执行关闭；框架不回写 visible
      shouldDismiss: (sheetDismiss: SheetDismiss) => {
        this.closeSettingsSheet();
        sheetDismiss.dismiss();
      },
      onDisappear: () => {
        // 令牌守卫：仅当本轮关闭未被更新的打开打断时才复位模式；
        // 过期关闭事件的 onDisappear 直接丢弃，不触碰新一轮弹层状态
        if (this.sheetClosingToken === this.sheetOpenToken) {
          this.sheetMode = '';
        }
      }
    })
  }

  /** 设置弹层内容：同一稳定节点上唯一一次 bindSheet，按模式切换 builder 内容 */
  @Builder
  settingsSheetBuilder() {
    if (this.sheetMode === 'ai') {
      Column() {
        Text(this.tr('settings.aiSelectPreset'))
          .fontSize(FontSize.h3)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
          .margin({ bottom: Space.md })

        ForEach(LLMService.presetIds(), (id: string) => {
          Button(this.presetLabel(id))
            .type(ButtonType.Normal)
            .width('100%')
            .height(44)
            .fontSize(FontSize.body)
            .fontColor(this.aiPreset === id ? Theme.textInvert : Theme.text)
            .backgroundColor(this.aiPreset === id ? Theme.primary : Theme.surfaceAlt)
            .borderRadius(Radius.sm)
            .margin({ top: Space.sm })
            .onClick(() => { this.selectAiPreset(id); })
        }, (id: string) => id)
      }
      .width('100%')
      .padding(Space.lg)
      .alignItems(HorizontalAlign.Start)
    } else {
      Column() {
        Text(this.tr('settings.selectLanguage'))
          .fontSize(FontSize.h3)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
          .margin({ bottom: Space.md })

        Button(this.tr('settings.langZh'))
          .type(ButtonType.Normal)
          .width('100%')
          .height(44)
          .fontSize(FontSize.body)
          .fontColor(this.locale === 'zh' ? Theme.textInvert : Theme.text)
          .backgroundColor(this.locale === 'zh' ? Theme.primary : Theme.surfaceAlt)
          .borderRadius(Radius.sm)
          .onClick(() => { this.selectLanguage('zh'); })

        Button(this.tr('settings.langEn'))
          .type(ButtonType.Normal)
          .width('100%')
          .height(44)
          .fontSize(FontSize.body)
          .fontColor(this.locale === 'en' ? Theme.textInvert : Theme.text)
          .backgroundColor(this.locale === 'en' ? Theme.primary : Theme.surfaceAlt)
          .borderRadius(Radius.sm)
          .margin({ top: Space.md })
          .onClick(() => { this.selectLanguage('en'); })
      }
      .width('100%')
      .padding(Space.lg)
      .alignItems(HorizontalAlign.Start)
    }
  }
}
