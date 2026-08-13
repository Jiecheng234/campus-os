/**
 * CampusOS 共享 UI 组件库 — 对齐 docs/CAMPUS_OS_DESIGN_SYSTEM_V1.md
 * 与原项目 src/features/common/components/Ui.tsx 视觉一致。
 */
import { Theme, Space, Radius, FontSize } from '../pages/Theme';

@Builder
function emptyContent() {}

// ────────────────────────────────
// ScreenHeader：Tab 根页头部（eyebrow + 标题 + 副标题 + 右侧插槽）
// ────────────────────────────────
@Component
export struct ScreenHeader {
  eyebrow: string = '';
  title: string = '';
  subtitle: string = '';
  @BuilderParam right: () => void = emptyContent;

  build() {
    Row() {
      Column({ space: 3 }) {
        if (this.eyebrow.length > 0) {
          Text(this.eyebrow.toUpperCase())
            .fontSize(FontSize.micro)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.textMuted)
            .letterSpacing(1.4)
        }
        Text(this.title)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.text)
          .letterSpacing(-0.3)
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(FontSize.caption)
            .fontColor(Theme.textMuted)
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      this.right()
    }
    .width('100%')
    .alignItems(VerticalAlign.Bottom)
  }
}

// ────────────────────────────────
// SectionHeader：数据组标题（12px 大写小标题 + 可选右侧操作）
// ────────────────────────────────
@Component
export struct SectionHeader {
  title: string = '';
  actionText: string = '';
  onAction: () => void = () => {};

  build() {
    Row() {
      Text(this.title.toUpperCase())
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.textSecondary)
        .letterSpacing(0.2)
      Blank()
      if (this.actionText.length > 0) {
        Text(this.actionText)
          .fontSize(FontSize.label)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.primary)
          .onClick(() => { this.onAction(); })
      }
    }
    .width('100%')
    .margin({ top: Space.lg, bottom: Space.sm })
  }
}

// ────────────────────────────────
// Badge：pill 状态标签
// ────────────────────────────────
export enum BadgeTone {
  Default = 'default',
  Success = 'success',
  Warning = 'warning',
  Error = 'error',
}

@Component
export struct StatusBadge {
  text: string = '';
  tone: BadgeTone = BadgeTone.Default;

  private bgColor(): string {
    if (this.tone === BadgeTone.Success) { return Theme.successMuted; }
    if (this.tone === BadgeTone.Warning) { return Theme.warningMuted; }
    if (this.tone === BadgeTone.Error) { return Theme.errorMuted; }
    return Theme.primaryMuted;
  }

  private fgColor(): string {
    if (this.tone === BadgeTone.Success) { return Theme.success; }
    if (this.tone === BadgeTone.Warning) { return Theme.warning; }
    if (this.tone === BadgeTone.Error) { return Theme.error; }
    return Theme.primary;
  }

  build() {
    Text(this.text)
      .fontSize(FontSize.micro)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.fgColor())
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .borderRadius(Radius.pill)
      .backgroundColor(this.bgColor())
  }
}

// ────────────────────────────────
// ListCard：可导航记录卡（可选左侧 2px accent 条）
// ────────────────────────────────
export enum CardAccent {
  None = 'none',
  Primary = 'primary',
  Success = 'success',
  Warning = 'warning',
  Error = 'error',
}

@Component
export struct ListCard {
  accent: CardAccent = CardAccent.None;
  onCardClick: () => void = () => {};
  @BuilderParam content: () => void = emptyContent;

  private accentColor(): string {
    if (this.accent === CardAccent.Primary) { return Theme.primary; }
    if (this.accent === CardAccent.Success) { return Theme.success; }
    if (this.accent === CardAccent.Warning) { return Theme.warning; }
    if (this.accent === CardAccent.Error) { return Theme.error; }
    return 'transparent';
  }

