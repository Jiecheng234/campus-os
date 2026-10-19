/**
 * ScheduleGrid — 块状课表网格（纯展示组件）
 *
 * 【职责边界】只负责渲染：左侧时间轴（大节"起-止"）+ 日列头（星期 + MM-DD）
 * + 每日纵向堆叠的课程块（跨节块高 = 跨越节数 × 单元高）。
 * 不发起请求、不读写存储、不硬编码文案——所有静态字样（星期/日期/时间轴）由调用方传入。
 *
 * 【堆叠策略（无绝对定位）】每日列按节次顺序堆叠：
 *  - 遇到某块 startPeriod → 渲染高度 = (endPeriod-startPeriod+1)×cellHeight 的块；
 *  - 被已渲染跨节块覆盖的节次 → 跳过（不重复渲染空单元）；
 *  - 其余节次 → 渲染空单元。
 *
 * 【重叠课程】同日同一起始节的多个块 → 同槽并列（横向 layoutWeight 均分，各自高度按
 * 自身跨度）；与前面跨节块部分重叠的块 → 顺延至下一空节位堆叠（保证可辨识、不破版）。
 *
 * 【配色】16 组调色板（浅色底 + 深色前景 + 同系边框）；页面两段式分配：
 * 先映射全部课程块，再 assignScheduleColorIndexes 按「课名散列基址 + 冲突线性探测」
 * 统一回填 colorIndex——同名恒同色、本周不同课名（≤16）零撞色、未冲突课程跨周稳定。
 *
 * 【时间指示线】仅 todayIndex 对应日列渲染：nowMinuteOfDay 按大节刻度换算纵向偏移
 * （节内比例插值、课间吸附节边界、08:00 前/21:45 后隐藏），Stack 叠加不占布局、
 * 不挡课程点击（hitTestBehavior None）。
 *
 * 【文本规则】块内自上而下：课程名（多行，优先）→ 地点（多行；空白地点不渲染行）；
 * 块高不足时经 maxLines + textOverflow + clip 安全裁剪，不溢出、不遮挡相邻块。
 */
import { Theme } from '../pages/Theme';
import { Log } from '../utils/Logger';

/** 大节起始时间（清华 6 大节，与教务 zhjw 课表分桶一致） */
export const SCHEDULE_PERIOD_STARTS: string[] = ['08:00', '09:50', '13:30', '15:20', '17:05', '19:20'];
/** 大节结束时间（时间轴"起-止"显示；页面结束节次判定同源语义） */
export const SCHEDULE_PERIOD_ENDS: string[] = ['09:35', '12:15', '15:05', '16:55', '18:40', '21:45'];
/** 大节数（勿改，与教务数据约定绑定） */
export const SCHEDULE_PERIOD_COUNT: number = 6;
/** 日列数（周一 → 周日） */
export const SCHEDULE_DAY_COUNT: number = 7;

const DAY_INDEXES: number[] = [0, 1, 2, 3, 4, 5, 6];

/** "HH:mm" → 当日分钟数；解析失败返回 -1 */
function parseHmToMinutes(text: string): number {
  const parts: string[] = text.trim().split(':');
  if (parts.length < 2) {
    return -1;
  }
  const h: number = Number(parts[0]);
  const m: number = Number(parts[1]);
  if (isNaN(h) || isNaN(m) || h < 0 || h > 23 || m < 0 || m > 59) {
    return -1;
  }
  return h * 60 + m;
}

/** 6 大节起止分钟数（由 SCHEDULE_PERIOD_STARTS/ENDS 解析，时间线换算与时间轴同源） */
const PERIOD_START_MINUTES: number[] = SCHEDULE_PERIOD_STARTS.map((s: string): number => parseHmToMinutes(s));
const PERIOD_END_MINUTES: number[] = SCHEDULE_PERIOD_ENDS.map((s: string): number => parseHmToMinutes(s));

/**
 * 当前时刻 → 时间指示线纵向偏移（vp）：
 *  - 无有效时间 / 早于首节开始（08:00）/ 晚于末节结束（21:45）→ -1（隐藏）；
 *  - 落在某大节内 → 节内按时间比例插值：periodIndex × cellHeight + 比例 × cellHeight；
 *  - 落在课间间隔 → 吸附到下一节上边界（= 前一大节索引+1）× cellHeight。
 */
