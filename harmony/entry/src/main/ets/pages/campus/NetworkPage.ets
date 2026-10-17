/**
 * NetworkPage — 校园网络（核心：余额/用量 + 账户信息 + 在线设备 + 设备注销）
 * 真实模式：WebVPN 校园网自助服务快照 + 单设备注销（对齐原项目 CampusNetworkScreen）；
 * 演示模式：内置示例数据，零网络请求。
 * 验证码登录：命中 NetworkCaptchaRequiredError 进入验证码态，页内取图（data URI）
 * + 输入提交（loginNetworkWithCaptcha），成功自动重载退出，失败自动换图清输入。
 */
import { Theme, SafeTop, Space } from '../Theme';
import { DetailHeader } from '../../components/Ui';
import { SessionManager } from '../../services/auth/SessionManager';
import { CampusNetworkService, NetworkAccountInfo, NetworkBalance, NetworkDevice,
  NetworkLogoutResult, NetworkSnapshot, isNetworkCaptchaRequiredError } from '../../services/campus/CampusNetworkService';
import { AuthManager } from '../../state/AuthManager';
import { StateManager } from '../../state/StateManager';
import { I18n } from '../../utils/I18n';

/** IP/MAC/账号打码（空→'—'；≤4→'****'；否则 ab***yz，对齐原项目 mask） */
function mask(value: string): string {
  if (value.length === 0) {
    return '—';
  }
  if (value.length <= 4) {
    return '****';
  }
  return value.substring(0, 2) + '***' + value.substring(value.length - 2);
}

function mockDevice(key: number, ip4: string, ip6: string, loggedAt: string,
  authPermission: string, mac: string): NetworkDevice {
  const device: NetworkDevice = new NetworkDevice();
  device.key = key;
  device.ip4 = ip4;
  device.ip6 = ip6;
  device.loggedAt = loggedAt;
  device.authPermission = authPermission;
  device.mac = mac;
  return device;
}

@Component
export struct NetworkPage {
  onBack: () => void = () => {};
  /** 语言订阅：新增可见文案走 i18n（语言切换即时重渲染） */
  @StorageLink('locale') locale: string = 'zh';
  @State balance: NetworkBalance = new NetworkBalance();
  @State account: NetworkAccountInfo = new NetworkAccountInfo();
  @State devices: NetworkDevice[] = [];
  @State loaded: boolean = false;
  @State loading: boolean = false;
  @State errorText: string = '';
  @State captchaRequired: boolean = false;
  /** 验证码图片 data URI（'' = 未取到/取图失败） */
  @State captchaImage: string = '';
  /** 验证码输入内容 */
  @State captchaInput: string = '';
  /** 验证码图片获取中 */
  @State captchaLoading: boolean = false;
  /** 验证码登录提交中 */
  @State captchaSubmitting: boolean = false;
  /** 注销进行中的设备 key（-1 = 无） */
  @State busyKey: number = -1;
  private isReal: boolean = false;

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  private trp(key: string, args: Record<string, string>): string {
    return I18n.tp(key, args, this.locale);
  }

  aboutToAppear(): void {
    this.isReal = AuthManager.isLoggedIn() && !StateManager.isDemoMode();
    if (this.isReal) {
      this.load();
    } else {
      this.applyMock();
    }
  }

  private applyMock(): void {
    const balance: NetworkBalance = new NetworkBalance();
    balance.productName = '校园网标准套餐';
    balance.usedBytes = '42.50 GB';
    balance.usedSeconds = '168 小时';
    balance.accountBalance = '15.80';
    balance.settlementDate = '2026-10-01';
    this.balance = balance;

    const account: NetworkAccountInfo = new NetworkAccountInfo();
    account.username = 'wangj23';
    account.contactEmail = 'wangj23@mails.tsinghua.edu.cn';
    account.contactPhone = '138****1234';
    account.contactLandline = '010-6279****';
    account.realName = '王小明';
    account.status = '正常';
    account.userGroup = '学生组';
    account.location = '紫荆公寓';
    account.allowedDevices = 3;
    this.account = account;

    const devices: NetworkDevice[] = [];
    devices.push(mockDevice(1, '10.10.1.23', '166.111:8::23', '2026-10-10 21:18', '校园网出线', 'AA:BB:CC:DD:EE:01'));
    devices.push(mockDevice(2, '10.10.1.45', '166.111:8::45', '2026-10-11 08:32', '校园网出线', 'AA:BB:CC:DD:EE:02'));
    this.devices = devices;

    this.loaded = true;
    this.errorText = '';
    this.captchaRequired = false;
  }

