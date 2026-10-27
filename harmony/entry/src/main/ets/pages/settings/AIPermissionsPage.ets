/**
 * ============================================================================
 * AIPermissionsPage — AI 工具权限页（ai-governance 特性，US2）
 * ============================================================================
 *
 * - 按权限键分组展示 AgentTools 注册表（28 个权限域：22 只读 + 6 可写）；
 *   组标题走 i18n（settings.aiPermDomain.<permission>），缺键回退原始权限键。
 * - 每组：域标题 + 最高风险标签 + 需确认标记 + 工具计数 + 启停开关。
 * - 开关经 AIPermissionStore 持久化：乐观更新，失败回滚开关并 toast。
 * - 「恢复全部权限」：逐项解除禁用后整页重建；失败 toast 可重试。
 * - 子页形态：由 SettingsPage 的 subScreen 驱动（无路由栈），
 *   返回手势经 BackDispatcher（BackOwner.SETTINGS）关闭。
 */
import { AgentToolDef } from '../../domain/AIAgentTypes';
import { ToolRisk } from '../../domain/ActionTypes';
import { AgentTools } from '../../services/ai/AgentTools';
import { AIPermissionStore } from '../../storage/AIPermissionStore';
import { I18n } from '../../utils/I18n';
import { SafeTop, Theme, Space, Radius, FontSize } from '../Theme';
import { BadgeTone, DetailHeader, SectionHeader, StatusBadge } from '../../components/Ui';

/** 权限分组（渲染模型；不可变替换以驱动 V1 状态刷新） */
class PermGroup {
  permission: string = '';
  toolCount: number = 0;
  /** 组内工具展示名清单（FR-008：类别必须展示包含的工具，不能只显示数量） */
  toolTitles: string[] = [];
  maxRisk: string = ToolRisk.NONE;
  requiresConfirmation: boolean = false;
  disabled: boolean = false;

  copy(): PermGroup {
    const next: PermGroup = new PermGroup();
    next.permission = this.permission;
    next.toolCount = this.toolCount;
    next.toolTitles = this.toolTitles.slice();
    next.maxRisk = this.maxRisk;
    next.requiresConfirmation = this.requiresConfirmation;
    next.disabled = this.disabled;
    return next;
  }
}

/** 风险等级序（取组内最高） */
function riskRank(risk: string): number {
  if (risk === ToolRisk.NONE) {
    return 0;
  }
  if (risk === ToolRisk.LOW) {
    return 1;
  }
  if (risk === ToolRisk.MEDIUM) {
    return 2;
  }
  return 3;
}

@Component
export struct AIPermissionsPage {
  @StorageLink('locale') locale: string = 'zh';
  @State groups: PermGroup[] = [];
  /** 仓库读取失败（不谎报"全部启用"；开关写入会被仓库拒绝） */
  @State loadFailed: boolean = false;
  onBack: () => void = () => {};

  aboutToAppear(): void {
    // 已加载过：同步构建；再幂等确认 / 失败重试（如冷启动竞态）
    if (AIPermissionStore.isLoaded()) {
      this.buildGroups();
    }
    AIPermissionStore.ensureLoaded().then((): void => {
      this.loadFailed = false;
      this.buildGroups();
    }).catch((): void => {
      // 读取失败：给出可读提示，开关操作会被仓库上抛拒绝
      this.loadFailed = true;
      this.buildGroups();
    });
  }

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  private trp(key: string, args: Record<string, string>): string {
    return I18n.tp(key, args, this.locale);
  }

  /** 域标题：i18n 命中走翻译，缺键回退原始权限键 */
  private domainTitle(group: PermGroup): string {
    const key: string = 'settings.aiPermDomain.' + group.permission;
    return I18n.has(key) ? this.tr(key) : group.permission;
  }

  /** 工具展示名清单（顿号连接；FR-008 行内展示用） */
  private toolTitlesText(group: PermGroup): string {
    const parts: string[] = [];
    for (let i: number = 0; i < group.toolTitles.length; i++) {
      parts.push(group.toolTitles[i]);
    }
    return parts.join('、');
  }

  private riskLabel(risk: string): string {
    if (risk === ToolRisk.NONE) {
      return this.tr('ai.riskNone');
    }
    if (risk === ToolRisk.LOW) {
      return this.tr('ai.riskLow');
    }
    if (risk === ToolRisk.MEDIUM) {
      return this.tr('ai.riskMedium');
    }
    if (risk === ToolRisk.HIGH) {
      return this.tr('ai.riskHigh');
    }
    return risk.length > 0 ? risk : '—';
  }

