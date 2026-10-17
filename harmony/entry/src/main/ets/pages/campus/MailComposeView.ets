/**
 * ============================================================================
 * MailComposeView — 撰写并发送邮件（收件人/抄送/主题/正文）
 * ============================================================================
 *
 * 交互约定：
 *   - 必填校验（收件人、主题）：缺失时 toast 提示，不发请求。
 *   - 发送前 AlertDialog 二次确认。
 *   - 发送由父组件执行（onSend：真实模式调用 MailService.sendMail；
 *     失败抛可读中文错误）。
 *   - 失败保留已填内容并展示服务端消息（sendError）。
 * ============================================================================
 */
import { Theme, Space, Radius, FontSize } from '../Theme';
import { DetailHeader, StateBlock, StateTone } from '../../components/Ui';
import { ComposeDraft } from '../../services/campus/MailService';
import { I18n } from '../../utils/I18n';

@Component
export struct MailComposeView {
  /** 初始草稿（预填收件人等） */
  initialDraft: ComposeDraft = new ComposeDraft();
  /** 发送（父组件执行服务调用；失败抛可读中文错误，已填内容保留） */
  onSend: (draft: ComposeDraft) => Promise<void> =
    (_draft: ComposeDraft): Promise<void> => Promise.resolve();
  /** 发送成功回调（父组件返回列表并提示） */
  onSent: () => void = () => {};
  onBack: () => void = () => {};

  /** 语言订阅：新增可见文案走 i18n（语言切换即时重渲染） */
  @StorageLink('locale') locale: string = 'zh';

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  @State toInput: string = '';
  @State ccInput: string = '';
  @State subjectInput: string = '';
  @State contentInput: string = '';
  @State sending: boolean = false;
  @State sendError: string = '';

  aboutToAppear(): void {
    this.toInput = this.initialDraft.to;
    this.ccInput = this.initialDraft.cc;
    this.subjectInput = this.initialDraft.subject;
    this.contentInput = this.initialDraft.content;
  }

  private buildDraft(): ComposeDraft {
    const draft: ComposeDraft = new ComposeDraft();
    draft.to = this.toInput.trim();
    draft.cc = this.ccInput.trim();
    draft.bcc = '';
    draft.subject = this.subjectInput.trim();
    draft.content = this.contentInput;
    return draft;
  }

  /** 必填校验：收件人、主题 */
  private validateDraft(draft: ComposeDraft): boolean {
    if (draft.to.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: this.tr('mail.compose.toRequired'), duration: 2000 });
      return false;
    }
    if (draft.subject.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: this.tr('mail.compose.subjectRequired'), duration: 2000 });
      return false;
    }
    return true;
  }

  /** 发送前二次确认（必填校验通过后才弹确认框） */
  private confirmSend(): void {
    if (this.sending) {
      return;
    }
    const draft: ComposeDraft = this.buildDraft();
    if (!this.validateDraft(draft)) {
      return;
    }
    AlertDialog.show({
      title: this.tr('mail.compose.sendTitle'),
      message: this.tr('mail.compose.sendConfirmMessage'),
      primaryButton: {
        value: this.tr('common.cancel'),
        action: (): void => {},
      },
      secondaryButton: {
        value: this.tr('mail.compose.sendConfirmOk'),
        action: (): void => {
          this.doSend(draft);
        },
      },
    });
  }

  private async doSend(draft: ComposeDraft): Promise<void> {
    this.sending = true;
    this.sendError = '';
    try {
      await this.onSend(draft);
      this.onSent();
    } catch (e) {
      // 失败保留已填内容并展示服务端可读原因
      this.sendError = e instanceof Error ? e.message : String(e);
    }
    this.sending = false;
  }

  // ── UI ────────────────────────────────

  @Builder
  private FieldLabel(label: string) {
    Text(label)
      .fontSize(FontSize.micro)
      .fontColor(Theme.textMuted)
      .width('100%')
      .padding({ left: 4 })
  }

  build() {
    Column() {
      DetailHeader({ title: this.tr('mail.compose.title'), onBack: () => { this.onBack(); } })
      Divider().color(Theme.divider)

      Scroll() {
        Column({ space: Space.sm }) {
          this.FieldLabel(this.tr('mail.compose.to'))
          TextInput({ placeholder: this.tr('mail.compose.toPlaceholder'), text: this.toInput })
            .fontSize(FontSize.body)
            .fontColor(Theme.text)
            .height(44)
            .width('100%')
            .constraintSize({ maxWidth: '100%' })
            .backgroundColor(Theme.surface)
            .borderRadius(Radius.sm)
            .padding({ left: Space.md, right: Space.md })
            .onChange((value: string) => {
              this.toInput = value;
            })

          this.FieldLabel(this.tr('mail.compose.cc'))
          TextInput({ placeholder: this.tr('mail.compose.ccPlaceholder'), text: this.ccInput })
            .fontSize(FontSize.body)
            .fontColor(Theme.text)
            .height(44)
            .width('100%')
            .constraintSize({ maxWidth: '100%' })
            .backgroundColor(Theme.surface)
            .borderRadius(Radius.sm)
            .padding({ left: Space.md, right: Space.md })
            .onChange((value: string) => {
              this.ccInput = value;
            })

          this.FieldLabel(this.tr('mail.compose.subject'))
          TextInput({ placeholder: this.tr('mail.compose.subjectPlaceholder'), text: this.subjectInput })
            .fontSize(FontSize.body)
            .fontColor(Theme.text)
            .height(44)
            .width('100%')
            .constraintSize({ maxWidth: '100%' })
            .backgroundColor(Theme.surface)
            .borderRadius(Radius.sm)
            .padding({ left: Space.md, right: Space.md })
            .onChange((value: string) => {
              this.subjectInput = value;
            })

          this.FieldLabel(this.tr('mail.compose.content'))
          TextArea({ placeholder: this.tr('mail.compose.contentPlaceholder'), text: this.contentInput })
            .fontSize(FontSize.body)
            .fontColor(Theme.text)
            .width('100%')
            .constraintSize({ maxWidth: '100%', minHeight: 160 })
            .backgroundColor(Theme.surface)
            .borderRadius(Radius.sm)
            .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
            .onChange((value: string) => {
              this.contentInput = value;
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(Space.md)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      if (this.sendError.length > 0) {
        Column() {
          StateBlock({
            tone: StateTone.Error,
            message: this.sendError,
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: Space.md, right: Space.md, bottom: Space.sm })
      }

      Row() {
        Button(this.sending ? this.tr('mail.compose.sending') : this.tr('mail.compose.send'))
          .fontSize(FontSize.label)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textInvert)
          .backgroundColor(Theme.primary)
          .borderRadius(Radius.pill)
          .layoutWeight(1)
          .height(44)
          .enabled(!this.sending)
          .onClick(() => {
            this.confirmSend();
          })
      }
      .width('100%')
      .padding({ left: Space.md, right: Space.md, bottom: Space.md })
      // 上移，避免「发送」按钮被应用底部 Tab 栏遮挡
      .margin({ bottom: 72 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}
