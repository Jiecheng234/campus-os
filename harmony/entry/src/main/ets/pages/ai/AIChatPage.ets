import { Theme, SafeTop, Space, Radius, FontSize } from '../Theme';
import { ScreenHeader } from '../../components/Ui';
import { I18n } from '../../utils/I18n';

class ChatMessage {
  id: string = '';
  role: string = '';
  content: string = '';
  timestamp: string = '';
}

class AIModel {
  name: string = '';
  provider: string = '';
  icon: string = '';
}

const MOCK_MODELS: AIModel[] = [
  { name: 'DeepSeek V3', provider: 'deepseek', icon: '🧠' },
  { name: 'GPT-4o', provider: 'openai', icon: '🌟' },
  { name: 'Qwen-Max', provider: 'qwen', icon: '🚀' },
  { name: 'Moonshot', provider: 'moonshot', icon: '🌙' },
];

/** 推荐提问：词典键（渲染与发送时均经页面 tr() 按当前语言解析） */
const SUGGESTION_KEYS: string[] = [
  'ai.suggest.schedule',
  'ai.suggest.classroom',
  'ai.suggest.ddl',
  'ai.suggest.grades',
  'ai.suggest.card',
];

function getNowStr(): string {
  const d: Date = new Date();
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

function generateId(): string {
  return String(Date.now()) + String(Math.floor(Math.random() * 1000));
}

@Component
struct MessageBubble {
  @Prop message: ChatMessage = new ChatMessage();

  build() {
    Row() {
      if (this.message.role === 'assistant') {
        Column() {
          Text('🤖')
            .fontSize(14)
            .width(32)
            .height(32)
            .textAlign(TextAlign.Center)
            .borderRadius(16)
            .backgroundColor('rgba(124,92,250,0.10)')
        }
        .margin({ right: 8 })
      }
      Column() {
        Text(this.message.content)
          .fontSize(14)
          .fontColor(Theme.text)
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .borderRadius(16)
          .backgroundColor(this.message.role === 'user' ?
            Theme.primary : Theme.surfaceAlt)
          .constraintSize({ maxWidth: '75%' })
        if (this.message.role === 'user') {
          Text(this.message.timestamp)
            .fontSize(10)
            .fontColor(Theme.textMuted)
            .margin({ top: 2, right: 4 })
        } else {
          Text(this.message.timestamp)
            .fontSize(10)
            .fontColor(Theme.textMuted)
            .margin({ top: 2, left: 4 })
        }
      }
      .alignItems(this.message.role === 'user' ? HorizontalAlign.End : HorizontalAlign.Start)

      if (this.message.role === 'user') {
        Blank()
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
    .justifyContent(this.message.role === 'user' ? FlexAlign.End : FlexAlign.Start)
  }
}

@Component
struct ModelSelector {
  @Prop models: AIModel[] = [];
  @Link selectedIndex: number;

  build() {
    Row() {
      ForEach(this.models, (model: AIModel, index: number) => {
        Row() {
          Text(model.icon + ' ' + model.name)
            .fontSize(12)
            .fontColor(this.selectedIndex === index ? Theme.primary : Theme.textSecondary)
        }
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .borderRadius(999)
        .backgroundColor(this.selectedIndex === index ? 'rgba(124,92,250,0.10)' : Theme.surfaceAlt)
        .border({
          width: this.selectedIndex === index ? 1 : 0,
          color: Theme.primary
        })
        .margin({ right: 8 })
        .onClick(() => {
          this.selectedIndex = index;
        })
      })
    }
    .padding({ left: 16, right: 16 })
  }
}

@Component
export struct AIChatPage {
  /** 语言订阅：语言切换即时重渲染 */
  @StorageLink('locale') locale: string = 'zh';

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  @State messages: ChatMessage[] = [];
  @State inputText: string = '';
  @State selectedModel: number = 0;
  @State isTyping: boolean = false;
  @State hasStarted: boolean = false;
  private models: AIModel[] = MOCK_MODELS;

  addUserMessage(text: string): void {
    const msg: ChatMessage = new ChatMessage();
    msg.id = generateId();
    msg.role = 'user';
    msg.content = text;
    msg.timestamp = getNowStr();
    this.messages = this.messages.concat([msg]);
  }

  addAssistantMessage(text: string): void {
    const msg: ChatMessage = new ChatMessage();
    msg.id = generateId();
    msg.role = 'assistant';
    msg.content = text;
    msg.timestamp = getNowStr();
    this.messages = this.messages.concat([msg]);
  }

  getMockResponse(prompt: string): string {
    // 中英文关键词均可命中（英文建议在 en 模式下发送，保持 mock 应答行为一致）
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
    if (prompt.indexOf('校园卡') >= 0 || prompt.indexOf('余额') >= 0 || p.indexOf('card') >= 0 || p.indexOf('balance') >= 0) {
      return this.tr('ai.mockCard');
    }
    return this.tr('ai.mockDefault');
  }

  sendMessage(): void {
    const text: string = this.inputText.trim();
    if (text.length === 0 || this.isTyping) {
      return;
    }
    this.hasStarted = true;
    this.inputText = '';
    this.addUserMessage(text);

    this.isTyping = true;
    const response: string = this.getMockResponse(text);

    setTimeout(() => {
      this.isTyping = false;
      this.addAssistantMessage(response);
    }, 800 + Math.floor(Math.random() * 600));
  }

  startNewChat(): void {
    this.messages = [];
    this.hasStarted = false;
    this.isTyping = false;
  }

  @Builder
  newChatButton() {
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

  build() {
    Column() {
      SafeTop()

      Column() {
        ScreenHeader({
          eyebrow: this.tr('ai.eyebrow'),
          title: this.tr('ai.title'),
          right: (): void => this.newChatButton()
        })
      }
      .width('100%')
      .padding({ left: Space.lg, right: Space.md, top: Space.lg, bottom: Space.sm })

      Divider().color(Theme.divider)

      ModelSelector({ models: this.models, selectedIndex: $selectedModel })
      Divider().color(Theme.divider).margin({ top: 8 })

      if (this.hasStarted) {
        Scroll() {
          Column() {
            ForEach(this.messages, (msg: ChatMessage) => {
              MessageBubble({ message: msg })
            })

            if (this.isTyping) {
              Row() {
                Column() {
                  Text('🤖')
                    .fontSize(14)
                    .width(32)
                    .height(32)
                    .textAlign(TextAlign.Center)
                    .borderRadius(16)
                    .backgroundColor('rgba(124,92,250,0.10)')
                }
                .margin({ right: 8 })

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
              .padding({ left: 16, right: 16, top: 10 })
              .justifyContent(FlexAlign.Start)
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
          .enabled(!this.isTyping)
          .onChange((v: string) => {
            this.inputText = v;
          })

        Button(this.tr('ai.send'))
          .type(ButtonType.Capsule)
          .height(44)
          .fontSize(14)
          .fontColor(Theme.textInvert)
          .backgroundColor(Theme.primary)
          .borderRadius(22)
          .margin({ left: 8 })
          .enabled(this.inputText.trim().length > 0 && !this.isTyping)
          .onClick(() => {
            this.sendMessage();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 16 })
      .backgroundColor(Theme.surface)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}