  private riskTone(risk: string): BadgeTone {
    if (risk === ToolRisk.MEDIUM) {
      return BadgeTone.Warning;
    }
    if (risk === ToolRisk.HIGH) {
      return BadgeTone.Error;
    }
    if (risk === ToolRisk.LOW) {
      return BadgeTone.Success;
    }
    return BadgeTone.Default;
  }

  /** 从注册表构建权限分组（permissionKeys 预建分组顺序，含当前禁用状态与工具清单） */
  private buildGroups(): void {
    const registry: AgentToolDef[] = AgentTools.all();
    // 用 permissionKeys 预建分组顺序（消除注册表遍历顺序依赖）
    const order: string[] = AgentTools.permissionKeys();
    const groups: PermGroup[] = [];
    for (let i: number = 0; i < order.length; i++) {
      const seeded: PermGroup = new PermGroup();
      seeded.permission = order[i];
      groups.push(seeded);
    }
    for (let i: number = 0; i < registry.length; i++) {
      const tool: AgentToolDef = registry[i];
      if (tool.permission.length === 0) {
        continue;
      }
      let group: PermGroup | undefined = undefined;
      for (let j: number = 0; j < groups.length; j++) {
        if (groups[j].permission === tool.permission) {
          group = groups[j];
          break;
        }
      }
      if (group === undefined) {
        group = new PermGroup();
        group.permission = tool.permission;
        groups.push(group);
      }
      group.toolCount += 1;
      group.toolTitles.push(tool.title.length > 0 ? tool.title : tool.name);
      if (riskRank(tool.risk) > riskRank(group.maxRisk)) {
        group.maxRisk = tool.risk;
      }
      if (tool.requiresConfirmation) {
        group.requiresConfirmation = true;
      }
    }
    for (let j: number = 0; j < groups.length; j++) {
      groups[j].disabled = AIPermissionStore.isDisabled(groups[j].permission);
    }
    this.groups = groups;
  }

  /** 不可变替换指定权限分组的禁用状态（按权限键实时查找，避免陈旧索引/闭包） */
  private applyDisabledByPermission(permission: string, disabled: boolean): boolean {
    const updated: PermGroup[] = this.groups.slice();
    let applied: boolean = false;
    for (let i: number = 0; i < updated.length; i++) {
      if (updated[i].permission === permission) {
        const group: PermGroup = updated[i].copy();
        group.disabled = disabled;
        updated[i] = group;
        applied = true;
        break;
      }
    }
    if (applied) {
      this.groups = updated;
    }
    return applied;
  }

  private enabledCount(): number {
    let count: number = 0;
    for (let i: number = 0; i < this.groups.length; i++) {
      if (!this.groups[i].disabled) {
        count += 1;
      }
    }
    return count;
  }

  private readGroups(): PermGroup[] {
    const out: PermGroup[] = [];
    for (let i: number = 0; i < this.groups.length; i++) {
      if (!this.groups[i].requiresConfirmation) {
        out.push(this.groups[i]);
      }
    }
    return out;
  }

  private writeGroups(): PermGroup[] {
    const out: PermGroup[] = [];
    for (let i: number = 0; i < this.groups.length; i++) {
      if (this.groups[i].requiresConfirmation) {
        out.push(this.groups[i]);
      }
    }
    return out;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (e) {
      /* ignore */
    }
  }

  // ============================================================
  // 开关切换（乐观更新 + 失败回滚）与恢复全部
  // ============================================================

  private onToggle(group: PermGroup, nextEnabled: boolean): void {
    const targetDisabled: boolean = !nextEnabled;
    // 不信任闭包里的 group：按权限键从当前状态实时查找，
    // 避免 ForEach 复用导致的陈旧闭包提前 return / 误判状态
    let current: PermGroup | undefined = undefined;
    for (let i: number = 0; i < this.groups.length; i++) {
      if (this.groups[i].permission === group.permission) {
        current = this.groups[i];
        break;
      }
    }
    if (current === undefined || current.disabled === targetDisabled) {
      return;
    }
    // 乐观更新：先改内存态，持久化失败再回滚（回滚同样按权限键实时查找）
    this.applyDisabledByPermission(group.permission, targetDisabled);
    AIPermissionStore.setDisabled(group.permission, targetDisabled).catch((): void => {
      this.applyDisabledByPermission(group.permission, !targetDisabled);
      this.showToast(this.tr('settings.aiPermToggleFailed'));
    });
  }

