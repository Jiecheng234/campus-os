/**
 * ============================================================================
 * LaundryPage — 宿舍洗衣机只读查询（楼宇分组 → 楼层/机台）
 * ============================================================================
 *
 * 层级（页内状态切换，不走路由）：
 *   GROUP（按平台/区域分组的楼宇列表）
 *     → FLOOR（楼层 → 机台卡片：类型/位置 + 空闲/使用中/异常；洁力含剩余时间）
 *
 * 数据经 LaundryService（第三方公开接口，无鉴权、不依赖登录态，FR-009）；
 * 演示模式（未登录或演示开关开启）内置示例、零网络请求（FR-010）；
 * 单平台失败仍展示另一平台（服务层"部分成功"合并，FR-006）；
 * 各层可手动刷新（右上角 ↻），加载中显示加载态（FR-008）。
 * ============================================================================
 */
import { Theme, Space, Radius, FontSize } from '../Theme';
import { EmptyHint, MetricPill, StateBlock, StateTone, BadgeTone } from '../../components/Ui';
import { SessionManager } from '../../services/auth/SessionManager';
import {
  LaundryService,
  LaundryBuilding,
  LaundryBuildingGroup,
  LaundryFloor,
  LaundryMachine,
  LaundryMachineStatus,
  LaundryPlatform,
} from '../../services/campus/LaundryService';
import { AuthManager } from '../../state/AuthManager';
import { StateManager } from '../../state/StateManager';
import { BackDispatcher, BackOwner, BackHandler } from '../../state/BackDispatcher';
import { I18n } from '../../utils/I18n';

/** 页内层级（不走路由） */
const LEVEL_GROUP: number = 0;
const LEVEL_FLOOR: number = 1;

// ============================================================
// 演示模式示例数据（零网络请求）
// ============================================================

function demoBuilding(id: string, name: string, platform: LaundryPlatform): LaundryBuilding {
  const building: LaundryBuilding = new LaundryBuilding();
  building.id = id;
  building.name = name;
  building.platform = platform;
  return building;
}

function getDemoGroups(): LaundryBuildingGroup[] {
  const groups: LaundryBuildingGroup[] = [];
  const specs: string[][] = [
    ['紫荆公寓', '紫荆1号楼', '紫荆2号楼', '紫荆3号楼', '紫荆4号楼', '紫荆5号楼', '紫荆6号楼'],
    ['南区宿舍', '南区1号楼', '南区2号楼'],
    ['双清公寓', '双清公寓北楼', '双清公寓南楼'],
    ['海乐生活', '清华园海乐洗衣房'],
  ];
  for (let g: number = 0; g < specs.length; g++) {
    const group: LaundryBuildingGroup = new LaundryBuildingGroup();
    group.name = specs[g][0];
    for (let i: number = 1; i < specs[g].length; i++) {
      const platform: LaundryPlatform = group.name === '海乐生活' ? 'haile' : 'jieli';
      group.buildings.push(demoBuilding('demo-' + String(g) + '-' + String(i), specs[g][i], platform));
    }
    groups.push(group);
  }
  return groups;
}

function demoMachine(type: string, name: string, floor: string, status: LaundryMachineStatus,
  etaMinutes: number, updatedAt: string, location: string): LaundryMachine {
  const machine: LaundryMachine = new LaundryMachine();
  machine.type = type;
  machine.name = name;
  machine.floor = floor;
  machine.status = status;
  machine.etaMinutes = etaMinutes;
  machine.updatedAt = updatedAt;
  machine.location = location;
  return machine;
}

