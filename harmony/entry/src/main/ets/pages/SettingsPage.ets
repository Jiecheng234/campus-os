/**
 * SettingsPage — 设置页（对齐原项目 SettingsScreen：组标题 + 白卡行组）
 */
import { Theme, SafeTop, Space, Radius, FontSize } from './Theme';
import { ScreenHeader, SectionHeader } from '../components/Ui';
import { promptAction } from '@kit.ArkUI';
import { StateManager } from '../state/StateManager';
import { AuthManager } from '../state/AuthManager';
import { SessionManager } from '../services/auth/SessionManager';

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

@Component
export struct SettingsPage {
  @State showLangDialog: boolean = false;
  @State currentLang: string = '中文';
  @State demoMode: boolean = false;
  @State trustDevice: boolean = true;

  aboutToAppear(): void {
    this.demoMode = StateManager.isDemoMode();
  }

  build() {
    Scroll() {
      Column() {
        SafeTop()

        Column() {
          ScreenHeader({
            eyebrow: 'SETTINGS',
            title: '设置',
            subtitle: StateManager.isDemoMode() ? '演示模式' : '已登录'
          })
        }
        .width('100%')
        .padding({ left: Space.lg, right: Space.lg, top: Space.lg, bottom: Space.sm })

        // ── 偏好设置组 ──
        SectionHeader({ title: '偏好设置' })
          .padding({ left: Space.lg, right: Space.lg })

        Column() {
          SettingSwitch({
            label: '演示模式',
            isOn: $demoMode,
            onToggle: (v: boolean) => { StateManager.settings.demoMode = v; }
          })
          Divider().color(Theme.divider).margin({ left: Space.md })
          SettingSwitch({ label: '信任此设备', isOn: $trustDevice })
          Divider().color(Theme.divider).margin({ left: Space.md })
          SettingRow({
            label: '语言',
            value: this.currentLang,
            onItemClick: () => { this.showLangDialog = true; }
          })
        }
        .width('100%')
        .borderRadius(Radius.lg)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.borderSubtle })
        .margin({ left: Space.lg, right: Space.lg })

        // ── 功能组 ──
        SectionHeader({ title: '功能' })
          .padding({ left: Space.lg, right: Space.lg })

        Column() {
          SettingRow({
            label: 'AI 记忆',
            value: '已保存偏好',
            onItemClick: () => { promptAction.showToast({ message: 'AI 记忆 — 功能开发中', duration: 2000 }); }
          })
          Divider().color(Theme.divider).margin({ left: Space.md })
          SettingRow({
            label: '操作记录',
            value: '查看最近操作',
            onItemClick: () => { promptAction.showToast({ message: '操作记录 — 功能开发中', duration: 2000 }); }
          })
          Divider().color(Theme.divider).margin({ left: Space.md })
          SettingRow({
            label: '智能监控',
            value: '管理提醒监控项',
            onItemClick: () => { promptAction.showToast({ message: '智能监控 — 功能开发中', duration: 2000 }); }
          })
        }
        .width('100%')
        .borderRadius(Radius.lg)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.borderSubtle })
        .margin({ left: Space.lg, right: Space.lg })

        // ── 退出登录（ghost 按钮）──
        Text('退出登录')
          .fontSize(FontSize.label)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.error)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(Space.md)
          .borderRadius(Radius.lg)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.border })
          .margin({ left: Space.lg, right: Space.lg, top: Space.xl })
          .onClick(() => {
            SessionManager.logout();
            promptAction.showToast({ message: '已退出登录', duration: 2000 });
          })

        // ── 版本信息 ──
        Column({ space: Space.xs }) {
          Text('CampusOS v2.1.1')
            .fontSize(FontSize.caption)
            .fontColor(Theme.textMuted)
          Text('HarmonyOS ArkTS')
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
      Text('选择语言')
        .fontSize(FontSize.h3)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
        .margin({ bottom: Space.md })

      Button('中文')
        .type(ButtonType.Normal)
        .width('100%')
        .height(44)
        .fontSize(FontSize.body)
        .fontColor(this.currentLang === '中文' ? Theme.textInvert : Theme.text)
        .backgroundColor(this.currentLang === '中文' ? Theme.primary : Theme.surfaceAlt)
        .borderRadius(Radius.sm)
        .onClick(() => {
          this.currentLang = '中文';
          this.showLangDialog = false;
        })

      Button('English')
        .type(ButtonType.Normal)
        .width('100%')
        .height(44)
        .fontSize(FontSize.body)
        .fontColor(this.currentLang === 'English' ? Theme.textInvert : Theme.text)
        .backgroundColor(this.currentLang === 'English' ? Theme.primary : Theme.surfaceAlt)
        .borderRadius(Radius.sm)
        .margin({ top: Space.md })
        .onClick(() => {
          this.currentLang = 'English';
          this.showLangDialog = false;
        })
    }
    .width('100%')
    .padding(Space.lg)
    .alignItems(HorizontalAlign.Start)
  }
}