  private async load(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.errorText = '';
    this.captchaRequired = false;
    try {
      const service: CampusNetworkService = SessionManager.getNetworkService();
      const snapshot: NetworkSnapshot = await service.getNetworkSnapshot();
      this.balance = snapshot.balance;
      this.account = snapshot.account;
      this.devices = snapshot.devices;
      this.loaded = true;
    } catch (e) {
      if (isNetworkCaptchaRequiredError(e)) {
        this.captchaRequired = true;
        // 进入验证码态自动取图（失败仅 toast，可手动"换一张"重试）
        this.refreshCaptcha();
      } else {
        this.errorText = e instanceof Error ? e.message : String(e);
      }
    }
    this.loading = false;
  }

  /** 获取/刷新验证码图片（点击图片或"换一张"可手动触发） */
  private async refreshCaptcha(): Promise<void> {
    if (!this.isReal || this.captchaLoading) {
      return;
    }
    this.captchaLoading = true;
    try {
      const service: CampusNetworkService = SessionManager.getNetworkService();
      this.captchaImage = await service.fetchCaptchaImage();
    } catch (e) {
      this.captchaImage = '';
      const message: string = e instanceof Error ? e.message : String(e);
      this.getUIContext().getPromptAction().showToast({
        message: this.trp('campus.network.captchaFailed', { 'msg': message }),
        duration: 2000,
      });
    }
    this.captchaLoading = false;
  }