export function scheduleNowLineOffset(nowMinuteOfDay: number, cellHeight: number): number {
  if (nowMinuteOfDay < 0 || PERIOD_START_MINUTES.length === 0
    || PERIOD_START_MINUTES.length !== PERIOD_END_MINUTES.length) {
    return -1;
  }
  if (nowMinuteOfDay < PERIOD_START_MINUTES[0]
    || nowMinuteOfDay > PERIOD_END_MINUTES[PERIOD_END_MINUTES.length - 1]) {
    return -1;
  }
  for (let i: number = 0; i < PERIOD_START_MINUTES.length; i++) {
    const s: number = PERIOD_START_MINUTES[i];
    const e: number = PERIOD_END_MINUTES[i];
    if (e > s && nowMinuteOfDay >= s && nowMinuteOfDay <= e) {
      const ratio: number = (nowMinuteOfDay - s) / (e - s);
      return i * cellHeight + ratio * cellHeight;
    }
    if (nowMinuteOfDay < s) {
      return i * cellHeight;
    }
  }
  return -1;
}

/**
 * 课程块 UI 模型（仅渲染用）。
 * 页面把 ScheduleEvent（或演示示例）换算为该模型后交给网格渲染。
 */
export class ScheduleBlock {
  /** 星期下标 0-6（周一为 0） */
  dayIndex: number = 0;
  /** 起始大节 0-5 */
  startPeriod: number = 0;
  /** 结束大节 0-5（含） */
  endPeriod: number = 0;
  /** 课程名（多行展示，优先保证） */
  title: string = '';
  /** 上课地点（多行展示；空白则不渲染地点行） */
  location: string = '';
  /** 调色板下标（课程名确定性散列结果，由页面计算） */
  colorIndex: number = 0;
  /** 上课日期（YYYY-MM-DD，详情弹层展示用） */
  date: string = '';
  /** 课程开始时间原文（HH:mm，详情弹层展示用） */
  startTime: string = '';
  /** 课程结束时间原文（HH:mm，可为空；详情弹层展示用） */
  endTime: string = '';
}

/** 调色板条目：柔和底色 + 深色前景（对比度安全）+ 同系描边 */
class SchedulePaletteEntry {
  bg: string = '';
  fg: string = '';
  border: string = '';
}

function paletteEntry(bg: string, fg: string, border: string): SchedulePaletteEntry {
  const e: SchedulePaletteEntry = new SchedulePaletteEntry();
  e.bg = bg;
  e.fg = fg;
  e.border = border;
  return e;
}

/**
 * 固定调色板（16 组 ≥6，浅色主题；散列取模稳定映射）。
 * 前 8 组为既有配色（紫/绿/橙/天蓝/粉/黄/藕紫/青）；后 8 组为课表交互增强追加，
 * 按色相环补齐（柠绿/湖蓝/正蓝/靛蓝/洋红/玫红/红/棕），均浅底 + 深字 + 同系边框，
 * 与既有 8 组不重复且彼此可区分。
 */
const SCHEDULE_PALETTE: SchedulePaletteEntry[] = [
  paletteEntry('#EDE9FE', '#4C1D95', '#C4B5FD'), // 紫
  paletteEntry('#DCFCE7', '#14532D', '#86EFAC'), // 绿
  paletteEntry('#FFEDD5', '#7C2D12', '#FDBA74'), // 橙
  paletteEntry('#E0F2FE', '#0C4A6E', '#7DD3FC'), // 天蓝
  paletteEntry('#FCE7F3', '#831843', '#F9A8D4'), // 粉
  paletteEntry('#FEF9C3', '#713F12', '#FDE047'), // 黄
  paletteEntry('#F3E8FF', '#581C87', '#D8B4FE'), // 藕紫
  paletteEntry('#CCFBF1', '#134E4A', '#5EEAD4'), // 青
  paletteEntry('#ECFCCB', '#3F6212', '#BEF264'), // 柠绿
  paletteEntry('#CFFAFE', '#155E75', '#A5F3FC'), // 湖蓝
  paletteEntry('#DBEAFE', '#1E3A8A', '#93C5FD'), // 正蓝
  paletteEntry('#E0E7FF', '#312E81', '#A5B4FC'), // 靛蓝
  paletteEntry('#FAE8FF', '#701A75', '#E9D5FF'), // 洋红
  paletteEntry('#FFE4E6', '#9F1239', '#FDA4AF'), // 玫红
  paletteEntry('#FEE2E2', '#7F1D1D', '#FCA5A5'), // 红
  paletteEntry('#F7E8DA', '#5D4037', '#D7BFA8'), // 棕
];

/** 课程名确定性散列 → 调色板下标（同名恒同色，跨周/跨会话一致） */
export function scheduleColorIndexForTitle(title: string): number {
  let h: number = 0;
  for (let i: number = 0; i < title.length; i++) {
    h = (h * 31 + title.charCodeAt(i)) >>> 0;
  }
  return h % SCHEDULE_PALETTE.length;
}