  build() {
    Row() {
      if (this.accent !== CardAccent.None) {
        Column()
          .width(2)
          .height('100%')
          .backgroundColor(this.accentColor())
      }
      Column() {
        this.content()
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .padding({ left: this.accent !== CardAccent.None ? 14 : Space.md, right: Space.md, top: Space.md, bottom: Space.md })
    }
    .width('100%')
    .borderRadius(Radius.lg)
    .backgroundColor(Theme.surface)
    .border({ width: 1, color: Theme.borderSubtle })
    .margin({ bottom: Space.sm })
    .onClick(() => { this.onCardClick(); })
  }
}

// ────────────────────────────────
// InfoRow：标签—值详情行（label 宽 80 + value）
// ────────────────────────────────
@Component
export struct InfoRow {
  label: string = '';
  value: string = '';

  build() {
    Row({ space: Space.md }) {
      Text(this.label)
        .fontSize(FontSize.caption)
        .fontColor(Theme.textMuted)
        .width(80)
      Text(this.value.length > 0 ? this.value : '—')
        .fontSize(FontSize.body)
        .fontColor(Theme.text)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
  }
}

// ────────────────────────────────
// EmptyHint：空状态提示
// ────────────────────────────────
@Component
export struct EmptyHint {
  title: string = '';
  message: string = '';

  build() {
    Column({ space: Space.xs }) {
      Text(this.title)
        .fontSize(FontSize.body)
        .fontColor(Theme.textMuted)
        .textAlign(TextAlign.Center)
      if (this.message.length > 0) {
        Text(this.message)
          .fontSize(FontSize.caption)
          .fontColor(Theme.textMuted)
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .padding({ left: Space.md, right: Space.md, top: Space.xxl, bottom: Space.xxl })
  }
}

// ────────────────────────────────
// StateBlock：错误/警告/阻塞状态（左侧 4px 强调条）
// ────────────────────────────────
export enum StateTone {
  Neutral = 'neutral',
  Info = 'info',
  Success = 'success',
  Warning = 'warning',
  Error = 'error',
}

@Component
export struct StateBlock {
  tone: StateTone = StateTone.Neutral;
  title: string = '';
  message: string = '';
  actionText: string = '';
  onAction: () => void = () => {};

  private accentColor(): string {
    if (this.tone === StateTone.Info) { return Theme.primary; }
    if (this.tone === StateTone.Success) { return Theme.success; }
    if (this.tone === StateTone.Warning) { return Theme.warning; }
    if (this.tone === StateTone.Error) { return Theme.error; }
    return Theme.textMuted;
  }

  private bgColor(): string {
    if (this.tone === StateTone.Info) { return Theme.primaryMuted; }
    if (this.tone === StateTone.Success) { return Theme.successMuted; }
    if (this.tone === StateTone.Warning) { return Theme.warningMuted; }
    if (this.tone === StateTone.Error) { return Theme.errorMuted; }
    return Theme.surface;
  }

  build() {
    Row() {
      Column()
        .width(4)
        .height('100%')
        .backgroundColor(this.accentColor())
      Column({ space: Space.xs }) {
        if (this.title.length > 0) {
          Text(this.title)
            .fontSize(FontSize.label)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.accentColor())
        }
        if (this.message.length > 0) {
          Text(this.message)
            .fontSize(FontSize.caption)
            .fontColor(Theme.textSecondary)
        }
        if (this.actionText.length > 0) {
          Text(this.actionText)
            .fontSize(FontSize.label)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.accentColor())
            .margin({ top: Space.xs })
            .onClick(() => { this.onAction(); })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .padding(Space.md)
    }
    .width('100%')
    .borderRadius(Radius.lg)
    .backgroundColor(this.bgColor())
    .border({ width: 1, color: Theme.borderSubtle })
  }
}

// ────────────────────────────────
// MetricPill：并列统计块
// ────────────────────────────────
@Component
export struct MetricPill {
  value: string = '';
  label: string = '';
  tone: BadgeTone = BadgeTone.Default;

  private valueColor(): string {
    if (this.tone === BadgeTone.Success) { return Theme.success; }
    if (this.tone === BadgeTone.Warning) { return Theme.warning; }
    if (this.tone === BadgeTone.Error) { return Theme.error; }
    return Theme.primary;
  }

  build() {
    Column({ space: 2 }) {
      Text(this.value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.valueColor())
      Text(this.label)
        .fontSize(FontSize.micro)
        .fontColor(Theme.textMuted)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .height(66)
    .borderRadius(Radius.md)
    .backgroundColor(Theme.surfaceAlt)
    .padding(Space.sm)
  }
}