  /** 提交验证码登录：成功 → toast + 退出验证码态 + 重载数据；失败 → toast + 自动换图 + 清空输入 */
  private async submitCaptcha(): Promise<void> {
    if (!this.isReal || this.captchaSubmitting) {
      return;
    }
    if (this.captchaInput.trim().length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: this.tr('campus.network.captchaEmpty'), duration: 2000 });
      return;
    }
    this.captchaSubmitting = true;
    try {
      const service: CampusNetworkService = SessionManager.getNetworkService();
      await service.loginNetworkWithCaptcha(this.captchaInput);
      this.captchaInput = '';
      this.captchaImage = '';
      this.captchaRequired = false;
      this.getUIContext().getPromptAction().showToast({ message: this.tr('campus.network.loginSuccess'), duration: 2000 });
      await this.load();
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e);
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2500 });
      // 失败自动换图并清空输入（验证码一次性，旧图作废）
      this.captchaInput = '';
      await this.refreshCaptcha();
    }
    this.captchaSubmitting = false;
  }

  private refresh(): void {
    if (this.isReal) {
      this.load();
    } else {
      this.applyMock();
    }
  }

  /** 注销二次确认（取消 / 确认注销；文案含权限、掩码 IP/MAC 与断网提示） */
  private confirmLogout(device: NetworkDevice): void {
    AlertDialog.show({
      title: this.tr('campus.network.logoutTitle'),
      message: `${device.authPermission}\n${mask(device.ip4)} · ${mask(device.mac)}\n\n${this.tr('campus.network.logoutWarning')}`,
      primaryButton: {
        value: this.tr('common.cancel'),
        action: (): void => {},
      },
      secondaryButton: {
        value: this.tr('campus.network.logoutOk'),
        fontColor: Theme.error,
        action: (): void => { this.doLogout(device); },
      },
    });
  }

  private async doLogout(device: NetworkDevice): Promise<void> {
    if (!this.isReal) {
      // 演示模式：本地移除，零网络请求
      const rest: NetworkDevice[] = [];
      for (let i: number = 0; i < this.devices.length; i++) {
        if (this.devices[i].key !== device.key) {
          rest.push(this.devices[i]);
        }
      }
      this.devices = rest;
      this.getUIContext().getPromptAction().showToast({ message: this.tr('campus.network.loggedOutToast'), duration: 2000 });
      return;
    }
    this.busyKey = device.key;
    try {
      const service: CampusNetworkService = SessionManager.getNetworkService();
      const result: NetworkLogoutResult = await service.logoutNetworkDevice(device.key, device.mac);
      this.getUIContext().getPromptAction().showToast({ message: result.message, duration: 2000 });
      await this.load();
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e);
      this.getUIContext().getPromptAction().showToast({
        message: this.trp('campus.network.logoutFailed', { 'msg': message }),
        duration: 2000,
      });
    }
    this.busyKey = -1;
  }

  @Builder RightAction() {
    if (this.loading) {
      LoadingProgress()
        .width(20)
        .height(20)
        .color(Theme.primary)
    } else {
      Text(this.tr('common.refresh'))
        .fontSize(14)
        .fontColor(Theme.primary)
        .padding({ left: 12, right: 4, top: 8, bottom: 8 })
        .onClick(() => { this.refresh(); })
    }
  }

  @Builder SectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(Theme.textSecondary)
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 8 })
  }

  @Builder InfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(Theme.textSecondary)
        .layoutWeight(1)
      Text(value.length > 0 ? value : '—')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }

  build() {
    Column() {
      SafeTop()

      DetailHeader({
        title: this.tr('campus.network.pageTitle'),
        onBack: () => { this.onBack(); },
        right: (): void => { this.RightAction(); },
      })

      Divider().color(Theme.divider)

      if (!this.isReal) {
        Text(this.tr('campus.network.demoHint'))
          .fontSize(12)
          .fontColor(Theme.textMuted)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 8, bottom: 0 })
      }

      Scroll() {
        Column() {
          // 余额/用量 Hero 卡
          Column() {
            Text(this.tr('campus.network.balance'))
              .fontSize(13)
              .fontColor(Theme.textMuted)
            Row() {
              if (this.loading && !this.loaded) {
                LoadingProgress()
                  .width(28)
                  .height(28)
                  .color(Theme.primary)
              } else {
                Text(this.balance.accountBalance.length > 0 ? this.balance.accountBalance : '—')
                  .fontSize(40)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Theme.primary)
                Text(this.tr('campus.network.yuan'))
                  .fontSize(16)
                  .fontColor(Theme.textMuted)
                  .margin({ left: 6, bottom: 6 })
              }
            }
            .alignItems(VerticalAlign.Bottom)
            .margin({ top: 8 })

            if (this.balance.productName.length > 0) {
              Text(this.balance.productName)
                .fontSize(13)
                .fontColor(Theme.text)
                .margin({ top: 6 })
            }

            Row() {
              Text(this.tr('campus.network.usedBytes'))
                .fontSize(13)
                .fontColor(Theme.textMuted)
              Blank()
              Text(this.balance.usedBytes)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.text)
            }
            .width('100%')
            .margin({ top: 16 })

            Row() {
              Text(this.tr('campus.network.usedTime'))
                .fontSize(13)
                .fontColor(Theme.textMuted)
              Blank()
              Text(this.balance.usedSeconds)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.text)
            }
            .width('100%')
            .margin({ top: 10 })

            if (this.balance.settlementDate.length > 0) {
              Text(this.trp('campus.network.settlementDate', { 'name': this.balance.settlementDate }))
                .fontSize(12)
                .fontColor(Theme.textMuted)
                .margin({ top: 12 })
            }
          }
          .width('100%')
          .constraintSize({ maxWidth: '100%' })
          .padding(20)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16, top: 16 })
          .alignItems(HorizontalAlign.Center)

          // 错误态（会话两次恢复仍失败等，可重试）
          if (this.errorText.length > 0) {
            Column({ space: Space.sm }) {
              Text(this.tr('campus.network.errorTitle'))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.text)
              Text(this.errorText)
                .fontSize(13)
                .fontColor(Theme.textMuted)
                .textAlign(TextAlign.Center)
              Text(this.tr('status.retry'))
                .fontSize(13)
                .fontColor(Theme.primary)
                .padding({ left: Space.md, right: Space.md, top: Space.xs, bottom: Space.xs })
                .borderRadius(8)
                .border({ width: 1, color: Theme.primary })
                .onClick(() => { this.load(); })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ left: 16, right: 16, bottom: 8, top: 16 })
          }

          // 验证码登录态（取图 + 输入 + 提交/换一张；成功自动重载，失败自动换图）
          if (this.captchaRequired) {
            Column({ space: Space.sm }) {
              Text(this.tr('campus.network.captchaTitle'))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.text)
              Text(this.tr('campus.network.captchaHint'))
                .fontSize(13)
                .fontColor(Theme.textMuted)
                .textAlign(TextAlign.Center)

              if (this.captchaLoading) {
                LoadingProgress()
                  .width(32)
                  .height(32)
                  .color(Theme.primary)
                  .margin({ top: 4, bottom: 4 })
              } else if (this.captchaImage.length > 0) {
                Image(this.captchaImage)
                  .height(44)
                  .objectFit(ImageFit.Contain)
                  .borderRadius(6)
                  .border({ width: 1, color: Theme.borderSubtle })
                  .margin({ top: 4, bottom: 4 })
                  .onClick(() => { this.refreshCaptcha(); })
              } else {
                Text(this.tr('campus.network.getCaptcha'))
                  .fontSize(13)
                  .fontColor(Theme.primary)
                  .padding({ left: Space.md, right: Space.md, top: 10, bottom: 10 })
                  .borderRadius(8)
                  .border({ width: 1, color: Theme.primary })
                  .margin({ top: 4, bottom: 4 })
                  .onClick(() => { this.refreshCaptcha(); })
              }

              Row({ space: Space.sm }) {
                TextInput({ placeholder: this.tr('campus.network.captchaPlaceholder'), text: this.captchaInput })
                  .type(InputType.Normal)
                  .fontSize(14)
                  .height(40)
                  .layoutWeight(1)
                  .enabled(!this.captchaSubmitting)
                  .onChange((v: string) => { this.captchaInput = v; })
                  .onSubmit(() => { this.submitCaptcha(); })
                Text(this.tr('campus.network.refreshCaptcha'))
                  .fontSize(13)
                  .fontColor(Theme.primary)
                  .padding({ left: 4, right: 4, top: 10, bottom: 10 })
                  .enabled(!this.captchaSubmitting && !this.captchaLoading)
                  .onClick(() => { this.refreshCaptcha(); })
              }
              .width('100%')

              Button(this.captchaSubmitting
                ? this.tr('campus.network.loggingIn')
                : this.tr('campus.network.loginButton'))
                .type(ButtonType.Capsule)
                .height(40)
                .fontSize(14)
                .fontColor(Theme.textInvert)
                .backgroundColor(Theme.primary)
                .padding({ left: Space.xl, right: Space.xl })
                .enabled(!this.captchaSubmitting && this.captchaInput.trim().length > 0)
                .onClick(() => { this.submitCaptcha(); })

              Text(this.tr('campus.network.retryQuery'))
                .fontSize(12)
                .fontColor(Theme.textMuted)
                .padding({ top: 2, bottom: 2 })
                .onClick(() => { this.load(); })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ left: 16, right: 16, bottom: 8, top: 16 })
          }

          // 账户信息（9 字段）
          if (this.loaded) {
            this.SectionTitle(this.tr('campus.network.accountInfo'))
            Column() {
              this.InfoRow(this.tr('campus.network.username'), this.account.username)
              Divider().color(Theme.divider).margin({ left: 16 })
              this.InfoRow(this.tr('campus.network.contactEmail'), this.account.contactEmail)
              Divider().color(Theme.divider).margin({ left: 16 })
              this.InfoRow(this.tr('campus.network.contactPhone'), this.account.contactPhone)
              Divider().color(Theme.divider).margin({ left: 16 })
              this.InfoRow(this.tr('campus.network.contactLandline'), this.account.contactLandline)
              Divider().color(Theme.divider).margin({ left: 16 })
              this.InfoRow(this.tr('campus.network.realName'), this.account.realName)
              Divider().color(Theme.divider).margin({ left: 16 })
              this.InfoRow(this.tr('campus.network.userGroup'), this.account.userGroup)
              Divider().color(Theme.divider).margin({ left: 16 })
              this.InfoRow(this.tr('campus.network.status'), this.account.status)
              Divider().color(Theme.divider).margin({ left: 16 })
              this.InfoRow(this.tr('campus.network.location'), this.account.location)
              Divider().color(Theme.divider).margin({ left: 16 })
              this.InfoRow(this.tr('campus.network.allowedDevices'), String(this.account.allowedDevices))
            }
            .width('100%')
            .constraintSize({ maxWidth: '100%' })
            .borderRadius(Theme.cardRadius)
            .backgroundColor(Theme.surface)
            .border({ width: 1, color: Theme.borderSubtle })
            .margin({ left: 16, right: 16 })
          }

          // 在线设备
          this.SectionTitle(this.tr('campus.network.devices'))
          Column() {
            if (this.loading && !this.loaded) {
              Row({ space: Space.sm }) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color(Theme.primary)
                Text(this.tr('campus.network.loadingDevices'))
                  .fontSize(13)
                  .fontColor(Theme.textMuted)
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ top: 20, bottom: 20 })
            } else if (this.devices.length === 0) {
              Column({ space: Space.xs }) {
                Text(this.tr('campus.network.emptyDevicesTitle'))
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.text)
                Text(this.tr('campus.network.emptyDevicesMessage'))
                  .fontSize(12)
                  .fontColor(Theme.textMuted)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 20, bottom: 20 })
            } else {
              ForEach(this.devices, (device: NetworkDevice, index: number) => {
                Column() {
                  Row() {
                    Column({ space: 3 }) {
                      Text(device.authPermission.length > 0 ? device.authPermission : this.tr('campus.network.deviceFallback'))
                        .fontSize(14)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(Theme.text)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(this.trp('campus.network.ip4', { 'name': device.ip4.length > 0 ? device.ip4 : '—' }))
                        .fontSize(12)
                        .fontColor(Theme.textMuted)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(this.trp('campus.network.ip6', { 'name': device.ip6.length > 0 ? device.ip6 : '—' }))
                        .fontSize(12)
                        .fontColor(Theme.textMuted)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(this.trp('campus.network.loginTime', { 'name': device.loggedAt.length > 0 ? device.loggedAt : '—' }))
                        .fontSize(12)
                        .fontColor(Theme.textMuted)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(this.trp('campus.network.mac', { 'name': device.mac.length > 0 ? device.mac : '—' }))
                        .fontSize(12)
                        .fontColor(Theme.textMuted)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    Button(this.busyKey === device.key
                      ? this.tr('campus.network.processing')
                      : this.tr('campus.network.logout'))
                      .type(ButtonType.Capsule)
                      .fontSize(11)
                      .fontColor(Theme.error)
                      .backgroundColor('rgba(220,38,38,0.08)')
                      .enabled(this.busyKey < 0)
                      .margin({ left: 12 })
                      .onClick(() => { this.confirmLogout(device); })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding({ left: 16, right: 16, top: 12, bottom: 12 })

                if (index < this.devices.length - 1) {
                  Divider().color(Theme.divider).margin({ left: 16 })
                }
              }, (device: NetworkDevice, index: number) => device.key.toString() + '-' + index.toString())
            }
          }
          .width('100%')
          .constraintSize({ maxWidth: '100%' })
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16, bottom: 24 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}