/**
 * 本周课程配色统一分配（两段式配色的第二段）：
 *  - 输入去重 → 按字典序排序（分配结果与接口返回顺序无关，跨次渲染稳定）；
 *  - 以 scheduleColorIndexForTitle 为基址；基址被其它课名占用 → 线性探测下一个空闲色；
 *  - 不同课名数 ≤ 调色板容量（16）时值两两不同；超出时剩余项回落基址并告警一次。
 * 未冲突课程始终落在基址 → 跨周保持同色。
 */
export function assignScheduleColorIndexes(titles: string[]): Map<string, number> {
  const seen: Set<string> = new Set<string>();
  const uniqueTitles: string[] = [];
  for (let i: number = 0; i < titles.length; i++) {
    const t: string = titles[i];
    if (!seen.has(t)) {
      seen.add(t);
      uniqueTitles.push(t);
    }
  }
  uniqueTitles.sort((a: string, b: string): number => a.localeCompare(b));
  const capacity: number = SCHEDULE_PALETTE.length;
  const occupied: Set<number> = new Set<number>();
  const result: Map<string, number> = new Map<string, number>();
  let overflowWarned: boolean = false;
  for (let i: number = 0; i < uniqueTitles.length; i++) {
    const title: string = uniqueTitles[i];
    const base: number = scheduleColorIndexForTitle(title);
    let assigned: number = base;
    if (occupied.has(base)) {
      let probe: number = (base + 1) % capacity;
      while (probe !== base && occupied.has(probe)) {
        probe = (probe + 1) % capacity;
      }
      if (occupied.has(probe)) {
        // 无空闲色（不同课名数超过容量）：回落基址，仅告警一次
        assigned = base;
        if (!overflowWarned) {
          Log.i('SchedGrid', 'COLOR_OVERFLOW unique=%{public}d capacity=%{public}d fallback=base',
            uniqueTitles.length, capacity);
          overflowWarned = true;
        }
      } else {
        assigned = probe;
      }
    }
    occupied.add(assigned);
    result.set(title, assigned);
  }
  return result;
}

/** 调色板取色（负数/越界安全取模） */
function paletteAt(index: number): SchedulePaletteEntry {
  const n: number = SCHEDULE_PALETTE.length;
  const i: number = ((index % n) + n) % n;
  return SCHEDULE_PALETTE[i];
}

/** 日列内的渲染槽：空单元，或同槽并列的一组课程块 */
class ScheduleSlot {
  /** true = 空占位单元；false = 课程块组 */
  isEmpty: boolean = true;
  /** 槽高（单元数） */
  heightCells: number = 1;
  /** 同槽并列的课程块（1..n） */
  blocks: ScheduleBlock[] = [];
}

function clampInt(v: number, lo: number, hi: number): number {
  if (isNaN(v)) {
    return lo;
  }
  if (v < lo) {
    return lo;
  }
  if (v > hi) {
    return hi;
  }
  return v;
}

/** 取某天的块（防御性钳制节次到 0-5；按起始节升序、跨度降序、课名稳定排序） */
function blocksForDay(blocks: ScheduleBlock[], dayIndex: number): ScheduleBlock[] {
  const result: ScheduleBlock[] = [];
  for (let i: number = 0; i < blocks.length; i++) {
    const raw: ScheduleBlock = blocks[i];
    if (raw.dayIndex !== dayIndex) {
      continue;
    }
    const b: ScheduleBlock = new ScheduleBlock();
    b.dayIndex = raw.dayIndex;
    b.startPeriod = clampInt(raw.startPeriod, 0, SCHEDULE_PERIOD_COUNT - 1);
    b.endPeriod = clampInt(raw.endPeriod, b.startPeriod, SCHEDULE_PERIOD_COUNT - 1);
    b.title = raw.title;
    b.location = raw.location;
    b.colorIndex = raw.colorIndex;
    b.date = raw.date;
    b.startTime = raw.startTime;
    b.endTime = raw.endTime;
    result.push(b);
  }
  result.sort((a: ScheduleBlock, c: ScheduleBlock): number => {
    if (a.startPeriod !== c.startPeriod) {
      return a.startPeriod - c.startPeriod;
    }
    if (a.endPeriod !== c.endPeriod) {
      return c.endPeriod - a.endPeriod;
    }
    return a.title.localeCompare(c.title);
  });
  return result;
}