  private restoreAll(): void {
    const job = async (): Promise<void> => {
      for (let i: number = 0; i < this.groups.length; i++) {
        if (this.groups[i].disabled) {
          await AIPermissionStore.setDisabled(this.groups[i].permission, false);
        }
      }
    };
    job().then((): void => {
      this.buildGroups();
      this.showToast(this.tr('settings.aiPermRestored'));
    }).catch((): void => {
      this.buildGroups();
      this.showToast(this.tr('settings.aiPermRestoreFailed'));
    });
  }

  build() {
    Column() {
      SafeTop()
      DetailHeader({ title: this.tr('settings.aiPermissions'), onBack: () => { this.onBack(); } })

      Scroll() {
        Column() {
          // ── 摘要 + 恢复全部 ──
          Row() {
            Column({ space: 2 }) {
              Text(this.tr('settings.aiPermDesc'))
                .fontSize(FontSize.caption)
                .fontColor(Theme.textSecondary)
              Text(this.trp('settings.aiPermSummary', {
                'enabled': `${this.enabledCount()}`,
                'total': `${this.groups.length}`
              }))
                .fontSize(FontSize.micro)
                .fontColor(Theme.textMuted)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            if (this.enabledCount() < this.groups.length) {
              Text(this.tr('settings.aiPermRestoreAll'))
                .fontSize(FontSize.caption)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.primary)
                .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
                .onClick(() => { this.restoreAll(); })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({ left: Space.lg, right: Space.lg, top: Space.sm, bottom: Space.sm })

          if (this.loadFailed) {
            // 读取失败：给出可读提示，不谎报"全部启用"（开关写入会被仓库拒绝）
            Text(this.tr('settings.aiPermLoadFailed'))
              .fontSize(FontSize.micro)
              .fontColor(Theme.error)
              .padding({ left: Space.lg, right: Space.lg, bottom: Space.sm })
          }

          // ── 只读工具 ──
          SectionHeader({ title: this.tr('settings.aiPermReadonlyGroup') })
            .padding({ left: Space.lg, right: Space.lg })
          Column() {
            ForEach(this.readGroups(), (group: PermGroup, index: number) => {
              if (index > 0) {
                Divider().color(Theme.divider).width('100%').margin({ left: Space.md })
              }
              this.GroupRow(group)
            // key 纳入禁用状态：ArkUI V1 键值不变不重建组件，开关不跟随时状态会脱节
            }, (group: PermGroup) => group.permission + (group.disabled ? '_off' : '_on'))
          }
          .width('100%')
          .constraintSize({ maxWidth: '100%' })
          .borderRadius(Radius.lg)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: Space.lg, right: Space.lg })

          // ── 可写工具 ──
          SectionHeader({ title: this.tr('settings.aiPermWriteGroup') })
            .padding({ left: Space.lg, right: Space.lg })
          Column() {
            ForEach(this.writeGroups(), (group: PermGroup, index: number) => {
              if (index > 0) {
                Divider().color(Theme.divider).width('100%').margin({ left: Space.md })
              }
              this.GroupRow(group)
            // key 纳入禁用状态：ArkUI V1 键值不变不重建组件，开关不跟随时状态会脱节
            }, (group: PermGroup) => group.permission + (group.disabled ? '_off' : '_on'))
          }
          .width('100%')
          .constraintSize({ maxWidth: '100%' })
          .borderRadius(Radius.lg)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: Space.lg, right: Space.lg, bottom: Space.xxl })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }

  /** 权限分组行：域标题 + 风险/确认标记 + 计数 + 开关 */
  @Builder
  GroupRow(group: PermGroup) {
    Row() {
      Column({ space: 4 }) {
        Row({ space: Space.sm }) {
          Text(this.domainTitle(group))
            .fontSize(FontSize.body)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          StatusBadge({ text: this.riskLabel(group.maxRisk), tone: this.riskTone(group.maxRisk) })
          if (group.requiresConfirmation) {
            StatusBadge({ text: this.tr('ai.confirmRequired'), tone: BadgeTone.Warning })
          }
        }
        .width('100%')

        Row({ space: Space.xs }) {
          Text(this.trp('settings.aiPermToolCount', { 'n': `${group.toolCount}` }))
            .fontSize(FontSize.micro)
            .fontColor(Theme.textMuted)
          Text(group.permission)
            .fontSize(FontSize.micro)
            .fontColor(Theme.textMuted)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')

        // FR-008：每个类别展示包含的工具（展示名清单），过长省略
        Text(this.trp('settings.aiPermTools', { 'tools': this.toolTitlesText(group) }))
          .fontSize(FontSize.micro)
          .fontColor(Theme.textMuted)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: !group.disabled })
        .onChange((next: boolean) => {
          this.onToggle(group, next);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: Space.md, right: Space.md, top: Space.md, bottom: Space.md })
  }
}
