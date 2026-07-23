/**
 * LoginPage — 登录页（含二因子认证演示）
 */
import { Theme, SafeTop } from './Theme';
import { AuthState, AuthStatus, TwoFactorMethod, getDefaultTwoFactorMethods } from './AuthState';
import { promptAction } from '@kit.ArkUI';

@Component
export struct LoginPage {
  @State auth: AuthState = new AuthState();
  @State studentId: string = '';
  @State password: string = '';
  @State twoFactorCode: string = '';
  @State isSubmitting: boolean = false;
  @State loggedIn: boolean = false;

  onLoginSuccess: () => void = () => {};

  handleLogin(): void {
    if (this.isSubmitting) {
      return;
    }
    if (this.studentId.trim() === '' || this.password.trim() === '') {
      this.auth.status = AuthStatus.ERROR;
      this.auth.error = '请输入学号和密码';
      return;
    }

    this.isSubmitting = true;
    this.auth.status = AuthStatus.AUTHENTICATING;
    this.auth.error = '';

    // 模拟网络请求 1.5 秒后进入二因子认证
    setTimeout(() => {
      this.auth.status = AuthStatus.TWO_FACTOR;
      this.auth.twoFactorMethods = getDefaultTwoFactorMethods();
      this.auth.twoFactorHint = '检测到新设备登录，需二次验证';
      this.auth.selectedMethod = 'wechat';
      this.isSubmitting = false;
    }, 1500);
  }

  handleDemo(): void {
    this.auth.status = AuthStatus.AUTHENTICATED;
    this.onLoginSuccess();
  }

  handleSendCode(): void {
    // 模拟发送：自动填入演示验证码并提示
    this.twoFactorCode = '123456';
    promptAction.showToast({ message: '验证码已发送（演示模式：123456）', duration: 2000 });
  }

  handleVerify(): void {
    if (this.twoFactorCode.trim() === '') {
      this.auth.error = '请输入验证码';
      this.auth.status = AuthStatus.ERROR;
      return;
    }
    this.isSubmitting = true;
    this.auth.error = '';

    // 模拟验证 1 秒后成功
    setTimeout(() => {
      this.auth.status = AuthStatus.AUTHENTICATED;
      this.isSubmitting = false;
      this.onLoginSuccess();
    }, 1000);
  }

