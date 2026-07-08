/**
 * CampusOS Theme — 色板常量 + SafeTop 组件
 */
export class Theme {
  static readonly primary: string = '#7C5CFA';
  static readonly primaryDark: string = '#5B3EE0';
  static readonly background: string = '#FAFAFB';
  static readonly surface: string = '#FFFFFF';
  static readonly surfaceAlt: string = '#F2F2F4';
  static readonly text: string = '#0A0A0B';
  static readonly textSecondary: string = '#5C5C61';
  static readonly textMuted: string = '#8E8E93';
  static readonly textInvert: string = '#FFFFFF';
  static readonly border: string = '#E2E2E5';
  static readonly borderSubtle: string = 'rgba(10,10,11,0.08)';
  static readonly divider: string = 'rgba(10,10,11,0.06)';
  static readonly success: string = '#16A34A';
  static readonly warning: string = '#D97706';
  static readonly error: string = '#DC2626';
  static readonly cardRadius: number = 16;
}

/**
 * SafeTop — 顶部安全区占位组件，高度 36px。
 * 不使用 getWindowAvoidArea(TYPE_SYSTEM)：有挖孔摄像的设备会返回含挖孔区的完整避开高度（可达 130px+），
 * 导致标题被过度下推。36px 覆盖绝大部分设备的状态栏高度，且 ArkUI 全屏模式会自动将内容绘制到状态栏下方。
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
