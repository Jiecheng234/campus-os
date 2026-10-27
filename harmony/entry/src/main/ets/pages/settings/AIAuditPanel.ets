/**
 * ============================================================================
 * AIAuditPanel — AI 行为审计面板（ai-governance 特性，US1）
 * ============================================================================
 *
 * - 数据源：ActionAuditStore（持久化，跨重启保留 200 条）；面板内最多展示
 *   最近 6 条（PANEL_MAX_ROWS）。
 * - 刷新：@StorageLink(AUDIT_TICK_KEY) + @Watch 订阅 store 的写入/清空信号
 *   （单调递增计数）；tick 只读内存缓存（getRecords），不重复读盘；
 *   语言切换经 @StorageLink('locale') 即时重渲染。
 * - 交互：点击条目展开治理链详情（权限/确认/影响资源/脱敏参数/结果/错误/
 *   验证结论）；展开值均为 store 落盘前的脱敏副本，不渲染原始敏感值。
 * - 展示：本地时间 yyyy-MM-dd HH:mm；状态/风险/确认状态走 i18n 标签，
 *   未知枚举值回退原始字符串；工具展示名缺失时回退工具名。
 */
import { ActionExecutionStatus, AuditRecord, ConfirmationStatus } from '../../domain/ActionTypes';
import { AgentService } from '../../services/ai/AgentService';
import { ActionAuditStore, AUDIT_TICK_KEY } from '../../storage/ActionAuditStore';
import { I18n } from '../../utils/I18n';
import { Theme, Space, Radius, FontSize } from '../Theme';
import { BadgeTone, EmptyHint, SectionHeader, StatusBadge } from '../../components/Ui';

/** 面板内最多展示条数（持久层完整保留 200 条） */
const PANEL_MAX_ROWS: number = 6;

function pad2(n: number): string {
  return n < 10 ? '0' + n : '' + n;
}