function getDemoFloors(platform: LaundryPlatform): LaundryFloor[] {
  const floors: LaundryFloor[] = [];
  if (platform === 'haile') {
    const floor: LaundryFloor = new LaundryFloor();
    floor.name = '海乐生活';
    floor.machines = [
      demoMachine('洗衣机', '1号机', floor.name, 'idle', -1, '10:16:20', ''),
      demoMachine('洗衣机', '2号机', floor.name, 'working', -1, '10:16:20', ''),
      demoMachine('洗鞋机', '1号机', floor.name, 'idle', -1, '10:16:20', ''),
      demoMachine('烘干机', '1号机', floor.name, 'error', -1, '10:16:20', ''),
      demoMachine('烘干机', '2号机', floor.name, 'working', -1, '10:16:20', ''),
    ];
    floors.push(floor);
    return floors;
  }
  const first: LaundryFloor = new LaundryFloor();
  first.name = '一层';
  first.machines = [
    demoMachine('洗衣机', 'A01', first.name, 'idle', -1, '2026/10/16 10:12', '一层东水房'),
    demoMachine('洗衣机', 'A02', first.name, 'working', 23, '2026/10/16 10:12', '一层东水房'),
    demoMachine('洗鞋机', 'B01', first.name, 'idle', -1, '2026/10/16 10:12', '一层西水房'),
    demoMachine('烘干机', 'B02', first.name, 'error', -1, '2026/10/16 10:12', '一层西水房'),
  ];
  floors.push(first);
  const second: LaundryFloor = new LaundryFloor();
  second.name = '二层';
  second.machines = [
    demoMachine('洗衣机', 'C01', second.name, 'working', 12, '2026/10/16 10:12', '二层东水房'),
    demoMachine('洗衣机', 'C02', second.name, 'idle', -1, '2026/10/16 10:12', '二层东水房'),
    demoMachine('烘干机', 'C03', second.name, 'idle', -1, '2026/10/16 10:12', '二层西水房'),
  ];
  floors.push(second);
  return floors;
}

// ============================================================
// 页面组件
// ============================================================

@Component
export struct LaundryPage {
  onBack: () => void = () => {};

  /** 语言订阅：新增可见文案走 i18n（语言切换即时重渲染） */
  @StorageLink('locale') locale: string = 'zh';

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  private trp(key: string, args: Record<string, string>): string {
    return I18n.tp(key, args, this.locale);
  }

  @State level: number = LEVEL_GROUP;
  @State titleText: string = '';
  @State loading: boolean = false;
  @State errorMessage: string = '';

  // GROUP 层
  @State groups: LaundryBuildingGroup[] = [];

  // FLOOR 层
  @State floors: LaundryFloor[] = [];

  private isDemo: boolean = true;
  private currentBuilding: LaundryBuilding = new LaundryBuilding();

  /** 系统返回拦截：FLOOR 逐级回 GROUP，GROUP 层交回宿舍页电费视图 */
  private backHandler: BackHandler = (): boolean => {
    if (this.level === LEVEL_GROUP) {
      this.onBack();
      return true;
    }
    this.goBackOneLevel();
    return true;
  };

  aboutToAppear(): void {
    this.isDemo = !(AuthManager.isLoggedIn() && !StateManager.isDemoMode());
    BackDispatcher.push(BackOwner.CAMPUS, this.backHandler);
    this.loadGroupLevel();
  }

  aboutToDisappear(): void {
    BackDispatcher.remove(this.backHandler);
  }

  // ── 层级导航 ────────────────────────────────

  private goBackOneLevel(): void {
    this.level = LEVEL_GROUP;
    this.titleText = this.tr('laundry.title');
  }

  private handleHeaderBack(): void {
    if (this.level === LEVEL_GROUP) {
      this.onBack();
    } else {
      this.goBackOneLevel();
    }
  }

  // ── 数据加载（演示模式零网络请求） ────────────────────────────────

  private extractError(e: Object): string {
    return e instanceof Error ? e.message : String(e);
  }

  /** GROUP 层：楼宇分组列表 */
  private async loadGroupLevel(): Promise<void> {
    this.level = LEVEL_GROUP;
    this.titleText = this.tr('laundry.title');
    this.errorMessage = '';
    if (this.isDemo) {
      this.groups = getDemoGroups();
      return;
    }
    this.loading = true;
    try {
      const service: LaundryService = SessionManager.getLaundryService();
      this.groups = await service.getLaundryBuildings();
    } catch (e) {
      this.errorMessage = this.extractError(e);
    }
    this.loading = false;
  }

