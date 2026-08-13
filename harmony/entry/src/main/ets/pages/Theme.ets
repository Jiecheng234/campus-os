/**
 * CampusOS Theme — 设计系统 token（对齐 docs/CAMPUS_OS_DESIGN_SYSTEM_V1.md）
 * 色板 / 间距 / 圆角 / 字号，数值与原项目 src/app/theme 一致。
 */
export class Theme {
  // ── 主色 ──
  static readonly primary: string = '#7C5CFA';
  static readonly primaryDark: string = '#5B3EE0';
  static readonly primaryMuted: string = 'rgba(124,92,250,0.10)';
  static readonly accentLight: string = '#A78BFA';
  static readonly accentMuted: string = 'rgba(124,92,250,0.08)';
  static readonly gradientStart: string = '#F4F2FF';
  static readonly gradientEnd: string = '#E8E3FF';

  // ── 背景层级 ──
  static readonly background: string = '#FAFAFB';
  static readonly surface: string = '#FFFFFF';
  static readonly surfaceAlt: string = '#F2F2F4';
  static readonly surfaceElevated: string = '#FFFFFF';

  // ── 文本 ──
  static readonly text: string = '#0A0A0B';
  static readonly textSecondary: string = '#5C5C61';
  static readonly textMuted: string = '#8E8E93';
  static readonly textInvert: string = '#FFFFFF';

  // ── 结构 ──
  static readonly border: string = '#E2E2E5';
  static readonly borderSubtle: string = 'rgba(10,10,11,0.08)';
  static readonly divider: string = 'rgba(10,10,11,0.06)';
  static readonly overlay: string = 'rgba(15,23,42,0.45)';

  // ── 语义色 ──
  static readonly success: string = '#16A34A';
  static readonly successMuted: string = 'rgba(22,163,74,0.12)';
  static readonly warning: string = '#D97706';
  static readonly warningMuted: string = 'rgba(217,119,6,0.12)';
  static readonly error: string = '#DC2626';
  static readonly errorMuted: string = 'rgba(220,38,38,0.10)';

  // ── 兼容旧字段 ──
  static readonly cardRadius: number = 16;
}

/** 间距 token（vp），4 的倍数网格 */
export class Space {
  static readonly xs: number = 4;
  static readonly sm: number = 8;
  static readonly md: number = 16;
  static readonly lg: number = 24;
  static readonly xl: number = 32;
  static readonly xxl: number = 48;
}

/** 圆角 token（vp），大圆角风格 */
export class Radius {
  static readonly sm: number = 10;
  static readonly md: number = 14;
  static readonly lg: number = 20;
  static readonly xl: number = 28;
  static readonly pill: number = 999;
}

/** 字号 token（fp） */
export class FontSize {
  static readonly display: number = 34;
  static readonly h1: number = 28;
  static readonly h2: number = 20;
  static readonly h3: number = 16;
  static readonly label: number = 14;
  static readonly body: number = 15;
  static readonly caption: number = 13;
  static readonly micro: number = 11;
}

/**
 * SafeTop — 顶部安全区占位组件。
 * 36px 覆盖绝大部分设备状态栏高度；ArkUI 全屏模式自动将内容绘制到状态栏下方。
 */
@Component
export struct SafeTop {
  @StorageLink('safeAreaTop') safeAreaTop: number = 36;

  build() {
    Row()
      .width('100%')
      .height(this.safeAreaTop)
  }
}