/** ISO 时间 → 本地 yyyy-MM-dd HH:mm（非法回退原始串截断） */
function formatAuditTime(iso: string): string {
  const d: Date = new Date(iso);
  const t: number = d.getTime();
  if (Number.isNaN(t)) {
    return iso.length > 16 ? iso.substring(0, 16) : iso;
  }
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ` +
    `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

@Component
export struct AIAuditPanel {
  /** 语言运行时状态（AppStorage）：切换即时重渲染 */
  @StorageLink('locale') locale: string = 'zh';
  /** 审计刷新信号（store 写入/清空时以单调递增计数投递） */
  @StorageLink(AUDIT_TICK_KEY) @Watch('onAuditTick') auditTick: number = 0;
  @State records: AuditRecord[] = [];
  /** 持久层记录总数（面板仅展示最近 6 条，清空按钮按总数显示） */
  @State totalCount: number = 0;
  @State expandedId: string = '';
  /** 持久层读取失败（不谎报"暂无记录"；ensureLoaded 可重试） */
  @State loadFailed: boolean = false;

  aboutToAppear(): void {
    // 已加载过（如从子页返回）：同步渲染，再幂等确认
    if (ActionAuditStore.isLoaded()) {
      this.refresh();
    }
    ActionAuditStore.ensureLoaded().then((): void => {
      this.loadFailed = false;
      this.refresh();
    }).catch((): void => {
      this.loadFailed = true;
    });
  }

  private onAuditTick(): void {
    this.refresh();
  }

  /** 只读内存缓存渲染（ensureLoaded / tick 后调用），不重复读盘 */
  private refresh(): void {
    const records: AuditRecord[] = ActionAuditStore.getRecords();
    this.totalCount = records.length;
    this.records = records.length > PANEL_MAX_ROWS ? records.slice(0, PANEL_MAX_ROWS) : records;
  }

  // ============================================================
  // 清空审计记录（二次确认 → store 清空 → auditTick 回调刷新空态）
  // ============================================================

  private confirmClear(): void {
    this.getUIContext().showAlertDialog({
      title: this.tr('settings.aiAuditClearTitle'),
      message: this.tr('settings.aiAuditClearMessage'),
      primaryButton: {
        value: this.tr('common.cancel'),
        action: (): void => {}
      },
      secondaryButton: {
        value: this.tr('settings.aiAuditClearOk'),
        fontColor: Theme.error,
        action: (): void => { this.doClear(); }
      }
    });
  }

  private doClear(): void {
    // FR-007：内存会话列表与持久化同时清空——clearAuditRecords 内部双清
    // （AgentService.auditRecords + ActionAuditStore.clear），无循环依赖。
    // 持久化清空失败上抛 → toast；tick（成功/失败均发）驱动列表刷新
    AgentService.clearAuditRecords().catch((): void => {
      this.showToast(this.tr('settings.aiAuditClearFailed'));
    });
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (e) {
      /* ignore */
    }
  }

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  private trp(key: string, args: Record<string, string>): string {
    return I18n.tp(key, args, this.locale);
  }

  /** 工具展示名：标题缺失回退工具名 */
  private toolDisplay(rec: AuditRecord): string {
    return rec.toolTitle.length > 0 ? rec.toolTitle : rec.toolName;
  }

  private statusLabel(rec: AuditRecord): string {
    if (rec.status === ActionExecutionStatus.SUCCESS) {
      return this.tr('ai.traceOk');
    }
    if (rec.status === ActionExecutionStatus.ERROR) {
      return this.tr('ai.traceError');
    }
    if (rec.status === ActionExecutionStatus.CANCELLED) {
      return this.tr('ai.traceCancelled');
    }
    return rec.status.length > 0 ? rec.status : '—';
  }

  private statusTone(rec: AuditRecord): BadgeTone {
    if (rec.status === ActionExecutionStatus.SUCCESS) {
      return BadgeTone.Success;
    }
    if (rec.status === ActionExecutionStatus.ERROR) {
      return BadgeTone.Error;
    }
    return BadgeTone.Warning;
  }

  private riskLabel(risk: string): string {
    if (risk === 'none') {
      return this.tr('ai.riskNone');
    }
    if (risk === 'low') {
      return this.tr('ai.riskLow');
    }
    if (risk === 'medium') {
      return this.tr('ai.riskMedium');
    }
    if (risk === 'high') {
      return this.tr('ai.riskHigh');
    }
    return risk.length > 0 ? risk : '—';
  }

  private confirmationLabel(rec: AuditRecord): string {
    if (rec.confirmation === ConfirmationStatus.NOT_REQUIRED) {
      return this.tr('ai.confirmNotRequired');
    }
    if (rec.confirmation === ConfirmationStatus.APPROVED) {
      return this.tr('ai.confirmApproved');
    }
    if (rec.confirmation === ConfirmationStatus.DENIED) {
      return this.tr('ai.confirmDenied');
    }
    if (rec.confirmation === ConfirmationStatus.UNAVAILABLE) {
      return this.tr('ai.confirmUnavailable');
    }
    return rec.confirmation.length > 0 ? rec.confirmation : '—';
  }

  /** 验证行仅在"已执行验证"时展示（成功或带失败信息） */
  private hasVerification(rec: AuditRecord): boolean {
    return rec.verificationOk || rec.verificationMessage.length > 0;
  }

  private verificationText(rec: AuditRecord): string {
    const verdict: string = rec.verificationOk ? this.tr('ai.verifyOk') : this.tr('ai.verifyFailed');
    return rec.verificationMessage.length > 0 ? `${verdict}（${rec.verificationMessage}）` : verdict;
  }

  private toggleExpand(id: string): void {
    this.expandedId = this.expandedId === id ? '' : id;
  }

  build() {
    Column() {
      SectionHeader({ title: this.tr('settings.sectionGovernance') })
        .padding({ left: Space.lg, right: Space.lg })

      Column() {
        // ── 审计标题区（右侧清空入口，仅有记录时显示）──
        Row() {
          Column({ space: 2 }) {
            Text(this.tr('settings.aiAuditTitle'))
              .fontSize(FontSize.label)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.text)
            Text(this.tr('settings.aiAuditDesc'))
              .fontSize(FontSize.micro)
              .fontColor(Theme.textMuted)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          if (this.totalCount > 0) {
            // 清空入口用 Button 而非裸 Text：命中区更明确，避免在卡片右缘被裁切后
            // 只剩文字局部可点（自动化/触屏均更稳定）
            Button(this.trp('settings.aiAuditClearWithCount', { 'n': `${this.totalCount}` }))
              .type(ButtonType.Normal)
              .fontSize(FontSize.caption)
              .fontColor(Theme.error)
              .backgroundColor(Color.Transparent)
              .height(36)
              .padding({ left: Space.sm, right: Space.sm })
              .constraintSize({ maxWidth: '55%' })
              .onClick(() => { this.confirmClear(); })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: Space.md, right: Space.md, top: Space.md, bottom: Space.sm })

        if (this.loadFailed) {
          // 读取失败：给出可读提示，不谎报"暂无审计记录"（重进面板会重试加载）
          Text(this.tr('settings.aiAuditLoadFailed'))
            .fontSize(FontSize.micro)
            .fontColor(Theme.error)
            .padding({ top: Space.sm, bottom: Space.md })
        } else if (this.records.length === 0) {
          EmptyHint({ title: this.tr('settings.aiAuditEmpty'), message: '' })
            .padding({ top: Space.sm, bottom: Space.md })
        } else {
          ForEach(this.records, (rec: AuditRecord, index: number) => {
            Column() {
              if (index > 0) {
                Divider()
                  .color(Theme.divider)
                  .width('100%')
                  .margin({ left: Space.md })
              }
              this.RecordRow(rec)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }, (rec: AuditRecord) => rec.id)
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: '100%' })
      .borderRadius(Radius.lg)
      .backgroundColor(Theme.surface)
      .border({ width: 1, color: Theme.borderSubtle })
      .margin({ left: Space.lg, right: Space.lg })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 单条审计记录：折叠行 + 展开详情 */
  @Builder
  RecordRow(rec: AuditRecord) {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Row({ space: Space.sm }) {
            Text(this.toolDisplay(rec))
              .fontSize(FontSize.label)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.text)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            StatusBadge({ text: this.statusLabel(rec), tone: this.statusTone(rec) })
          }
          .width('100%')

          Row({ space: Space.sm }) {
            Text(formatAuditTime(rec.timestamp))
              .fontSize(FontSize.micro)
              .fontColor(Theme.textMuted)
            Text(this.riskLabel(rec.risk))
              .fontSize(FontSize.micro)
              .fontColor(Theme.textMuted)
            if (rec.permission.length > 0) {
              Text(rec.permission)
                .fontSize(FontSize.micro)
                .fontColor(Theme.textMuted)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
          }
          .width('100%')

          if (rec.resultSummary.length > 0 && this.expandedId !== rec.id) {
            Text(rec.resultSummary)
              .fontSize(FontSize.micro)
              .fontColor(Theme.textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(this.expandedId === rec.id ? '⌄' : '›')
          .fontSize(18)
          .fontWeight(FontWeight.Lighter)
          .fontColor(Theme.textMuted)
          .margin({ left: Space.sm })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: Space.md, right: Space.md, top: Space.md, bottom: Space.md })
      .onClick(() => {
        this.toggleExpand(rec.id);
      })

      if (this.expandedId === rec.id) {
        Column({ space: Space.sm }) {
          this.DetailText(this.tr('ai.auditPermission'), rec.permission.length > 0 ? rec.permission : '—')
          this.DetailText(this.tr('ai.auditConfirmation'), this.confirmationLabel(rec))
          if (rec.previewAffectedResource.length > 0) {
            this.DetailText(this.tr('ai.auditAffected'), rec.previewAffectedResource)
          }
          if (rec.paramsJson.length > 0) {
            this.DetailText(this.tr('ai.auditParams'), rec.paramsJson)
          }
          if (rec.result.length > 0) {
            this.DetailText(this.tr('ai.auditResult'), rec.result)
          }
          if (rec.errorMessage.length > 0) {
            this.DetailText(this.tr('ai.auditError'), rec.errorMessage)
          }
          if (this.hasVerification(rec)) {
            this.DetailText(this.tr('ai.auditVerification'), this.verificationText(rec))
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: Space.md, right: Space.md, bottom: Space.md })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 详情块：标签 + 脱敏值（长文本截断，不渲染未脱敏原文） */
  @Builder
  DetailText(label: string, value: string) {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(FontSize.micro)
        .fontColor(Theme.textMuted)
      Text(value)
        .fontSize(FontSize.micro)
        .fontColor(Theme.text)
        .width('100%')
        .maxLines(8)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