  /** 点击楼宇 → FLOOR 层（楼层与机台） */
  private async openBuilding(building: LaundryBuilding): Promise<void> {
    this.currentBuilding = building;
    this.level = LEVEL_FLOOR;
    this.titleText = building.name.length > 0 ? building.name : this.tr('laundry.title');
    this.errorMessage = '';
    if (this.isDemo) {
      this.floors = getDemoFloors(building.platform);
      return;
    }
    this.loading = true;
    try {
      const service: LaundryService = SessionManager.getLaundryService();
      this.floors = await service.getLaundryFloors(building);
    } catch (e) {
      this.errorMessage = this.extractError(e);
    }
    this.loading = false;
  }

  /** 右上角刷新 / 错误重试：按当前层级重拉 */
  private async refreshCurrentLevel(): Promise<void> {
    if (this.level === LEVEL_FLOOR) {
      await this.openBuilding(this.currentBuilding);
    } else {
      await this.loadGroupLevel();
    }
  }

  // ── 展示辅助 ────────────────────────────────

  private platformLabel(platform: LaundryPlatform): string {
    return this.tr(platform === 'haile' ? 'laundry.platformHaile' : 'laundry.platformJieli');
  }

  private statusText(status: LaundryMachineStatus): string {
    if (status === 'idle') {
      return this.tr('laundry.statIdle');
    }
    if (status === 'working') {
      return this.tr('laundry.statWorking');
    }
    return this.tr('laundry.statError');
  }

  private statusColor(status: LaundryMachineStatus): string {
    if (status === 'idle') {
      return Theme.success;
    }
    if (status === 'working') {
      return Theme.warning;
    }
    return Theme.error;
  }

  private statusBg(status: LaundryMachineStatus): string {
    if (status === 'idle') {
      return Theme.successMuted;
    }
    if (status === 'working') {
      return Theme.warningMuted;
    }
    return Theme.errorMuted;
  }

  /** 机台状态徽标文本（使用中且剩余时间可得时附加"剩余 N 分钟"） */
  private machineBadgeText(machine: LaundryMachine): string {
    if (machine.status === 'working' && machine.etaMinutes >= 0) {
      return this.statusText(machine.status) + ' · '
        + this.trp('laundry.remaining', { 'n': String(machine.etaMinutes) });
    }
    return this.statusText(machine.status);
  }

  /** 机台主文本："类型 名称"（FR-004：类型必须展示；名称缺失回退类型） */
  private machineMainText(machine: LaundryMachine): string {
    const type: string = machine.type.length > 0 ? machine.type : '';
    const name: string = machine.name.length > 0 ? machine.name : '';
    if (type.length > 0 && name.length > 0) {
      return type + ' ' + name;
    }
    if (type.length > 0) {
      return type;
    }
    return name.length > 0 ? name : '—';
  }

  /** FLOOR 层按状态统计机台数 */
  private countByStatus(status: LaundryMachineStatus): number {
    let count: number = 0;
    for (let i: number = 0; i < this.floors.length; i++) {
      const machines: LaundryMachine[] = this.floors[i].machines;
      for (let j: number = 0; j < machines.length; j++) {
        if (machines[j].status === status) {
          count++;
        }
      }
    }
    return count;
  }

  /** FLOOR 层机台总数 */
  private machineTotal(): number {
    let total: number = 0;
    for (let i: number = 0; i < this.floors.length; i++) {
      total += this.floors[i].machines.length;
    }
    return total;
  }

  // ── UI ────────────────────────────────

  /**
   * 页内头部（复刻 DetailHeader 版式）：
   * 标题直接绑定 this.titleText（自定义组件普通成员只初始化一次、不随父状态刷新，
   * 故不能经 DetailHeader 传入动态标题）。
   */
  @Builder
  private HeaderBar() {
    Row() {
      Text('‹')
        .fontSize(32)
        .fontWeight(FontWeight.Lighter)
        .fontColor(Theme.text)
        .width(40)
        .height(40)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.handleHeaderBack();
        })

      Text(this.titleText)
        .fontSize(FontSize.h3)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .maxLines(1)