/**
 * 某天的块 → 渲染槽序列（核心堆叠/跳过算法）：
 *  - 同一起始节的块合并为同槽并列（槽高 = 最大跨度）；
 *  - 块的起始节已被前面跨节块覆盖 → 顺延至当前空节位（顺序堆叠，保证可辨识）；
 *  - 空闲节次插入空占位单元；节位游标可越过末节（极端重叠时列高自然增长，不破版）。
 */
function buildDaySlots(blocks: ScheduleBlock[], dayIndex: number): ScheduleSlot[] {
  const dayBlocks: ScheduleBlock[] = blocksForDay(blocks, dayIndex);
  const slots: ScheduleSlot[] = [];
  let cursor: number = 0;
  let i: number = 0;
  while (i < dayBlocks.length) {
    const startP: number = dayBlocks[i].startPeriod;
    let j: number = i;
    const group: ScheduleBlock[] = [];
    while (j < dayBlocks.length && dayBlocks[j].startPeriod === startP) {
      group.push(dayBlocks[j]);
      j++;
    }
    let slotStart: number = startP;
    if (slotStart < cursor) {
      slotStart = cursor;
    }
    let span: number = 1;
    for (let k: number = 0; k < group.length; k++) {
      const s: number = group[k].endPeriod - group[k].startPeriod + 1;
      if (s > span) {
        span = s;
      }
    }
    while (cursor < slotStart) {
      const empty: ScheduleSlot = new ScheduleSlot();
      empty.isEmpty = true;
      empty.heightCells = 1;
      slots.push(empty);
      cursor++;
    }
    const slot: ScheduleSlot = new ScheduleSlot();
    slot.isEmpty = false;
    slot.heightCells = span;
    slot.blocks = group;
    slots.push(slot);
    cursor = slotStart + span;
    i = j;
  }
  while (cursor < SCHEDULE_PERIOD_COUNT) {
    const tail: ScheduleSlot = new ScheduleSlot();
    slots.push(tail);
    cursor++;
  }
  return slots;
}

@Component
export struct ScheduleGrid {
  /** 课程块（页面已完成节次区间换算与配色索引） */
  @Prop blocks: ScheduleBlock[] = [];
  /** 时间轴"起-止"文案（如 08:00-09:35；渲染时按'-'分两行） */
  @Prop axisLabels: string[] = [];
  /** 星期标签（i18n 文案，由页面传入） */
  @Prop dayLabels: string[] = [];
  /** 日期标签（MM-DD，随周次导航更新） */
  @Prop dateLabels: string[] = [];
  /** 单大节单元高度（vp） */
  @Prop cellHeight: number = 72;
  /** 左侧时间轴列宽（vp） */
  @Prop leftWidth: number = 48;
  /** 今天所在日列下标 0-6（-1 = 不显示当前时间指示线） */
  @Prop todayIndex: number = -1;
  /** 当前时刻距 0 点的分钟数（-1 = 无有效时间，不显示指示线） */
  @Prop nowMinuteOfDay: number = -1;
  /** 课程块点击回调（默认空实现；由页面接管打开详情弹层） */
  onBlockSelect: (block: ScheduleBlock) => void = () => {};

  /** 当前时间指示线纵向偏移（-1 = 隐藏；由 nowMinuteOfDay 与 6 大节刻度换算） */
  private nowLineOffset(): number {
    return scheduleNowLineOffset(this.nowMinuteOfDay, this.cellHeight);
  }

  /** "起-止"文案 → 起始时间（无'-'时原样返回） */
  private axisStartPart(label: string): string {
    const idx: number = label.indexOf('-');
    return idx > 0 ? label.substring(0, idx) : label;
  }

  /** "起-止"文案 → 结束时间（无'-'时返回空串） */
  private axisEndPart(label: string): string {
    const idx: number = label.indexOf('-');
    return idx > 0 ? label.substring(idx + 1) : '';
  }

