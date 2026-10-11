/**
 * SettingsPage — 设置页（对齐原项目 SettingsScreen：组标题 + 白卡行组）
 *
 * 功能对接（settings-integration 特性）：
 *  - 偏好项（演示模式/信任设备/语言）经 SettingsManager 写入即持久化；
 *    演示模式写内存即全应用生效（状态对象为单一事实源）。
 *  - 全部文案走 I18n（@StorageLink('locale') 订阅语言即时重渲染）。
 *  - 账号信息只读展示（学号取自本地凭证）；未登录/演示模式展示状态文案。
 *  - 退出登录：AlertDialog 二次确认 → 注销会话 + 清除本地凭证。
 *  - 数据清理：AI 会话 / 学习缓存（AlertDialog 二次确认 + 结果提示）。
 *  - 版本号读取自身应用包信息（bundleManager，禁止硬编码）。
 *  - "AI 记忆 / 操作记录 / 智能监控"标注"暂不支持"（禁用态，无跳转）。
 */
import { Theme, SafeTop, Space, Radius, FontSize } from './Theme';
import { ScreenHeader, SectionHeader, InfoRow } from '../components/Ui';
import { bundleManager } from '@kit.AbilityKit';
import { SettingsManager } from '../state/SettingsManager';
import { AuthManager } from '../state/AuthManager';
import { SessionManager } from '../services/auth/SessionManager';
import { SecureStorage, SecureCredentials } from '../storage/SecureStorage';
import { LocalDataCleaner } from '../storage/LocalDataCleaner';
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
  @State showLangDialog: boolean = false;
  @State demoMode: boolean = false;
  @State trustDevice: boolean = false;
  @State isSignedIn: boolean = false;
  @State accountStudentId: string = '';
  @State versionName: string = '';

  aboutToAppear(): void {
    this.demoMode = SettingsManager.isDemoMode();
    this.trustDevice = SettingsManager.isTrustDevice();
    this.isSignedIn = AuthManager.isLoggedIn();
    this.loadAccountStudentId();
    this.loadVersionInfo();
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
    this.showLangDialog = false;
  }

  // ============================================================
  // 退出登录：二次确认 → 注销会话 + 清除本地凭证 → 可读提示
  // ============================================================

  private confirmLogout(): void {
    this.getUIContext().showAlertDialog({
      title: this.tr('settings.logoutConfirmTitle'),
      message: this.tr('settings.logoutConfirmMessage'),
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
      await SessionManager.logout();
      await SecureStorage.clearCredentials();
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
            onItemClick: () => { this.showLangDialog = true; }
          })
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
    .bindSheet($$this.showLangDialog, this.langSheetBuilder(), {
      height: 260,
      showClose: true,
      dragBar: true,
    })
  }

  @Builder
  langSheetBuilder() {
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