      Column() {
        this.RightAction()
      }
      .width(40)
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding({ left: Space.sm, right: Space.md, top: Space.sm, bottom: Space.sm })
    .alignItems(VerticalAlign.Center)
  }

  /** 右上角刷新：加载中转加载指示（FR-008） */
  @Builder
  private RightAction() {
    if (this.loading) {
      LoadingProgress()
        .width(20)
        .height(20)
        .color(Theme.primary)
    } else {
      Text('↻')
        .fontSize(20)
        .fontColor(Theme.primary)
        .width(40)
        .height(40)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.refreshCurrentLevel();
        })
    }
  }

  @Builder
  private ErrorView() {
    Column() {
      StateBlock({
        tone: StateTone.Error,
        title: this.level === LEVEL_GROUP ? this.tr('laundry.errorBuildings') : this.tr('laundry.errorFloors'),
        message: this.errorMessage,
        actionText: this.tr('status.retry'),
        onAction: () => {
          this.refreshCurrentLevel();
        },
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(Space.md)
  }

  @Builder
  private BuildingRow(building: LaundryBuilding) {
    Row() {
      Text(building.name.length > 0 ? building.name : '—')
        .fontSize(FontSize.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      Text(this.platformLabel(building.platform))
        .fontSize(FontSize.micro)
        .fontColor(Theme.textMuted)
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .borderRadius(Radius.pill)
        .backgroundColor(Theme.surfaceAlt)

      Text('›')
        .fontSize(22)
        .fontColor(Theme.textMuted)
        .margin({ left: Space.sm })
    }
    .width('100%')
    .constraintSize({ maxWidth: '100%' })
    .padding({ left: Space.md, right: Space.md, top: 13, bottom: 13 })
    .onClick(() => {
      this.openBuilding(building);
    })
  }

  @Builder
  private GroupSection(group: LaundryBuildingGroup) {
    Column() {
      Text(group.name)
        .fontSize(FontSize.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.textSecondary)
        .width('100%')
        .padding({ left: Space.md, right: Space.md, top: Space.md, bottom: Space.sm })

      Column() {
        ForEach(group.buildings, (building: LaundryBuilding, index: number) => {
          this.BuildingRow(building)
          if (index < group.buildings.length - 1) {
            Divider().color(Theme.divider).margin({ left: Space.md })
          }
        }, (building: LaundryBuilding) => building.platform + '-' + building.id)
      }
      .width('100%')
      .constraintSize({ maxWidth: '100%' })
      .alignItems(HorizontalAlign.Start)
      .borderRadius(Theme.cardRadius)
      .backgroundColor(Theme.surface)
      .border({ width: 1, color: Theme.borderSubtle })
      .margin({ left: Space.md, right: Space.md })
    }
    .width('100%')
    .constraintSize({ maxWidth: '100%' })
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: Space.sm })
  }

  /** GROUP 层：分组楼宇列表 */
  @Builder
  private GroupLayer() {
    Scroll() {
      Column() {
        if (this.isDemo) {
          Text(this.tr('laundry.demoHint'))
            .fontSize(FontSize.micro)
            .fontColor(Theme.textMuted)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: Space.sm, bottom: Space.xs })
        }

        StateBlock({
          tone: StateTone.Info,
          message: this.tr('laundry.hintBuildings'),
        })
        .margin({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.md })

        if (this.groups.length === 0) {
          EmptyHint({
            title: this.tr('laundry.emptyBuildings'),
            message: this.tr('laundry.emptyBuildingsHint'),
          })
        } else {
          ForEach(this.groups, (group: LaundryBuildingGroup) => {
            this.GroupSection(group)
          }, (group: LaundryBuildingGroup) => group.name + '-' + String(group.buildings.length))
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  private MachineCard(machine: LaundryMachine) {
    Column({ space: Space.xs }) {
      Row({ space: Space.xs }) {
        Column()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(this.statusColor(machine.status))
          .margin({ top: 5 })

        Text(this.machineMainText(machine))
          .fontSize(FontSize.label)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      if (machine.location.length > 0) {
        Text(machine.location)
          .fontSize(FontSize.micro)
          .fontColor(Theme.textMuted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      Text(this.machineBadgeText(machine))
        .fontSize(FontSize.micro)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.statusColor(machine.status))
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .borderRadius(Radius.pill)
        .backgroundColor(this.statusBg(machine.status))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (machine.updatedAt.length > 0) {
        Text(this.trp('laundry.updatedAt', { 'name': machine.updatedAt }))
          .fontSize(FontSize.micro)
          .fontColor(Theme.textMuted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('48.5%')
    .constraintSize({ maxWidth: '100%' })
    .alignItems(HorizontalAlign.Start)
    .padding({ left: Space.md, right: Space.md, top: 13, bottom: 13 })
    .borderRadius(Theme.cardRadius)
    .backgroundColor(Theme.surface)
    .border({ width: 1, color: Theme.borderSubtle })
    .margin({ bottom: Space.sm })
  }

  @Builder
  private FloorSection(floor: LaundryFloor) {
    Column() {
      Text(floor.name.length > 0 ? floor.name : this.tr('laundry.floorFallback'))
        .fontSize(FontSize.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.textSecondary)
        .width('100%')
        .padding({ left: Space.md, right: Space.md, top: Space.md, bottom: Space.sm })

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(floor.machines, (machine: LaundryMachine, index: number) => {
          this.MachineCard(machine)
        }, (machine: LaundryMachine, index: number) =>
          machine.floor + '-' + machine.type + '-' + machine.name + '-' + machine.status + '-' + String(index))
      }
      .width('100%')
      .padding({ left: Space.md, right: Space.md })
    }
    .width('100%')
    .constraintSize({ maxWidth: '100%' })
    .alignItems(HorizontalAlign.Start)
  }

  /** FLOOR 层：状态汇总 + 楼层与机台列表 */
  @Builder
  private FloorLayer() {
    Scroll() {
      Column() {
        // 状态汇总（空闲/使用中/异常）
        Row({ space: Space.sm }) {
          MetricPill({
            value: String(this.countByStatus('idle')),
            label: this.tr('laundry.statIdle'),
            tone: BadgeTone.Success,
          })
          MetricPill({
            value: String(this.countByStatus('working')),
            label: this.tr('laundry.statWorking'),
            tone: BadgeTone.Warning,
          })
          MetricPill({
            value: String(this.countByStatus('error')),
            label: this.tr('laundry.statError'),
            tone: BadgeTone.Error,
          })
        }
        .width('100%')
        .constraintSize({ maxWidth: '100%' })
        .margin({ left: Space.md, right: Space.md, top: Space.md, bottom: Space.xs })

        // 平台来源标注
        Text(this.platformLabel(this.currentBuilding.platform))
          .fontSize(FontSize.micro)
          .fontColor(Theme.textMuted)
          .width('100%')
          .textAlign(TextAlign.Start)
          .padding({ left: Space.md, right: Space.md, top: Space.xs, bottom: Space.xs })

        if (this.floors.length === 0) {
          EmptyHint({
            title: this.tr('laundry.emptyFloors'),
            message: this.tr('laundry.emptyFloorsHint'),
          })
        } else {
          ForEach(this.floors, (floor: LaundryFloor) => {
            this.FloorSection(floor)
          }, (floor: LaundryFloor) => floor.name + '-' + String(floor.machines.length))

          Text(this.tr('laundry.thirdPartyNote'))
            .fontSize(FontSize.micro)
            .fontColor(Theme.textMuted)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.lg })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  build() {
    Column() {
      this.HeaderBar()
      Divider().color(Theme.divider)

      if (this.loading) {
        Column({ space: Space.md }) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(Theme.primary)
          Text(this.tr('status.loading'))
            .fontSize(FontSize.caption)
            .fontColor(Theme.textMuted)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        if (this.errorMessage.length > 0) {
          this.ErrorView()
        } else {
          if (this.level === LEVEL_GROUP) {
            this.GroupLayer()
          } else {
            this.FloorLayer()
          }
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}
