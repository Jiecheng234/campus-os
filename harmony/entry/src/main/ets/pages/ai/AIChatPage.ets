import { Theme, SafeTop, Space, Radius, FontSize } from '../Theme';
import { ScreenHeader } from '../../components/Ui';

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

const SUGGESTIONS: string[] = [
  '今天有什么课？',
  '查一下空教室',
  '帮我添加一个DDL',
  '最近的成绩怎么样？',
  '校园卡还有多少钱？',
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
    if (prompt.indexOf('课') >= 0 || prompt.indexOf('课程') >= 0) {
      return '根据你的课表，今天有以下课程：\n\n🔹 8:00-9:35 高等数学(1) — 六教6A201\n🔹 10:10-11:45 大学物理B(2) — 四教4301\n🔹 13:30-15:05 线性代数 — 六教6B101\n\n需要我帮你查看课程详情或作业吗？';
    }
    if (prompt.indexOf('空教室') >= 0 || prompt.indexOf('教室') >= 0) {
      return '查询到当前时段以下教室空闲：\n\n🏫 六教：6A301, 6A302, 6A401, 6A402, 6B203\n🏫 四教：4303, 4304, 4402\n🏫 五教：5102, 5201, 5303\n\n共 11 间教室可用。需要预约吗？';
    }
    if (prompt.indexOf('DDL') >= 0 || prompt.indexOf('作业') >= 0) {
      return '你当前有 2 项待完成的作业：\n\n📝 高等数学(1) — 习题集第5章 — 截止：7月25日\n📝 大学物理B(2) — 实验报告2 — 截止：7月28日\n\n需要我帮你添加新的DDL吗？';
    }
    if (prompt.indexOf('成绩') >= 0 || prompt.indexOf('GPA') >= 0) {
      return '你的学业成绩概览：\n\n📊 本学期 GPA：3.72\n🏆 等级分布：A=3门, A-=2门, B+=1门, B=1门\n\n详细成绩可在「校园」→「成绩查询」中查看。';
    }
    if (prompt.indexOf('校园卡') >= 0 || prompt.indexOf('余额') >= 0) {
      return '你的校园卡信息：\n\n💰 当前余额：¥285.30\n💳 卡号：**** **** **** 6821\n📋 最近消费：紫荆园餐厅 -¥15.50\n\n余额充足，无需充值。';
    }
    return '我是 CampusOS AI 助手，可以帮你：\n\n📚 查询课表和学习任务\n🏫 查找空教室\n📊 查看成绩和 GPA\n💰 查询校园卡余额\n📝 管理 DDL 待办\n🌐 查询校园网状态\n\n有什么我可以帮你的吗？';
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
    Text('新建对话')
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
          eyebrow: 'AI ASSISTANT',
          title: 'AI 助手',
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

          Text('CampusOS AI')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.text)

          Text('你的清华校园智能助手')
            .fontSize(14)
            .fontColor(Theme.textMuted)
            .margin({ top: 6, bottom: 32 })

          Text('试试问我：')
            .fontSize(13)
            .fontColor(Theme.textMuted)
            .margin({ bottom: 12 })

          ForEach(SUGGESTIONS, (item: string) => {
            Text(item)
              .fontSize(14)
              .fontColor(Theme.primary)
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .borderRadius(999)
              .backgroundColor('rgba(124,92,250,0.06)')
              .border({ width: 1, color: 'rgba(124,92,250,0.15)' })
              .margin({ bottom: 8 })
              .onClick(() => {
                this.inputText = item;
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
        TextInput({ placeholder: '问我关于校园的任何问题...', text: this.inputText })
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

        Button('发送')
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
