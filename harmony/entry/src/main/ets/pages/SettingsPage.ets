/**
 * SettingsPage — 设置页
 */
import { Theme, SafeTop } from './Theme';
import { promptAction } from '@kit.ArkUI';

@Component
struct SettingItem {
  @Prop label: string = '';
  @Prop value: string = '';
  onItemClick: () => void = () => {};

  build() {
    Row() {
      Text(this.label)
        .fontSize(15)
        .fontColor(Theme.text)
        .layoutWeight(1)

      Text(this.value)
        .fontSize(13)
        .fontColor(Theme.textMuted)

      Text('▶')
        .fontSize(12)
        .fontColor(Theme.textMuted)
        .margin({ left: 8 })
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onItemClick();
    })
  }
}

@Component
export struct SettingsPage {
  @State showLangDialog: boolean = false;
  @State currentLang: string = '中文';

  build() {
    Column() {
      SafeTop()

      Text('设置')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
        .width('100%')
        .padding({ left: 20, bottom: 12 })
        .margin({ top: 12 })

      Divider().color(Theme.divider)

      List() {
        ListItem() {
          SettingItem({
            label: '语言',
            value: `当前：${this.currentLang}`,
            onItemClick: () => {
              this.showLangDialog = true;
            }
          })
        }
        ListItem() {
          SettingItem({
            label: 'AI 记忆',
            value: '已保存 2 条偏好',
            onItemClick: () => {
              promptAction.showToast({ message: 'AI 记忆 — 功能开发中', duration: 2000 });
            }
          })
        }
        ListItem() {
          SettingItem({
            label: '操作记录',
            value: '查看最近操作',
            onItemClick: () => {
              promptAction.showToast({ message: '操作记录 — 功能开发中', duration: 2000 });
            }
          })
        }
        ListItem() {
          SettingItem({
            label: '智能监控',
            value: '管理提醒监控项',
            onItemClick: () => {
              promptAction.showToast({ message: '智能监控 — 功能开发中', duration: 2000 });
            }
          })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .divider({ strokeWidth: 0.5, color: Theme.divider })

      Column() {
        Text('CampusOS v2.1.1')
          .fontSize(12)
          .fontColor(Theme.textMuted)
        Text('HarmonyOS 迁移中 — ArkTS MVP')
          .fontSize(11)
          .fontColor(Theme.textMuted)
          .margin({ top: 4 })
      }
      .width('100%')
      .padding({ top: 16, bottom: 32 })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
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
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
        .margin({ bottom: 16 })

      Button('中文')
        .type(ButtonType.Normal)
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(this.currentLang === '中文' ? Theme.textInvert : Theme.text)
        .backgroundColor(this.currentLang === '中文' ? Theme.primary : Theme.surfaceAlt)
        .borderRadius(10)
        .onClick(() => {
          this.currentLang = '中文';
          this.showLangDialog = false;
        })

      Button('English')
        .type(ButtonType.Normal)
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(this.currentLang === 'English' ? Theme.textInvert : Theme.text)
        .backgroundColor(this.currentLang === 'English' ? Theme.primary : Theme.surfaceAlt)
        .borderRadius(10)
        .margin({ top: 12 })
        .onClick(() => {
          this.currentLang = 'English';
          this.showLangDialog = false;
        })
    }
    .width('100%')
    .padding(20)
    .alignItems(HorizontalAlign.Start)
  }
}
