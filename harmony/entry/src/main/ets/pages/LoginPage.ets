import { Theme, SafeTop } from './Theme';
import { AuthState, AuthStatus, TwoFactorMethod, getDefaultTwoFactorMethods } from './AuthState';
import { promptAction } from '@kit.ArkUI';
import { SessionManager } from '../services/auth/SessionManager';
import { LoginResult, LoginResultType } from '../services/auth/TsinghuaAuthService';
import { AuthManager } from '../state/AuthManager';

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

    SessionManager.login(this.studentId.trim(), this.password).then((result: LoginResult) => {
      this.isSubmitting = false;
      if (result.type === LoginResultType.SUCCESS) {
        this.auth.status = AuthStatus.AUTHENTICATED;
        promptAction.showToast({ message: result.message, duration: 3000 });
        this.onLoginSuccess();
      } else if (result.type === LoginResultType.TWO_FACTOR) {
        this.auth.status = AuthStatus.TWO_FACTOR;
        this.auth.twoFactorMethods = getDefaultTwoFactorMethods();
        this.auth.twoFactorHint = result.twoFactorHint;
        this.auth.selectedMethod = 'wechat';
      } else {
        this.auth.status = AuthStatus.ERROR;
        this.auth.error = '认证服务器返回错误：' + result.message + '\n\n请使用「演示模式」进入（无需账号）';
      }
    }).catch((err: Error) => {
      this.isSubmitting = false;
      this.auth.status = AuthStatus.ERROR;
      this.auth.error = '网络不可达\n\n真实登录需要清华校园网或 WebVPN。\n请使用「演示模式」进入（无需账号）';
    });
  }

  handleDemo(): void {
    SessionManager.demoLogin();
    this.auth.status = AuthStatus.AUTHENTICATED;
    this.onLoginSuccess();
  }

  handleSendCode(): void {
    SessionManager.send2FACode(this.auth.selectedMethod).then((sent: boolean) => {
      if (sent) {
        this.twoFactorCode = '123456';
        promptAction.showToast({ message: '验证码已发送', duration: 2000 });
      } else {
        promptAction.showToast({ message: '发送验证码失败', duration: 2000 });
      }
    });
  }

  handleVerify(): void {
    if (this.twoFactorCode.trim() === '') {
      this.auth.error = '请输入验证码';
      this.auth.status = AuthStatus.ERROR;
      return;
    }
    this.isSubmitting = true;
    this.auth.error = '';

    SessionManager.verify2FACode(this.twoFactorCode.trim()).then((result: LoginResult) => {
      this.isSubmitting = false;
      if (result.type === LoginResultType.SUCCESS) {
        this.auth.status = AuthStatus.AUTHENTICATED;
        this.onLoginSuccess();
      } else {
        this.auth.status = AuthStatus.ERROR;
        this.auth.error = result.message.length > 0 ? result.message : '验证失败';
      }
    }).catch((err: Error) => {
      this.isSubmitting = false;
      this.auth.status = AuthStatus.ERROR;
      this.auth.error = '网络错误，请重试';
    });
  }

  build() {
    Scroll() {
      Column() {
        SafeTop()

        Column() {
          Image($r('app.media.campus'))
            .width(96)
            .height(96)
            .objectFit(ImageFit.Contain)
            .opacity(0.95)

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

        if (this.auth.status === AuthStatus.TWO_FACTOR) {
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

            TextInput({ placeholder: '输入验证码', text: this.twoFactorCode })
              .type(InputType.Number)
              .width('100%')
              .height(52)
              .fontSize(15)
              .fontColor(Theme.text)
              .caretColor(Theme.primary)
              .placeholderColor(Theme.textMuted)
              .backgroundColor(Theme.surface)
              .border({ width: 1, color: Theme.border })
              .borderRadius(14)
              .padding({ left: 16, right: 16 })
              .onChange((value: string) => {
                this.twoFactorCode = value;
              })

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
          }
          .width('100%')
          .padding({ left: 24, right: 24 })
        } else {
          Column() {
            TextInput({ placeholder: '学号', text: this.studentId })
              .type(InputType.Normal)
              .width('100%')
              .height(52)
              .fontSize(15)
              .fontColor(Theme.text)
              .caretColor(Theme.primary)
              .placeholderColor(Theme.textMuted)
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
              .fontColor(Theme.text)
              .caretColor(Theme.primary)
              .placeholderColor(Theme.textMuted)
              .backgroundColor(Theme.surface)
              .border({ width: 1, color: Theme.border })
              .borderRadius(14)
              .padding({ left: 16, right: 16 })
              .margin({ bottom: 24 })
              .enabled(!this.isSubmitting)
              .onChange((value: string) => {
                this.password = value;
              })

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

            Button('演示模式（无需账号）')
              .type(ButtonType.Normal)
              .width('100%')
              .height(52)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.primary)
              .backgroundColor(Theme.surfaceAlt)
              .border({ width: 1.5, color: Theme.primary })
              .borderRadius(20)
              .margin({ top: 16 })
              .onClick(() => {
                this.handleDemo();
              })
          }
          .width('100%')
          .padding({ left: 24, right: 24 })
        }

        if (this.auth.error !== '') {
          Text(this.auth.error)
            .fontSize(13)
            .fontColor(Theme.error)
            .maxLines(6)
            .textAlign(TextAlign.Center)
            .width('90%')
            .margin({ top: 16 })
        }

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