  build() {
    Scroll() {
      Column() {
        SafeTop()

        Column() {
          // ── 校徽 ──
          Image($r('app.media.campus'))
            .width(96)
            .height(96)
            .objectFit(ImageFit.Contain)
            .opacity(0.95)

          // ── 标题 ──
          Text('CampusOS')
            .fontSize(34)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.primary)
            .letterSpacing(-0.6)
            .margin({ top: 24 })

          Text('清华校园 AI 操作系统')
            .fontSize(15)
            .fontColor(Theme.textSecondary)
            .margin({ top: 8, bottom: 40 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .margin({ top: 32 })

        // ── 表单区 ──
        if (this.auth.status === AuthStatus.TWO_FACTOR) {
          // 二因子认证 UI
          Column() {
            Text('二次认证')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.text)
              .margin({ bottom: 4 })

            if (this.auth.twoFactorHint !== '') {
              Text(this.auth.twoFactorHint)
                .fontSize(13)
                .fontColor(Theme.warning)
                .margin({ bottom: 16 })
            }

            // 方式选择 chips
            Row() {
              ForEach(this.auth.twoFactorMethods, (method: TwoFactorMethod) => {
                Text(method.label)
                  .fontSize(13)
                  .fontColor(this.auth.selectedMethod === method.type ?
                  Theme.primary : Theme.textSecondary)
                  .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                  .borderRadius(999)
                  .backgroundColor(this.auth.selectedMethod === method.type ?
                  'rgba(124,92,250,0.10)' : Theme.surface)
                  .border({
                    width: 1,
                    color: this.auth.selectedMethod === method.type ?
                    Theme.primary : Theme.border
                  })
                  .margin({ right: 8 })
                  .onClick(() => {
                    this.auth.selectedMethod = method.type;
                  })
              })
            }
            .width('100%')
            .margin({ bottom: 16 })

            // 发送验证码
            Button('发送验证码')
              .type(ButtonType.Normal)
              .width('100%')
              .height(52)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.primary)
              .backgroundColor(Theme.surface)
              .border({ width: 1, color: Theme.border })
              .borderRadius(20)
              .margin({ bottom: 16 })
              .onClick(() => {
                this.handleSendCode();
              })

            // 验证码输入
            TextInput({ placeholder: '输入验证码', text: this.twoFactorCode })
              .type(InputType.Number)
              .width('100%')
              .height(52)
              .fontSize(15)
              .backgroundColor(Theme.surface)
              .border({ width: 1, color: Theme.border })
              .borderRadius(14)
              .padding({ left: 16, right: 16 })
              .onChange((value: string) => {
                this.twoFactorCode = value;
              })

            // 验证按钮
            Button('验证')
              .type(ButtonType.Normal)
              .width('100%')
              .height(52)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textInvert)
              .backgroundColor(Theme.primary)
              .borderRadius(20)
              .margin({ top: 16 })
              .enabled(!this.isSubmitting)
              .onClick(() => {
                this.handleVerify();
              })

            Text('演示模式：点击"发送验证码"自动填入 123456')
              .fontSize(11)
              .fontColor(Theme.textMuted)
              .margin({ top: 8 })
          }
          .width('100%')
          .padding({ left: 24, right: 24 })
        } else {
          // 登录表单 UI
          Column() {
            TextInput({ placeholder: '学号', text: this.studentId })
              .type(InputType.Number)
              .width('100%')
              .height(52)
              .fontSize(15)
              .backgroundColor(Theme.surface)
              .border({ width: 1, color: Theme.border })
              .borderRadius(14)
              .padding({ left: 16, right: 16 })
              .margin({ bottom: 12 })
              .enabled(!this.isSubmitting)
              .onChange((value: string) => {
                this.studentId = value;
              })

            TextInput({ placeholder: '密码', text: this.password })
              .type(InputType.Password)
              .width('100%')
              .height(52)
              .fontSize(15)
              .backgroundColor(Theme.surface)
              .border({ width: 1, color: Theme.border })
              .borderRadius(14)
              .padding({ left: 16, right: 16 })
              .margin({ bottom: 24 })
              .enabled(!this.isSubmitting)
              .onChange((value: string) => {
                this.password = value;
              })

            // 登录按钮
            Button(this.auth.status === AuthStatus.AUTHENTICATING ? '登录中...' : '登  录')
              .type(ButtonType.Normal)
              .width('100%')
              .height(52)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textInvert)
              .backgroundColor(Theme.primary)
              .borderRadius(20)
              .enabled(!this.isSubmitting)
              .onClick(() => {
                this.handleLogin();
              })

            // Demo 按钮
            Button('演示模式')
              .type(ButtonType.Normal)
              .width('100%')
              .height(52)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.text)
              .backgroundColor(Theme.surface)
              .border({ width: 1, color: Theme.border })
              .borderRadius(20)
              .margin({ top: 12 })
              .onClick(() => {
                this.handleDemo();
              })
          }
          .width('100%')
          .padding({ left: 24, right: 24 })
        }

        // ── 错误信息 ──
        if (this.auth.error !== '') {
          Text(this.auth.error)
            .fontSize(13)
            .fontColor(Theme.error)
            .margin({ top: 16 })
        }

        // ── 底部 ──
        Column() {
          Text('部分功能需清华大学校园网')
            .fontSize(13)
            .fontColor(Theme.textMuted)

          Text('Campus OS v2.1.1')
            .fontSize(11)
            .fontColor(Theme.primary)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 4 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .margin({ top: 32, bottom: 48 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
    .scrollBar(BarState.Off)
  }
}