  @Builder
  private DayHeaderBuilder() {
    Row() {
      Column()
        .width(this.leftWidth)
      ForEach(this.dayLabels, (label: string, dayIdx: number) => {
        Column() {
          Text(label)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
            .maxLines(1)
          if (dayIdx < this.dateLabels.length) {
            Text(this.dateLabels[dayIdx])
              .fontSize(9)
              .fontColor(Theme.textMuted)
              .maxLines(1)
              .margin({ top: 1 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      }, (label: string, dayIdx: number) => 'head-' + String(dayIdx) + '-' + label)
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
    .border({ width: { bottom: 1 }, color: Theme.divider })
  }

  @Builder
  private AxisCellBuilder(label: string) {
    Column() {
      Text(this.axisStartPart(label))
        .fontSize(9)
        .fontColor(Theme.textMuted)
        .maxLines(1)
      if (this.axisEndPart(label).length > 0) {
        Text(this.axisEndPart(label))
          .fontSize(9)
          .fontColor(Theme.textMuted)
          .maxLines(1)
          .margin({ top: 1 })
      }
    }
    .width('100%')
    .height(this.cellHeight)
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 4 })
  }

  @Builder
  private BlockBuilder(block: ScheduleBlock, spanCells: number) {
    Column() {
      Text(block.title)
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(paletteAt(block.colorIndex).fg)
        .maxLines(4)
        .lineHeight(13)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (block.location.trim().length > 0) {
        Text(block.location)
          .fontSize(9)
          .fontColor(paletteAt(block.colorIndex).fg)
          .maxLines(5)
          .lineHeight(12)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
          .opacity(0.85)
      }
    }
    .layoutWeight(1)
    .height(spanCells * this.cellHeight - 2)
    .padding(4)
    .borderRadius(6)
    .backgroundColor(paletteAt(block.colorIndex).bg)
    .border({ width: 1, color: paletteAt(block.colorIndex).border })
    .clip(true)
    .onClick(() => {
      this.onBlockSelect(block);
    })
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
  }

  /** 当前时间指示线：左端小圆点 + 2vp 横线；offsetY < 0 时不渲染；关闭命中测试（不挡课程点击） */
  @Builder
  private NowLineBuilder(offsetY: number) {
    if (offsetY >= 0) {
      Row({ space: 3 }) {
        Circle({ width: 5, height: 5 })
          .fill(Theme.error)
        Row()
          .height(2)
          .layoutWeight(1)
          .backgroundColor(Theme.error)
          .borderRadius(1)
      }
      .width('100%')
      .height(5)
      .alignItems(VerticalAlign.Center)
      .offset({ y: offsetY - 2 })
      .hitTestBehavior(HitTestMode.None)
    }
  }

  @Builder
  private DayColumnBuilder(dayIdx: number) {
    // Stack 叠加层：日列内容 + （仅今天列）当前时间指示线；宽度仍由 layoutWeight 均分
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        ForEach(buildDaySlots(this.blocks, dayIdx), (slot: ScheduleSlot, slotIdx: number) => {
          if (slot.isEmpty) {
            Column()
              .width('100%')
              .height(this.cellHeight)
              .border({ width: { bottom: 1 }, color: Theme.divider })
          } else {
            Row({ space: 2 }) {
              ForEach(slot.blocks, (block: ScheduleBlock, blockIdx: number) => {
                this.BlockBuilder(block, block.endPeriod - block.startPeriod + 1)
              }, (block: ScheduleBlock, blockIdx: number) =>
              'blk-' + String(dayIdx) + '-' + String(slotIdx) + '-' + String(blockIdx) + '-' + block.title)
            }
            .width('100%')
            .height(slot.heightCells * this.cellHeight)
            .padding({ top: 1, bottom: 1 })
            .border({ width: { bottom: 1 }, color: Theme.divider })
          }
        }, (slot: ScheduleSlot, slotIdx: number) =>
        'slot-' + String(dayIdx) + '-' + String(slotIdx) + '-' + String(slot.heightCells) + '-' + String(slot.blocks.length))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .border({ width: { right: 1 }, color: Theme.divider })

      // 当前时间指示线（仅 todayIndex 对应日列；offset < 0 时 Builder 内部不渲染）
      if (dayIdx === this.todayIndex) {
        this.NowLineBuilder(this.nowLineOffset())
      }
    }
    .layoutWeight(1)
  }

  @Builder
  private BodyBuilder() {
    Row() {
      // 左侧时间轴列（大节"起-止"，两行展示）
      Column() {
        ForEach(this.axisLabels, (label: string, periodIdx: number) => {
          this.AxisCellBuilder(label)
        }, (label: string, periodIdx: number) => 'axis-' + String(periodIdx) + '-' + label)
      }
      .width(this.leftWidth)
      .alignItems(HorizontalAlign.Center)
      .border({ width: { right: 1 }, color: Theme.divider })

      // 7 个日列（宽度均分自适应，无横向溢出）
      Row() {
        ForEach(DAY_INDEXES, (dayIdx: number) => {
          this.DayColumnBuilder(dayIdx)
        }, (dayIdx: number) => 'day-' + String(dayIdx))
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  build() {
    Column() {
      this.DayHeaderBuilder()
      this.BodyBuilder()
    }
    .width('100%')
    .constraintSize({ maxWidth: '100%' })
    .alignItems(HorizontalAlign.Start)
  }
}
