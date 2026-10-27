/**
 * ============================================================================
 * AgentTools — Agent 只读工具（35 个）+ 合并注册表
 * ============================================================================
 *
 * 【对齐参考实现】src/services/ai/tools.ts（读工具语义逐条移植）：
 *   - 只读工具 requiresConfirmation=false，仅 run；结果精简后回灌模型。
 *   - requireRealSession 与 RN 同位（天气/洗衣/本地备忘类不设闸门）。
 *
 * 【与参考实现的差异（Harmony 服务能力对齐）】
 *   - 天气：Harmony HomeWeather 字段较少（无小时/多日/建议），按可用字段返回。
 *   - search_news：无 searchNewsList → fetchNewsList 多页拉取 + 客户端
 *     标题关键词/频道过滤。
 *   - read_mail_message：Harmony readMessage 仅按 id 读取（schema 保留
 *     folderName 参数以兼容模型习惯，实际不使用）。
 *   - list_mail_messages：Harmony listMessages(fid, start, limit) /
 *     searchMessages(pattern, start, limit)（start 为 0 基偏移）。
 *   - 今日概览/作业列表/周日程：RN 读本地快照，Harmony 实时调用
 *     CampusDataService（失败/演示模式按空数据兜底，不抛错）。
 *   - 研读间：minReserveTime→minReserveMinute；usage 为 startText/endText
 *     文本（毫秒解析后比较）；记录 begin/end 用 beginFull/endFull。
 *   - 体育：date 直接传 'YYYY-MM-DD'（sportsDateString 同格式）。
 *   - 不注册：get_degree_program_completion / get_full_degree_program /
 *     get_selected_courses（Harmony 无对应服务）、recharge_campus_card /
 *     select_course / drop_course（不可逆/不迁移）。
 * ============================================================================
 */
import { AgentPersonalEvent, AgentToolDef } from '../../domain/AIAgentTypes';
import { ToolRisk } from '../../domain/ActionTypes';
import { ManualDeadline } from '../../domain/DeadlineTypes';
import { SettingsManager } from '../../state/SettingsManager';
import { SessionManager } from '../auth/SessionManager';
import {
  AgentWriteTools, argNumber, argNumberArray, argString, dateChoiceFromArg,
  isoDateForOffset, maskIdentifier, normalizeDateArg, normalizeDateString,
  parseRoomTimeMs, requireRealSession, sameMinuteMs, todayLocalISO, ymdFromIso,
} from './AgentWriteTools';
import {
  CampusCourse, CampusDataService, CampusHomework, CampusNews, CampusNewsDetail,
  ClassroomBuilding, ClassroomPeriod, ClassroomStateResult, ClassroomStatus,
  CLASSROOM_PERIODS, EleRemainder, EleRoomInfo, GradeReport, HomeworkDetailData,
  ScheduleEvent,
} from '../campus/CampusDataService';
import { buildWeatherSubtitle, fetchHomeWeather, HomeWeather } from '../campus/WeatherService';
import { CampusCardInfo, CampusCardService, CampusCardTransaction } from '../campus/CampusCardService';
import { CampusNetworkService, NetworkSnapshot } from '../campus/CampusNetworkService';
import { LaundryBuilding, LaundryBuildingGroup, LaundryFloor, LaundryMachine, LaundryService } from '../campus/LaundryService';
import { SPORTS_VENUES, SportsResourceInfo, SportsService, SportsVenue, sportsDateString } from '../campus/SportsService';
import {
  LibraryBookingRecord, LibrarySeatInfo, LibrarySeatService, seatStatusLabel,
} from '../campus/LibrarySeatService';
import {
  LibRoomBookRecord, LibRoomKind, LibRoomMember, LibRoomResource, LibraryRoomService,
} from '../campus/LibraryRoomService';
import { MailFolder, MailListResult, MailMessageDetail, MailMessageSummary, MailService, MAIL_FOLDERS } from '../campus/MailService';

const LOG_TAG: string = 'AgentTools';
/** 教室查询：每天 6 个大节（与 CLASSROOM_PERIODS/status 数组 7×6 约定绑定） */
const PERIODS_PER_DAY: number = 6;

// ============================================================
// 模块级辅助
// ============================================================

function pad2(n: number): string {
  return n < 10 ? '0' + n : '' + n;
}

/** Record 值安全取串 */
function strVal(v: Object | undefined): string {
  return typeof v === 'string' ? v : '';
}

/** 截止时间文本 → 毫秒（不可解析排最后） */
function deadlineTimeMs(value: string): number {
  const t: number = new Date(value.replace(' ', 'T')).getTime();
  return Number.isNaN(t) ? Number.MAX_SAFE_INTEGER : t;
}

/** 以周一为起点，返回某周（含偏移）7 天的 YYYY-MM-DD（对齐 RN weekDatesContaining） */
function weekDatesContaining(dateISO: string, weekOffset: number): string[] {
  const parts: string[] = dateISO.split('-');
  const anchor: Date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
  const dow: number = anchor.getDay();
  const mondayDelta: number = dow === 0 ? -6 : 1 - dow;
  const monday: Date = new Date(anchor.getFullYear(), anchor.getMonth(), anchor.getDate());
  monday.setDate(anchor.getDate() + mondayDelta + weekOffset * 7);
  const out: string[] = [];
  for (let i: number = 0; i < 7; i++) {
    const cur: Date = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate());
    cur.setDate(monday.getDate() + i);
    out.push(cur.getFullYear() + '-' + pad2(cur.getMonth() + 1) + '-' + pad2(cur.getDate()));
  }
  return out;
}

/** 教室查询：周一=1 … 周日=7 */
function currentClassroomDayIndex(): number {
  const day: number = new Date().getDay();
  return day === 0 ? 7 : day;
}

/** 大节 → 展示结构（period/label/timeRange） */
function describeClassroomPeriod(period: number): Record<string, Object> {
  for (let i: number = 0; i < CLASSROOM_PERIODS.length; i++) {
    const p: ClassroomPeriod = CLASSROOM_PERIODS[i];
    if (p.period === period) {
      return { 'period': p.period, 'label': p.label, 'timeRange': p.timeRange };
    }
  }
  return { 'period': period, 'label': '第' + period + '节', 'timeRange': '' };
}

function emptyParamsJson(): string {
  return '{"type":"object","properties":{}}';
}

// ============================================================
// 天气 / 今日概览 / 作业
// ============================================================

function buildGetCampusWeatherTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'get_campus_weather';
  t.title = '海淀天气';
  t.description = '查询北京市海淀区当前天气、体感温度、降水概率与今日温度区间。当用户问天气、是否带伞、防晒、通勤或受天气影响的学习安排时使用。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"includeHourly":{"type":"boolean","description":"是否返回小时预报（当前数据源暂不提供，保留参数兼容）"}'
    + '}}';
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.weather.read';
  t.summarize = (args: Record<string, Object>): string => '查询海淀天气';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    const w: HomeWeather = await fetchHomeWeather(true);
    const current: Record<string, Object> = {};
    current['temperature'] = w.temperature;
    current['apparentTemperature'] = w.apparent;
    current['condition'] = w.condition;
    current['precipProbability'] = w.precipProbability;
    current['minTemp'] = w.minTemp;
    current['maxTemp'] = w.maxTemp;
    const r: Record<string, Object> = {};
    r['location'] = '北京市海淀区';
    r['updatedAt'] = w.updatedAt;
    r['summary'] = buildWeatherSubtitle(w);
    r['current'] = current;
    return r;
  };
  return t;
}

function buildGetTodayOverviewTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'get_today_overview';
  t.title = '今日概览';
  t.description = '获取今天的日期、星期，以及今天的课程安排和临近的待办作业（DDL）。当用户问"今天/最近有什么安排/作业"时使用。';
  t.parametersJson = emptyParamsJson();
  t.risk = ToolRisk.NONE;
  t.permission = 'learning.overview.read';
  t.summarize = (args: Record<string, Object>): string => '读取今日概览';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    const service: CampusDataService = SessionManager.getCampusDataService();
    const today: string = todayLocalISO();
    const names: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    const weekday: string = names[new Date().getDay()];
    const todayClasses: string[] = [];
    const ddls: string[] = [];
    if (!SettingsManager.isDemoMode()) {
      try {
        const events: ScheduleEvent[] =
          await service.fetchScheduleEvents(ymdFromIso(today), ymdFromIso(today));
        for (let i: number = 0; i < events.length; i++) {
          todayClasses.push(events[i].startTime + '-' + events[i].endTime + ' ' +
            events[i].title + ' @ ' + events[i].location);
        }
      } catch (e) {
        // 课表失败：空列表兜底
      }
      try {
        const courses: CampusCourse[] = await service.fetchCourses();
        const homework: CampusHomework[] = await service.fetchHomework(courses);
        let count: number = 0;
        for (let i: number = 0; i < homework.length && count < 10; i++) {
          if (!homework[i].submitted) {
            ddls.push('[' + homework[i].courseName + '] ' + homework[i].title +
              ' · 截止 ' + homework[i].deadline);
            count++;
          }
        }
      } catch (e) {
        // 作业失败：空列表兜底
      }
    }
    const manual: ManualDeadline[] = await AgentWriteTools.listManualDeadlines();
    const manualDdls: string[] = [];
    for (let i: number = 0; i < manual.length && i < 10; i++) {
      const m: ManualDeadline = manual[i];
      const courseTag: string = m.course.length > 0 ? '自建/' + m.course : '自建';
      const deadlineText: string = m.time.length > 0 ? m.date + ' ' + m.time : m.date;
      manualDdls.push('[' + courseTag + '] ' + m.title + ' · 截止 ' + deadlineText);
    }
    const upcoming: string[] = [];
    for (let i: number = 0; i < ddls.length; i++) {
      upcoming.push(ddls[i]);
    }
    for (let i: number = 0; i < manualDdls.length; i++) {
      upcoming.push(manualDdls[i]);
    }
    const r: Record<string, Object> = {};
    r['date'] = today;
    r['weekday'] = weekday;
    r['todayClasses'] = todayClasses;
    r['upcomingHomework'] = upcoming;
    return r;
  };
  return t;
}

function buildListHomeworkTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'list_homework';
  t.title = '作业列表';
  t.description = '列出作业（合并老师布置的作业与用户自建 DDL）。可按状态筛选：pending=未提交，submitted=已提交未批改，graded=已批改，all=全部。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"status":{"type":"string","enum":["pending","submitted","graded","all"],"description":"筛选状态，默认 pending"}'
    + '}}';
  t.risk = ToolRisk.NONE;
  t.permission = 'learning.homework.read';
  t.summarize = (args: Record<string, Object>): string => '查询作业列表';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    const status: string = argString(args, 'status').length > 0 ? argString(args, 'status') : 'pending';
    const combined: Record<string, Object>[] = [];
    if (!SettingsManager.isDemoMode()) {
      try {
        const service: CampusDataService = SessionManager.getCampusDataService();
        const courses: CampusCourse[] = await service.fetchCourses();
        const homework: CampusHomework[] = await service.fetchHomework(courses);
        for (let i: number = 0; i < homework.length; i++) {
          const h: CampusHomework = homework[i];
          if (status === 'pending' && h.submitted) {
            continue;
          }
          if (status === 'submitted' && !(h.submitted && !h.graded)) {
            continue;
          }
          if (status === 'graded' && !h.graded) {
            continue;
          }
          const item: Record<string, Object> = {};
          item['source'] = 'course';
          item['deletable'] = false;
          item['id'] = h.id;
          item['course'] = h.courseName;
          item['title'] = h.title;
          item['deadline'] = h.deadline;
          item['status'] = h.status;
          item['grade'] = h.grade;
          combined.push(item);
        }
      } catch (e) {
        // 课程/作业失败：仅返回自建 DDL
      }
    }
    if (status !== 'submitted' && status !== 'graded') {
      const manual: ManualDeadline[] = await AgentWriteTools.listManualDeadlines();
      for (let i: number = 0; i < manual.length; i++) {
        const m: ManualDeadline = manual[i];
        const item: Record<string, Object> = {};
        item['source'] = 'manual';
        item['deletable'] = true;
        item['id'] = m.id;
        item['course'] = m.course;
        item['title'] = m.title;
        item['deadline'] = m.time.length > 0 ? m.date + ' ' + m.time : m.date;
        item['status'] = 'pending';
        item['note'] = m.note;
        combined.push(item);
      }
    }
    combined.sort((a: Record<string, Object>, b: Record<string, Object>): number =>
      deadlineTimeMs(strVal(a['deadline'])) - deadlineTimeMs(strVal(b['deadline'])));
    const top: Object[] = [];
    const n: number = combined.length < 30 ? combined.length : 30;
    for (let i: number = 0; i < n; i++) {
      top.push(combined[i]);
    }
    const r: Record<string, Object> = {};
    r['count'] = combined.length;
    r['homework'] = top;
    return r;
  };
  return t;
}

function buildGetHomeworkDetailTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'get_homework_detail';
  t.title = '作业详情';
  t.description = '获取某条作业的完整详情（作业说明、提交内容、批阅结果、附件名）。通过作业标题关键词或 list_homework 返回的 id 定位。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"titleOrId":{"type":"string","description":"作业标题关键词或作业 id"}'
    + '},"required":["titleOrId"]}';
  t.risk = ToolRisk.NONE;
  t.permission = 'learning.homework.read';
  t.summarize = (args: Record<string, Object>): string => '读取作业详情：' + argString(args, 'titleOrId');
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const service: CampusDataService = SessionManager.getCampusDataService();
    const key: string = argString(args, 'titleOrId').trim();
    const courses: CampusCourse[] = await service.fetchCourses();
    const homework: CampusHomework[] = await service.fetchHomework(courses);
    let item: CampusHomework | undefined = undefined;
    for (let i: number = 0; i < homework.length; i++) {
      if (homework[i].id === key) {
        item = homework[i];
        break;
      }
    }
    if (item === undefined) {
      for (let i: number = 0; i < homework.length; i++) {
        if (homework[i].title.includes(key)) {
          item = homework[i];
          break;
        }
      }
    }
    if (item === undefined) {
      return { 'error': '未找到匹配的作业：' + key };
    }
    const detail: HomeworkDetailData = await service.fetchHomeworkDetail(item.url);
    const r: Record<string, Object> = {};
    r['id'] = item.id;
    r['title'] = item.title;
    r['course'] = item.courseName;
    r['deadline'] = item.deadline;
    r['description'] = detail.description;
    r['answerContent'] = detail.answerContent;
    r['attachments'] = detail.attachments;
    r['grade'] = item.grade;
    r['gradeContent'] = item.gradeContent;
    return r;
  };
  return t;
}

// ============================================================
// 成绩 / 电费
// ============================================================

function buildGetGradesTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'get_grades';
  t.title = '成绩查询';
  t.description = '查询本人成绩单与学分绩（GPA）。返回各门课成绩与总体 GPA。';
  t.parametersJson = emptyParamsJson();
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.grades.read';
  t.summarize = (args: Record<string, Object>): string => '查询成绩与 GPA';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const service: CampusDataService = SessionManager.getCampusDataService();
    const report: GradeReport = await service.fetchGrades();
    const courses: Object[] = [];
    const n: number = report.courses.length < 60 ? report.courses.length : 60;
    for (let i: number = 0; i < n; i++) {
      const c = report.courses[i];
      const item: Record<string, Object> = {};
      item['name'] = c.name;
      item['credit'] = c.credit;
      item['grade'] = c.grade;
      item['point'] = c.point;
      item['semester'] = c.semester;
      courses.push(item);
    }
    const r: Record<string, Object> = {};
    r['gpa'] = Math.round(report.gpa * 1000) / 1000;
    r['totalCredit'] = report.totalCredit;
    r['courses'] = courses;
    return r;
  };
  return t;
}

function buildGetElectricityTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'get_electricity_balance';
  t.title = '电费余额';
  t.description = '查询宿舍当前电费剩余电量、更新时间与房间信息。';
  t.parametersJson = emptyParamsJson();
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.electricity.read';
  t.summarize = (args: Record<string, Object>): string => '查询电费余额';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const service: CampusDataService = SessionManager.getCampusDataService();
    const balance: EleRemainder = await service.getEleRemainder();
    let room: EleRoomInfo | undefined = undefined;
    try {
      room = await service.getEleRoomInfo();
    } catch (e) {
      room = undefined;
    }
    const r: Record<string, Object> = {};
    r['remainder'] = balance.remainder;
    r['unit'] = '度';
    r['updateTime'] = balance.updateTime;
    if (room !== undefined) {
      const roomRec: Record<string, Object> = {};
      roomRec['building'] = room.building;
      roomRec['room'] = room.room;
      roomRec['userName'] = room.userName;
      r['room'] = roomRec;
    }
    return r;
  };
  return t;
}

// ============================================================
// 洗衣 / 校园卡
// ============================================================

function buildListLaundryBuildingsTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'list_laundry_buildings';
  t.title = '洗衣机楼宇列表';
  t.description = '列出可查询洗衣机状态的宿舍楼/位置。用户问哪里能查洗衣机、要选择楼栋、或未说明具体楼栋时使用。';
  t.parametersJson = emptyParamsJson();
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.laundry.read';
  t.summarize = (args: Record<string, Object>): string => '查询洗衣机楼宇列表';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    const laundry: LaundryService = SessionManager.getLaundryService();
    const groups: LaundryBuildingGroup[] = await laundry.getLaundryBuildings();
    const groupArr: Object[] = [];
    for (let i: number = 0; i < groups.length; i++) {
      const g: LaundryBuildingGroup = groups[i];
      const buildings: Object[] = [];
      for (let j: number = 0; j < g.buildings.length; j++) {
        const b: LaundryBuilding = g.buildings[j];
        const item: Record<string, Object> = {};
        item['id'] = b.id;
        item['name'] = b.name;
        item['platform'] = b.platform;
        buildings.push(item);
      }
      const rec: Record<string, Object> = {};
      rec['name'] = g.name;
      rec['buildings'] = buildings;
      groupArr.push(rec);
    }
    return { 'groups': groupArr };
  };
  return t;
}

function buildGetLaundryStatusTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'get_laundry_status';
  t.title = '洗衣机状态';
  t.description = '查询某个宿舍楼/位置的洗衣机、洗鞋机、烘干机实时状态。需要 buildingId、buildingName、platform，优先来自 list_laundry_buildings 返回值。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"buildingId":{"type":"string","description":"list_laundry_buildings 返回的楼宇 id"},'
    + '"buildingName":{"type":"string","description":"楼宇/位置名称，用于展示和来源确认"},'
    + '"platform":{"type":"string","enum":["jieli","haile"],"description":"洗衣平台，来自 list_laundry_buildings 返回值"}'
    + '},"required":["buildingId","buildingName","platform"]}';
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.laundry.read';
  t.summarize = (args: Record<string, Object>): string => '查询洗衣机状态 ' + argString(args, 'buildingName');
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    const laundry: LaundryService = SessionManager.getLaundryService();
    const building: LaundryBuilding = new LaundryBuilding();
    building.id = argString(args, 'buildingId');
    building.name = argString(args, 'buildingName');
    building.platform = argString(args, 'platform') === 'haile' ? 'haile' : 'jieli';
    const floors: LaundryFloor[] = await laundry.getLaundryFloors(building);
    let total: number = 0;
    let idle: number = 0;
    let working: number = 0;
    let errorCount: number = 0;
    const floorArr: Object[] = [];
    for (let i: number = 0; i < floors.length; i++) {
      const floor: LaundryFloor = floors[i];
      const machines: Object[] = [];
      for (let j: number = 0; j < floor.machines.length; j++) {
        const m: LaundryMachine = floor.machines[j];
        total++;
        if (m.status === 'idle') {
          idle++;
        } else if (m.status === 'working') {
          working++;
        } else {
          errorCount++;
        }
        const item: Record<string, Object> = {};
        item['name'] = m.name;
        item['label'] = m.location.length > 0 ? m.location + ' ' + m.type : m.name + ' ' + m.type;
        item['type'] = m.type;
        item['status'] = m.status;
        item['etaMinutes'] = m.etaMinutes;
        item['updatedAt'] = m.updatedAt;
        machines.push(item);
      }
      const rec: Record<string, Object> = {};
      rec['name'] = floor.name;
      rec['machines'] = machines;
      floorArr.push(rec);
    }
    const summary: Record<string, Object> = {};
    summary['total'] = total;
    summary['idle'] = idle;
    summary['working'] = working;
    summary['error'] = errorCount;
    const buildingRec: Record<string, Object> = {};
    buildingRec['id'] = building.id;
    buildingRec['name'] = building.name;
    buildingRec['platform'] = building.platform;
    const r: Record<string, Object> = {};
    r['building'] = buildingRec;
    r['summary'] = summary;
    r['floors'] = floorArr;
    return r;
  };
  return t;
}

function buildGetCampusCardBalanceTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'get_campus_card_balance';
  t.title = '校园卡余额';
  t.description = '查询校园卡余额、卡状态和最近交易时间。只读，不执行充值、挂失或密码类动作。';
  t.parametersJson = emptyParamsJson();
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.card.read';
  t.summarize = (args: Record<string, Object>): string => '查询校园卡余额';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const card: CampusCardService = SessionManager.getCampusCardService();
    const info: CampusCardInfo = await card.getCampusCardInfo();
    const r: Record<string, Object> = {};
    r['balance'] = info.balance;
    r['unit'] = '元';
    r['cardStatus'] = info.cardStatus;
    r['departmentName'] = info.departmentName;
    r['userName'] = info.userName;
    r['cardId'] = maskIdentifier(info.cardId);
    r['lastTransactionTimestamp'] = info.lastTransactionTimestamp;
    return r;
  };
  return t;
}

function buildGetCampusCardTransactionsTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'get_campus_card_transactions';
  t.title = '校园卡流水';
  t.description = '查询校园卡近期流水。start/end 为 YYYY-MM-DD；type 可选 any/consumption/recharge/subsidy。结果会限制条数。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"start":{"type":"string","description":"起始日期 YYYY-MM-DD，默认 7 天前"},'
    + '"end":{"type":"string","description":"结束日期 YYYY-MM-DD，默认今天"},'
    + '"type":{"type":"string","enum":["any","consumption","recharge","subsidy"],"description":"流水类型，默认 any"}'
    + '}}';
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.card.transactions.read';
  t.summarize = (args: Record<string, Object>): string => '查询校园卡流水';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const card: CampusCardService = SessionManager.getCampusCardService();
    const typeArg: string = argString(args, 'type');
    let typeNum: number = -1;
    if (typeArg === 'consumption') {
      typeNum = 1;
    } else if (typeArg === 'recharge') {
      typeNum = 2;
    } else if (typeArg === 'subsidy') {
      typeNum = 3;
    }
    const end: string = normalizeDateArg(argString(args, 'end'), 0);
    const startArg: string = argString(args, 'start');
    const start: string = startArg.length > 0 ? normalizeDateArg(startArg, 0) : isoDateForOffset(-7);
    const rows: CampusCardTransaction[] = await card.getCampusCardTransactions(start, end, typeNum);
    const txArr: Object[] = [];
    const n: number = rows.length < 30 ? rows.length : 30;
    for (let i: number = 0; i < n; i++) {
      const item: CampusCardTransaction = rows[i];
      const rec: Record<string, Object> = {};
      rec['summary'] = item.summary;
      rec['timestamp'] = item.timestamp;
      rec['amount'] = item.amount;
      rec['balance'] = item.balance;
      rec['merchant'] = item.name;
      rec['address'] = item.address;
      rec['txName'] = item.txName;
      txArr.push(rec);
    }
    const r: Record<string, Object> = {};
    r['start'] = start;
    r['end'] = end;
    r['count'] = rows.length;
    r['transactions'] = txArr;
    return r;
  };
  return t;
}

// ============================================================
// 校园网
// ============================================================

function buildGetNetworkBalanceTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'get_network_balance';
  t.title = '校园网余额';
  t.description = '查询校园网套餐、已用流量/时长、账户余额和结算日期。';
  t.parametersJson = emptyParamsJson();
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.network.read';
  t.summarize = (args: Record<string, Object>): string => '查询校园网余额';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const network: CampusNetworkService = SessionManager.getNetworkService();
    const snapshot: NetworkSnapshot = await network.getNetworkSnapshot();
    const r: Record<string, Object> = {};
    r['productName'] = snapshot.balance.productName;
    r['usedBytes'] = snapshot.balance.usedBytes;
    r['usedSeconds'] = snapshot.balance.usedSeconds;
    r['accountBalance'] = snapshot.balance.accountBalance;
    r['settlementDate'] = snapshot.balance.settlementDate;
    return r;
  };
  return t;
}

function buildGetNetworkAccountInfoTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'get_network_account_info';
  t.title = '校园网账号信息';
  t.description = '查询校园网账号状态、用户组、允许在线设备数等信息。手机号和邮箱会脱敏。';
  t.parametersJson = emptyParamsJson();
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.network.read';
  t.summarize = (args: Record<string, Object>): string => '查询校园网账号信息';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const network: CampusNetworkService = SessionManager.getNetworkService();
    const snapshot: NetworkSnapshot = await network.getNetworkSnapshot();
    const info = snapshot.account;
    const r: Record<string, Object> = {};
    r['username'] = maskIdentifier(info.username);
    r['realName'] = info.realName;
    r['status'] = info.status;
    r['userGroup'] = info.userGroup;
    r['location'] = info.location;
    r['allowedDevices'] = info.allowedDevices;
    r['contactEmail'] = maskIdentifier(info.contactEmail);
    r['contactPhone'] = maskIdentifier(info.contactPhone);
    r['contactLandline'] = maskIdentifier(info.contactLandline);
    return r;
  };
  return t;
}

function buildListNetworkDevicesTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'list_network_devices';
  t.title = '校园网在线设备';
  t.description = '列出当前校园网在线设备。返回的 key 可用于 logout_network_device，IP/MAC 展示时会脱敏。';
  t.parametersJson = emptyParamsJson();
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.network.devices.read';
  t.summarize = (args: Record<string, Object>): string => '查询校园网在线设备';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const network: CampusNetworkService = SessionManager.getNetworkService();
    const snapshot: NetworkSnapshot = await network.getNetworkSnapshot();
    const devices: Object[] = [];
    const n: number = snapshot.devices.length < 20 ? snapshot.devices.length : 20;
    for (let i: number = 0; i < n; i++) {
      const d = snapshot.devices[i];
      const rec: Record<string, Object> = {};
      rec['key'] = d.key;
      rec['ip4'] = maskIdentifier(d.ip4);
      rec['ip6'] = maskIdentifier(d.ip6);
      rec['loggedAt'] = d.loggedAt;
      rec['mac'] = maskIdentifier(d.mac);
      rec['authPermission'] = d.authPermission;
      devices.push(rec);
    }
    const r: Record<string, Object> = {};
    r['count'] = snapshot.devices.length;
    r['devices'] = devices;
    return r;
  };
  return t;
}

// ============================================================
// 体育
// ============================================================

function buildListSportsVenuesTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'list_sports_venues';
  t.title = '体育场馆列表';
  t.description = '列出已接入的体育场馆项目，用于后续查询场地空闲时段。';
  t.parametersJson = emptyParamsJson();
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.sports.read';
  t.summarize = (args: Record<string, Object>): string => '查询体育场馆列表';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    const venues: Object[] = [];
    for (let i: number = 0; i < SPORTS_VENUES.length; i++) {
      const v: SportsVenue = SPORTS_VENUES[i];
      const rec: Record<string, Object> = {};
      rec['name'] = v.name;
      rec['gymId'] = v.gymId;
      rec['itemId'] = v.itemId;
      venues.push(rec);
    }
    return { 'venues': venues };
  };
  return t;
}

function buildSearchSportsSlotsTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'search_sports_slots';
  t.title = '体育场地空闲查询';
  t.description = '查询某体育项目某天可预约场地。可用 venueName 模糊匹配，或直接传 gymId/itemId。只查询，不预约、不支付。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"venueName":{"type":"string","description":"项目名，如 气膜馆羽毛球场"},'
    + '"gymId":{"type":"string"},'
    + '"itemId":{"type":"string"},'
    + '"date":{"type":"string","description":"YYYY-MM-DD，默认今天"}'
    + '}}';
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.sports.read';
  t.summarize = (args: Record<string, Object>): string => '查询体育场地：' + argString(args, 'venueName');
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const sports: SportsService = SessionManager.getSportsService();
    const keyword: string = argString(args, 'venueName').trim();
    const gymIdArg: string = argString(args, 'gymId');
    const itemIdArg: string = argString(args, 'itemId');
    let venue: SportsVenue | undefined = undefined;
    if (gymIdArg.length > 0 && itemIdArg.length > 0) {
      venue = new SportsVenue();
      venue.name = keyword.length > 0 ? keyword : '指定场馆';
      venue.gymId = gymIdArg;
      venue.itemId = itemIdArg;
    } else {
      for (let i: number = 0; i < SPORTS_VENUES.length; i++) {
        if (SPORTS_VENUES[i].name.includes(keyword)) {
          venue = SPORTS_VENUES[i];
          break;
        }
      }
      if (venue === undefined) {
        for (let i: number = 0; i < SPORTS_VENUES.length; i++) {
          if (keyword.includes(SPORTS_VENUES[i].name)) {
            venue = SPORTS_VENUES[i];
            break;
          }
        }
      }
    }
    if (venue === undefined) {
      const names: Object[] = [];
      for (let i: number = 0; i < SPORTS_VENUES.length; i++) {
        names.push(SPORTS_VENUES[i].name);
      }
      return { 'error': '未找到体育项目：' + keyword, 'availableVenues': names };
    }
    const dateArg: string = argString(args, 'date');
    const date: string = dateArg.length > 0 ? normalizeDateArg(dateArg, 0) : sportsDateString(0);
    const info: SportsResourceInfo = await sports.getSportsResources(venue, date);
    const slots: Object[] = [];
    for (let i: number = 0; i < info.data.length && slots.length < 40; i++) {
      const item = info.data[i];
      if (!item.canNetBook || item.locked) {
        continue;
      }
      const rec: Record<string, Object> = {};
      rec['resId'] = item.resId;
      rec['timeSession'] = item.timeSession;
      rec['fieldName'] = item.fieldName;
      rec['cost'] = item.cost;
      rec['overlaySize'] = item.overlaySize;
      slots.push(rec);
    }
    const limit: Record<string, Object> = {};
    limit['count'] = info.count;
    limit['init'] = info.init;
    const r: Record<string, Object> = {};
    r['venue'] = venue.name;
    r['date'] = date;
    r['limit'] = limit;
    r['availableCount'] = slots.length;
    r['slots'] = slots;
    return r;
  };
  return t;
}

function buildListSportsReservationRecordsTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'list_sports_reservation_records';
  t.title = '体育预约记录';
  t.description = '查询当前账号的体育场馆预约/订单记录。只读，不执行取消或支付。';
  t.parametersJson = emptyParamsJson();
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.sports.reservation.read';
  t.summarize = (args: Record<string, Object>): string => '查询体育预约记录';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const sports: SportsService = SessionManager.getSportsService();
    const records = await sports.getSportsRecords();
    const arr: Object[] = [];
    const n: number = records.length < 20 ? records.length : 20;
    for (let i: number = 0; i < n; i++) {
      const item = records[i];
      const rec: Record<string, Object> = {};
      rec['name'] = item.name;
      rec['field'] = item.field;
      rec['time'] = item.time;
      rec['price'] = item.price;
      rec['method'] = item.method;
      rec['canCancel'] = item.bookId.length > 0;
      rec['hasPaymentAction'] = item.payId.length > 0;
      arr.push(rec);
    }
    const r: Record<string, Object> = {};
    r['count'] = records.length;
    r['records'] = arr;
    return r;
  };
  return t;
}

// ============================================================
// 空教室
// ============================================================

function buildListClassroomBuildingsTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'list_classroom_buildings';
  t.title = '教学楼列表';
  t.description = '列出可查询空教室状态的教学楼。用户想找空教室但没指定楼宇时，先调用此工具。';
  t.parametersJson = emptyParamsJson();
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.classroom.read';
  t.summarize = (args: Record<string, Object>): string => '查询教学楼列表';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const service: CampusDataService = SessionManager.getCampusDataService();
    const buildings: ClassroomBuilding[] = await service.fetchClassroomList();
    const arr: Object[] = [];
    for (let i: number = 0; i < buildings.length; i++) {
      const rec: Record<string, Object> = {};
      rec['name'] = buildings[i].name;
      rec['currentWeekNumber'] = buildings[i].weekNumber;
      arr.push(rec);
    }
    return { 'buildings': arr };
  };
  return t;
}

function buildFindAvailableClassroomsTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'find_available_classrooms';
  t.title = '查找空教室';
  t.description = '查询某教学楼的空教室。dayIndex 为周一=1 到周日=7；periods 为 6 个大节（1=08:00-09:35，2=09:50-12:15，3=13:30-15:05，4=15:20-16:55，5=17:10-18:45，6=19:20-21:45）。不传 dayIndex 默认今天，不传 periods 返回全天空闲节次数汇总。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"buildingName":{"type":"string","description":"教学楼名称，如 六教"},'
    + '"weekNumber":{"type":"number","description":"教学周，不传则使用教务系统当前周"},'
    + '"dayIndex":{"type":"number","description":"周一=1 到周日=7，默认今天"},'
    + '"periods":{"type":"array","items":{"type":"number"},"description":"大节数组，1-6；例如下午 13:30-16:55 可传 [3,4]"}'
    + '},"required":["buildingName"]}';
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.classroom.read';
  t.summarize = (args: Record<string, Object>): string => '查找空教室：' + argString(args, 'buildingName');
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const service: CampusDataService = SessionManager.getCampusDataService();
    const buildings: ClassroomBuilding[] = await service.fetchClassroomList();
    const keyword: string = argString(args, 'buildingName').trim();
    let building: ClassroomBuilding | undefined = undefined;
    for (let i: number = 0; i < buildings.length; i++) {
      if (buildings[i].name === keyword) {
        building = buildings[i];
        break;
      }
    }
    if (building === undefined) {
      for (let i: number = 0; i < buildings.length; i++) {
        if (buildings[i].name.includes(keyword) || keyword.includes(buildings[i].name)) {
          building = buildings[i];
          break;
        }
      }
    }
    if (building === undefined) {
      const names: Object[] = [];
      for (let i: number = 0; i < buildings.length; i++) {
        names.push(buildings[i].name);
      }
      return { 'error': '未找到教学楼：' + keyword, 'availableBuildings': names };
    }
    const weekNumberArg: number = argNumber(args, 'weekNumber');
    const weekNumber: number = Number.isNaN(weekNumberArg) ? building.weekNumber : weekNumberArg;
    const state: ClassroomStateResult = await service.fetchClassroomState(building.searchName, weekNumber);
    const dayIndexArg: number = argNumber(args, 'dayIndex');
    let dayIndex: number = Number.isNaN(dayIndexArg) ? currentClassroomDayIndex() : dayIndexArg;
    dayIndex = dayIndex < 1 ? 1 : (dayIndex > 7 ? 7 : dayIndex);
    const requestedPeriods: number[] = [];
    const rawPeriods: number[] = argNumberArray(args, 'periods');
    for (let i: number = 0; i < rawPeriods.length; i++) {
      const p: number = rawPeriods[i];
      if (Number.isInteger(p) && p >= 1 && p <= PERIODS_PER_DAY) {
        requestedPeriods.push(p);
      }
    }
    const start: number = (dayIndex - 1) * PERIODS_PER_DAY;
    const slots: number[] = [];
    if (requestedPeriods.length > 0) {
      for (let i: number = 0; i < requestedPeriods.length; i++) {
        slots.push(start + requestedPeriods[i] - 1);
      }
    } else {
      for (let i: number = 0; i < PERIODS_PER_DAY; i++) {
        slots.push(start + i);
      }
    }
    const available: Object[] = [];
    for (let i: number = 0; i < state.classroomStates.length && available.length < 40; i++) {
      const room = state.classroomStates[i];
      const freePeriods: number[] = [];
      for (let j: number = 0; j < slots.length; j++) {
        const slot: number = slots[j];
        const period: number = (slot % PERIODS_PER_DAY) + 1;
        if (room.status[slot] === ClassroomStatus.AVAILABLE) {
          freePeriods.push(period);
        }
      }
      const availableForRequestedRange: boolean =
        requestedPeriods.length > 0 && freePeriods.length === requestedPeriods.length;
      if (requestedPeriods.length > 0 ? !availableForRequestedRange : freePeriods.length === 0) {
        continue;
      }
      const freePeriodDetails: Object[] = [];
      for (let j: number = 0; j < freePeriods.length; j++) {
        freePeriodDetails.push(describeClassroomPeriod(freePeriods[j]));
      }
      const rec: Record<string, Object> = {};
      rec['name'] = room.name;
      rec['freePeriods'] = freePeriods;
      rec['freePeriodDetails'] = freePeriodDetails;
      rec['availableForRequestedRange'] = availableForRequestedRange;
      available.push(rec);
    }
    const periodDefinitions: Object[] = [];
    for (let i: number = 0; i < CLASSROOM_PERIODS.length; i++) {
      periodDefinitions.push(describeClassroomPeriod(CLASSROOM_PERIODS[i].period));
    }
    const requestedOut: Object = requestedPeriods.length > 0 ? requestedPeriods : '全天 1-6 大节';
    const r: Record<string, Object> = {};
    r['building'] = building.name;
    r['weekNumber'] = state.currentWeekNumber;
    r['dayIndex'] = dayIndex;
    r['date'] = dayIndex - 1 < state.datesOfCurrentWeek.length ? state.datesOfCurrentWeek[dayIndex - 1] : '';
    r['periodDefinitions'] = periodDefinitions;
    r['requestedPeriods'] = requestedOut;
    r['count'] = available.length;
    r['classrooms'] = available;
    return r;
  };
  return t;
}

// ============================================================
// 图书馆座位（只读链路）
// ============================================================

function buildListLibrariesTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'list_libraries';
  t.title = '图书馆列表';
  t.description = '列出可预约座位的图书馆及其有效性。预约座位的第一步。';
  t.parametersJson = emptyParamsJson();
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.library.read';
  t.summarize = (args: Record<string, Object>): string => '获取图书馆列表';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const seatService: LibrarySeatService = SessionManager.getLibrarySeatService();
    const list = await seatService.getLibraryList();
    const arr: Object[] = [];
    for (let i: number = 0; i < list.length; i++) {
      if (!list[i].valid) {
        continue;
      }
      const rec: Record<string, Object> = {};
      rec['id'] = list[i].id;
      rec['name'] = list[i].zhName;
      arr.push(rec);
    }
    return { 'libraries': arr };
  };
  return t;
}

function buildListFloorsTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'list_library_floors';
  t.title = '图书馆楼层空位';
  t.description = '列出某图书馆各楼层及其空位数（available/total）。需先用 list_libraries 拿到 libraryId。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"libraryId":{"type":"number","description":"图书馆 id"},'
    + '"date":{"type":"string","enum":["today","tomorrow"],"description":"默认 today"}'
    + '},"required":["libraryId"]}';
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.library.read';
  t.summarize = (args: Record<string, Object>): string => '查询楼层空位';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const seatService: LibrarySeatService = SessionManager.getLibrarySeatService();
    const libraryId: number = argNumber(args, 'libraryId');
    if (Number.isNaN(libraryId)) {
      return { 'error': '缺少图书馆 libraryId' };
    }
    const floors = await seatService.getLibraryFloorList(libraryId, dateChoiceFromArg(args['date']));
    const arr: Object[] = [];
    for (let i: number = 0; i < floors.length; i++) {
      if (!floors[i].valid) {
        continue;
      }
      const rec: Record<string, Object> = {};
      rec['id'] = floors[i].id;
      rec['name'] = floors[i].zhName;
      rec['available'] = floors[i].available;
      rec['total'] = floors[i].total;
      arr.push(rec);
    }
    return { 'floors': arr };
  };
  return t;
}

function buildListSectionsTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'list_library_sections';
  t.title = '图书馆分区空位';
  t.description = '列出某楼层下各分区及空位数。需先用 list_library_floors 拿到 floorId。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"floorId":{"type":"number","description":"楼层 id"},'
    + '"date":{"type":"string","enum":["today","tomorrow"]}'
    + '},"required":["floorId"]}';
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.library.read';
  t.summarize = (args: Record<string, Object>): string => '查询分区空位';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const seatService: LibrarySeatService = SessionManager.getLibrarySeatService();
    const floorId: number = argNumber(args, 'floorId');
    if (Number.isNaN(floorId)) {
      return { 'error': '缺少楼层 floorId' };
    }
    const sections = await seatService.getLibrarySectionList(floorId, dateChoiceFromArg(args['date']));
    const arr: Object[] = [];
    for (let i: number = 0; i < sections.length; i++) {
      if (!sections[i].valid) {
        continue;
      }
      const rec: Record<string, Object> = {};
      rec['id'] = sections[i].id;
      rec['name'] = sections[i].zhName;
      rec['available'] = sections[i].available;
      rec['total'] = sections[i].total;
      arr.push(rec);
    }
    return { 'sections': arr };
  };
  return t;
}

function buildFindSeatsTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'find_available_seats';
  t.title = '可用座位查询';
  t.description = '列出某分区当前可预约的座位（仅返回可用座位）。需先用 list_library_sections 拿到 sectionId。返回的 seatId + seatType 用于 book_library_seat。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"sectionId":{"type":"number","description":"分区 id"},'
    + '"date":{"type":"string","enum":["today","tomorrow"]}'
    + '},"required":["sectionId"]}';
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.library.read';
  t.summarize = (args: Record<string, Object>): string => '查找可用座位';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const seatService: LibrarySeatService = SessionManager.getLibrarySeatService();
    const sectionId: number = argNumber(args, 'sectionId');
    if (Number.isNaN(sectionId)) {
      return { 'error': '缺少分区 sectionId' };
    }
    const seats: LibrarySeatInfo[] =
      await seatService.getLibrarySeatList(sectionId, dateChoiceFromArg(args['date']));
    const arr: Object[] = [];
    for (let i: number = 0; i < seats.length; i++) {
      if (seats[i].status !== 1) {
        continue;
      }
      const rec: Record<string, Object> = {};
      rec['seatId'] = seats[i].id;
      rec['seatName'] = seats[i].name;
      rec['seatType'] = seats[i].type;
      rec['status'] = seatStatusLabel(seats[i].status);
      arr.push(rec);
    }
    const r: Record<string, Object> = {};
    r['availableCount'] = arr.length;
    r['seats'] = arr;
    return r;
  };
  return t;
}

function buildListLibraryBookingRecordsTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'list_library_booking_records';
  t.title = '图书馆预约记录';
  t.description = '查询当前账号的图书馆座位预约记录。用户问"我预约了哪个座位/我的图书馆预约/能不能取消预约"时使用。取消预约用记录里的 cancelId。';
  t.parametersJson = emptyParamsJson();
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.library.booking.read';
  t.summarize = (args: Record<string, Object>): string => '查询图书馆预约记录';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const seatService: LibrarySeatService = SessionManager.getLibrarySeatService();
    const records: LibraryBookingRecord[] = await seatService.getLibraryBookingRecords();
    const arr: Object[] = [];
    const n: number = records.length < 20 ? records.length : 20;
    for (let i: number = 0; i < n; i++) {
      const rec: Record<string, Object> = {};
      rec['id'] = records[i].id;
      rec['pos'] = records[i].pos;
      rec['time'] = records[i].time;
      rec['status'] = records[i].status;
      rec['cancelId'] = records[i].cancelId;
      arr.push(rec);
    }
    const r: Record<string, Object> = {};
    r['count'] = records.length;
    r['records'] = arr;
    return r;
  };
  return t;
}

// ============================================================
// 研读间（只读链路）
// ============================================================

function buildListLibraryRoomTypesTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'list_library_room_types';
  t.title = '研读间类型列表';
  t.description = '列出可预约研读间类型及房间。查找或预约研读间前先调用它获取 kindId。';
  t.parametersJson = emptyParamsJson();
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.library.room.read';
  t.summarize = (args: Record<string, Object>): string => '查询研读间类型';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const roomService: LibraryRoomService = SessionManager.getLibraryRoomService();
    const kinds: LibRoomKind[] = await roomService.getRoomKindList();
    const arr: Object[] = [];
    for (let i: number = 0; i < kinds.length; i++) {
      const kind: LibRoomKind = kinds[i];
      const rooms: Object[] = [];
      const n: number = kind.rooms.length < 30 ? kind.rooms.length : 30;
      for (let j: number = 0; j < n; j++) {
        const roomRec: Record<string, Object> = {};
        roomRec['devId'] = kind.rooms[j].devId;
        roomRec['devName'] = kind.rooms[j].devName;
        roomRec['minReserveMinute'] = kind.rooms[j].minReserveMinute;
        rooms.push(roomRec);
      }
      const rec: Record<string, Object> = {};
      rec['kindId'] = kind.kindId;
      rec['kindName'] = kind.kindName;
      rec['rooms'] = rooms;
      arr.push(rec);
    }
    return { 'types': arr };
  };
  return t;
}

function buildFindLibraryRoomsTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'find_library_rooms';
  t.title = '查找可用研读间';
  t.description = '查询某天某类型研读间资源。date 支持 today/tomorrow/YYYY-MM-DD；传 startTime/endTime 时会过滤出该时段可用房间。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"kindId":{"type":"number","description":"研读间类型 id"},'
    + '"kindName":{"type":"string","description":"类型名关键词，如 研讨间"},'
    + '"date":{"type":"string","description":"today/tomorrow/YYYY-MM-DD，默认今天"},'
    + '"startTime":{"type":"string","description":"HH:mm，可选"},'
    + '"endTime":{"type":"string","description":"HH:mm，可选"}'
    + '}}';
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.library.room.read';
  t.summarize = (args: Record<string, Object>): string => '查找可用研读间';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const roomService: LibraryRoomService = SessionManager.getLibraryRoomService();
    const date: string = normalizeDateArg(argString(args, 'date'), 0);
    const kinds: LibRoomKind[] = await roomService.getRoomKindList();
    const kindIdArg: number = argNumber(args, 'kindId');
    const kindName: string = argString(args, 'kindName').trim();
    let kind: LibRoomKind | undefined = undefined;
    if (!Number.isNaN(kindIdArg)) {
      for (let i: number = 0; i < kinds.length; i++) {
        if (kinds[i].kindId === kindIdArg) {
          kind = kinds[i];
          break;
        }
      }
    } else {
      for (let i: number = 0; i < kinds.length; i++) {
        if (kinds[i].kindName.includes(kindName)) {
          kind = kinds[i];
          break;
        }
      }
    }
    if (kind === undefined) {
      const availableTypes: Object[] = [];
      for (let i: number = 0; i < kinds.length; i++) {
        const rec: Record<string, Object> = {};
        rec['kindId'] = kinds[i].kindId;
        rec['kindName'] = kinds[i].kindName;
        availableTypes.push(rec);
      }
      return { 'error': '未找到研读间类型', 'availableTypes': availableTypes };
    }
    const resources: LibRoomResource[] =
      await roomService.getRoomResourceList(ymdFromIso(date), kind.kindId);
    const startTime: string = argString(args, 'startTime');
    const endTime: string = argString(args, 'endTime');
    const hasRange: boolean = startTime.length > 0 && endTime.length > 0;
    const startMs: number = hasRange ? parseRoomTimeMs(date + ' ' + startTime) : Number.NaN;
    const endMs: number = hasRange ? parseRoomTimeMs(date + ' ' + endTime) : Number.NaN;
    const rooms: Object[] = [];
    for (let i: number = 0; i < resources.length && rooms.length < 40; i++) {
      const room: LibRoomResource = resources[i];
      if (hasRange) {
        const openStartText: string = room.openStart.length >= 5 ? room.openStart.substring(0, 5) : room.openStart;
        const openEndText: string = room.openEnd.length >= 5 ? room.openEnd.substring(0, 5) : room.openEnd;
        if (openStartText.length > 0 && startTime < openStartText) {
          continue;
        }
        if (openEndText.length > 0 && endTime > openEndText) {
          continue;
        }
        let overlapped: boolean = false;
        for (let j: number = 0; j < room.usageList.length; j++) {
          const usage = room.usageList[j];
          const usageStartMs: number = parseRoomTimeMs(usage.startText);
          const usageEndMs: number = parseRoomTimeMs(usage.endText);
          if (!Number.isNaN(usageStartMs) && !Number.isNaN(usageEndMs)
            && !Number.isNaN(startMs) && !Number.isNaN(endMs)
            && startMs < usageEndMs && usageStartMs < endMs) {
            overlapped = true;
            break;
          }
        }
        if (overlapped) {
          continue;
        }
      }
      const occupied: Object[] = [];
      const n: number = room.usageList.length < 8 ? room.usageList.length : 8;
      for (let j: number = 0; j < n; j++) {
        const usage = room.usageList[j];
        const usageRec: Record<string, Object> = {};
        usageRec['start'] = usage.startText;
        usageRec['end'] = usage.endText;
        usageRec['title'] = usage.title;
        usageRec['owner'] = usage.owner;
        occupied.push(usageRec);
      }
      const rec: Record<string, Object> = {};
      rec['devId'] = room.devId;
      rec['devName'] = room.devName;
      rec['kindId'] = room.kindId;
      rec['kindName'] = room.kindName;
      rec['labName'] = room.labName;
      rec['roomName'] = room.roomName;
      rec['minMinute'] = room.minMinute;
      rec['maxMinute'] = room.maxMinute;
      rec['minUser'] = room.minUser;
      rec['maxUser'] = room.maxUser;
      rec['openStart'] = room.openStart;
      rec['openEnd'] = room.openEnd;
      rec['occupied'] = occupied;
      rooms.push(rec);
    }
    const r: Record<string, Object> = {};
    r['date'] = date;
    r['kindId'] = kind.kindId;
    r['kindName'] = kind.kindName;
    r['requestedRange'] = hasRange ? startTime + '-' + endTime : '未指定时段';
    r['count'] = rooms.length;
    r['rooms'] = rooms;
    return r;
  };
  return t;
}

function buildSearchLibraryRoomMembersTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'search_library_room_members';
  t.title = '研读间成员搜索';
  t.description = '按姓名/学号关键词搜索研读间预约成员，返回 memberAccNo 供 book_library_room 使用。涉及他人信息，结果会脱敏。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"keyword":{"type":"string","description":"姓名或学号关键词"}'
    + '},"required":["keyword"]}';
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.library.room.member.read';
  t.summarize = (args: Record<string, Object>): string => '搜索研读间成员';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const roomService: LibraryRoomService = SessionManager.getLibraryRoomService();
    const keyword: string = argString(args, 'keyword').trim();
    const members: LibRoomMember[] = await roomService.getRoomMemberCandidates(keyword);
    const arr: Object[] = [];
    const n: number = members.length < 10 ? members.length : 10;
    for (let i: number = 0; i < n; i++) {
      const rec: Record<string, Object> = {};
      rec['memberAccNo'] = members[i].accNo;
      rec['label'] = maskIdentifier(members[i].label);
      rec['department'] = members[i].department;
      arr.push(rec);
    }
    const r: Record<string, Object> = {};
    r['count'] = members.length;
    r['members'] = arr;
    return r;
  };
  return t;
}

function buildListLibraryRoomBookingRecordsTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'list_library_room_booking_records';
  t.title = '研读间预约记录';
  t.description = '查询未来 7 天研读间预约记录。取消预约前先调用它拿 uuid。';
  t.parametersJson = emptyParamsJson();
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.library.room.booking.read';
  t.summarize = (args: Record<string, Object>): string => '查询研读间预约记录';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const roomService: LibraryRoomService = SessionManager.getLibraryRoomService();
    const records: LibRoomBookRecord[] = await roomService.getRoomBookingRecords();
    const arr: Object[] = [];
    const n: number = records.length < 20 ? records.length : 20;
    for (let i: number = 0; i < n; i++) {
      const item: LibRoomBookRecord = records[i];
      const rec: Record<string, Object> = {};
      rec['uuid'] = item.uuid;
      rec['rsvId'] = item.rsvId;
      rec['owner'] = item.owner;
      rec['ownerId'] = maskIdentifier(item.ownerId);
      rec['date'] = item.date;
      rec['begin'] = item.beginFull;
      rec['end'] = item.endFull;
      rec['devName'] = item.devName;
      rec['kindName'] = item.kindName;
      rec['members'] = item.membersText;
      arr.push(rec);
    }
    const r: Record<string, Object> = {};
    r['count'] = records.length;
    r['records'] = arr;
    return r;
  };
  return t;
}

// ============================================================
// 新闻
// ============================================================

function newsRecord(n: CampusNews): Record<string, Object> {
  const rec: Record<string, Object> = {};
  rec['title'] = n.title;
  rec['date'] = n.date;
  rec['source'] = n.source;
  rec['channel'] = n.channel;
  rec['topped'] = n.topped;
  rec['url'] = n.url;
  return rec;
}

function buildGetNewsListTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'get_news_list';
  t.title = '校园新闻列表';
  t.description = '获取最新的校园新闻列表，支持按频道筛选。回答"最近有什么新闻"之类的问题。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"page":{"type":"number","description":"页码，默认 1"},'
    + '"length":{"type":"number","description":"每页条数，默认 20"},'
    + '"channel":{"type":"string","description":"频道标签，如 LM_JWGG（教务通知）"}'
    + '}}';
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.news.read';
  t.summarize = (args: Record<string, Object>): string => '获取校园新闻';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const service: CampusDataService = SessionManager.getCampusDataService();
    const pageArg: number = argNumber(args, 'page');
    const lengthArg: number = argNumber(args, 'length');
    const page: number = Number.isNaN(pageArg) || pageArg < 1 ? 1 : pageArg;
    const length: number = Number.isNaN(lengthArg) || lengthArg < 1 ? 20 : lengthArg;
    const channel: string = argString(args, 'channel').trim();
    const list: CampusNews[] = await service.fetchNewsList(page, length);
    const arr: Object[] = [];
    for (let i: number = 0; i < list.length && arr.length < 30; i++) {
      if (channel.length > 0 && list[i].channel !== channel) {
        continue;
      }
      arr.push(newsRecord(list[i]));
    }
    const r: Record<string, Object> = {};
    r['count'] = arr.length;
    r['news'] = arr;
    return r;
  };
  return t;
}

function buildSearchNewsTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'search_news';
  t.title = '搜索新闻';
  t.description = '按关键词搜索校园新闻，支持按频道筛选。回答"找关于XX的新闻"之类的问题。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"key":{"type":"string","description":"搜索关键词"},'
    + '"page":{"type":"number","description":"页码，默认 1"},'
    + '"channel":{"type":"string","description":"频道标签，可选"},'
    + '"exactMatch":{"type":"boolean","description":"是否精确匹配标题，默认 false"}'
    + '},"required":["key"]}';
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.news.read';
  t.summarize = (args: Record<string, Object>): string => '搜索新闻：' + argString(args, 'key');
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const service: CampusDataService = SessionManager.getCampusDataService();
    const key: string = argString(args, 'key').trim();
    if (key.length === 0) {
      return { 'error': '请提供搜索关键词' };
    }
    const pageArg: number = argNumber(args, 'page');
    const page: number = Number.isNaN(pageArg) || pageArg < 1 ? 1 : pageArg;
    const channel: string = argString(args, 'channel').trim();
    const exactVal: Object | undefined = args['exactMatch'];
    const exactMatch: boolean = typeof exactVal === 'boolean' && exactVal;
    // 无 searchNewsList → 多页拉取 + 客户端过滤
    const collected: CampusNews[] = [];
    const maxPages: number = 3;
    for (let p: number = 0; p < maxPages; p++) {
      const batch: CampusNews[] = await service.fetchNewsList(page + p, 20);
      for (let i: number = 0; i < batch.length; i++) {
        collected.push(batch[i]);
      }
      if (batch.length < 20) {
        break;
      }
    }
    const arr: Object[] = [];
    for (let i: number = 0; i < collected.length && arr.length < 30; i++) {
      const n: CampusNews = collected[i];
      if (exactMatch ? n.title !== key : !n.title.includes(key)) {
        continue;
      }
      if (channel.length > 0 && n.channel !== channel) {
        continue;
      }
      arr.push(newsRecord(n));
    }
    const r: Record<string, Object> = {};
    r['count'] = arr.length;
    r['news'] = arr;
    return r;
  };
  return t;
}

function buildGetNewsDetailTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'get_news_detail';
  t.title = '新闻详情摘要';
  t.description = '读取某条校园新闻详情并返回纯文本摘要。需要传入 get_news_list/search_news 返回的 url；只读，不收藏、不订阅、不修改新闻偏好。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"url":{"type":"string","description":"新闻详情 URL，来自 get_news_list/search_news 返回值"},'
    + '"maxChars":{"type":"number","description":"返回摘要最大字符数，默认 1600，最多 3000"}'
    + '},"required":["url"]}';
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.news.read';
  t.summarize = (args: Record<string, Object>): string => '读取新闻详情摘要';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const service: CampusDataService = SessionManager.getCampusDataService();
    const url: string = argString(args, 'url');
    if (url.length === 0) {
      return { 'error': '缺少新闻 url' };
    }
    const detail: CampusNewsDetail = await service.fetchNewsDetail(url);
    const maxCharsArg: number = argNumber(args, 'maxChars');
    let maxChars: number = Number.isNaN(maxCharsArg) ? 1600 : maxCharsArg;
    maxChars = maxChars < 300 ? 300 : (maxChars > 3000 ? 3000 : maxChars);
    const text: string = detail.content.replace(/\s+/g, ' ').trim();
    const r: Record<string, Object> = {};
    r['title'] = detail.title;
    r['summary'] = text.length > maxChars ? text.substring(0, maxChars) : text;
    r['truncated'] = text.length > maxChars;
    r['sourceUrl'] = url;
    r['textLength'] = text.length;
    return r;
  };
  return t;
}

// ============================================================
// 邮件
// ============================================================

function buildListMailFoldersTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'list_mail_folders';
  t.title = '邮箱文件夹';
  t.description = '列出已配置清华邮箱客户端中的可查询文件夹。只读；不会发送、删除或移动邮件。';
  t.parametersJson = emptyParamsJson();
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.mail.read';
  t.summarize = (args: Record<string, Object>): string => '查询邮箱文件夹';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const arr: Object[] = [];
    for (let i: number = 0; i < MAIL_FOLDERS.length; i++) {
      const f: MailFolder = MAIL_FOLDERS[i];
      const rec: Record<string, Object> = {};
      rec['id'] = f.id;
      rec['name'] = f.name;
      rec['system'] = f.system;
      arr.push(rec);
    }
    return { 'folders': arr };
  };
  return t;
}

function buildSearchMailMessagesTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'search_mail_messages';
  t.title = '查询邮件列表';
  t.description = '查询或搜索清华邮箱邮件列表。folderSystem 可为 inbox/drafts/sent/deleted/junk，默认 inbox；query 为空时返回最近邮件。只读。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"folderSystem":{"type":"string","enum":["inbox","drafts","sent","deleted","junk"],"description":"默认 inbox"},'
    + '"query":{"type":"string","description":"搜索关键词，可为空"},'
    + '"limit":{"type":"number","description":"返回数量，默认 10，最多 30"}'
    + '}}';
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.mail.read';
  t.summarize = (args: Record<string, Object>): string => {
    const query: string = argString(args, 'query');
    return query.length > 0 ? '搜索邮件：' + query : '查询最近邮件';
  };
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const mail: MailService = SessionManager.getMailService();
    const folderSystem: string = argString(args, 'folderSystem');
    const system: string = folderSystem.length > 0 ? folderSystem : 'inbox';
    const query: string = argString(args, 'query').trim();
    const limitArg: number = argNumber(args, 'limit');
    let limit: number = Number.isNaN(limitArg) ? 10 : limitArg;
    limit = limit < 1 ? 1 : (limit > 30 ? 30 : limit);
    let folder: MailFolder | undefined = undefined;
    for (let i: number = 0; i < MAIL_FOLDERS.length; i++) {
      if (MAIL_FOLDERS[i].system === system) {
        folder = MAIL_FOLDERS[i];
        break;
      }
    }
    if (folder === undefined) {
      folder = MAIL_FOLDERS[0];
    }
    const result: MailListResult = query.length > 0
      ? await mail.searchMessages(query, 0, limit)
      : await mail.listMessages(folder.id, 0, limit);
    const messages: Object[] = [];
    const n: number = result.messages.length < limit ? result.messages.length : limit;
    for (let i: number = 0; i < n; i++) {
      const m: MailMessageSummary = result.messages[i];
      const rec: Record<string, Object> = {};
      rec['id'] = m.id;
      rec['subject'] = m.subject;
      rec['from'] = m.from;
      rec['to'] = m.to;
      rec['date'] = m.date;
      rec['unread'] = m.unread;
      rec['hasAttachment'] = m.hasAttachment;
      rec['brief'] = m.brief;
      messages.push(rec);
    }
    const folderRec: Record<string, Object> = {};
    folderRec['name'] = folder.name;
    folderRec['system'] = folder.system;
    const r: Record<string, Object> = {};
    r['folder'] = folderRec;
    r['total'] = result.total;
    r['messages'] = messages;
    return r;
  };
  return t;
}

function buildReadMailMessageTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'read_mail_message';
  t.title = '读取邮件详情';
  t.description = '读取清华邮箱中指定邮件的正文摘要和附件列表。需要先通过 search_mail_messages 拿到 id。只读。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"id":{"type":"string","description":"邮件 UID"},'
    + '"folderName":{"type":"string","description":"IMAP 文件夹名，如 INBOX（兼容保留，实际按 id 读取）"}'
    + '},"required":["id","folderName"]}';
  t.risk = ToolRisk.NONE;
  t.permission = 'campus.mail.read';
  t.summarize = (args: Record<string, Object>): string => '读取邮件详情';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const mail: MailService = SessionManager.getMailService();
    const id: string = argString(args, 'id');
    if (id.length === 0) {
      return { 'error': '缺少邮件 id' };
    }
    const message: MailMessageDetail = await mail.readMessage(id);
    const attachments: Object[] = [];
    for (let i: number = 0; i < message.attachments.length; i++) {
      const rec: Record<string, Object> = {};
      rec['name'] = message.attachments[i].name;
      rec['size'] = message.attachments[i].size;
      attachments.push(rec);
    }
    const r: Record<string, Object> = {};
    r['id'] = message.id;
    r['subject'] = message.subject;
    r['from'] = message.from;
    r['to'] = message.to;
    r['cc'] = message.cc;
    r['date'] = message.date;
    r['hasAttachment'] = message.hasAttachment;
    r['attachments'] = attachments;
    r['text'] = message.contentText.length > 6000 ? message.contentText.substring(0, 6000) : message.contentText;
    return r;
  };
  return t;
}

// ============================================================
// 个人备忘 / 周日程
// ============================================================

function buildListPersonalEventsTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'list_personal_events';
  t.title = '个人备忘列表';
  t.description = '列出用户自建备忘日程（不含教务课表）。可按 startDate/endDate（YYYY-MM-DD）筛选；不传则默认本周。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"startDate":{"type":"string","description":"起始日期 YYYY-MM-DD"},'
    + '"endDate":{"type":"string","description":"结束日期 YYYY-MM-DD"}'
    + '}}';
  t.risk = ToolRisk.NONE;
  t.permission = 'schedule.personal.read';
  t.summarize = (args: Record<string, Object>): string => '查询个人备忘日程';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    let start: string = normalizeDateString(argString(args, 'startDate'));
    let end: string = normalizeDateString(argString(args, 'endDate'));
    if (start.length === 0 && end.length === 0) {
      const week: string[] = weekDatesContaining(todayLocalISO(), 0);
      start = week[0];
      end = week[6];
    }
    const events: AgentPersonalEvent[] = await AgentWriteTools.listPersonalEventsInRange(start, end);
    const arr: Object[] = [];
    for (let i: number = 0; i < events.length; i++) {
      const e: AgentPersonalEvent = events[i];
      const rec: Record<string, Object> = {};
      rec['id'] = e.id;
      rec['date'] = e.date;
      rec['title'] = e.title;
      rec['time'] = e.startTime + '-' + e.endTime;
      rec['location'] = e.location;
      rec['note'] = e.note;
      arr.push(rec);
    }
    const r: Record<string, Object> = {};
    r['count'] = events.length;
    r['events'] = arr;
    return r;
  };
  return t;
}

function buildGetWeekScheduleTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'get_week_schedule';
  t.title = '周日程';
  t.description = '获取某周合并后的日程：教务课表 + 用户备忘。weekOffset：0=本周，1=下周，-1=上周。用于回答"这周/下周有什么安排"。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"weekOffset":{"type":"number","description":"相对本周偏移，默认 0"}'
    + '}}';
  t.risk = ToolRisk.NONE;
  t.permission = 'schedule.read';
  t.summarize = (args: Record<string, Object>): string => '读取周日程';
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    const offsetArg: number = argNumber(args, 'weekOffset');
    const weekOffset: number = Number.isNaN(offsetArg) ? 0 : offsetArg;
    const dates: string[] = weekDatesContaining(todayLocalISO(), weekOffset);
    // 教务课表（真实请求；演示模式/失败按空课表兜底）
    const courseEvents: ScheduleEvent[] = [];
    if (!SettingsManager.isDemoMode()) {
      try {
        const service: CampusDataService = SessionManager.getCampusDataService();
        const events: ScheduleEvent[] =
          await service.fetchScheduleEvents(ymdFromIso(dates[0]), ymdFromIso(dates[6]));
        for (let i: number = 0; i < events.length; i++) {
          courseEvents.push(events[i]);
        }
      } catch (e) {
        // 课表失败：仅返回个人备忘
      }
    }
    const personal: AgentPersonalEvent[] =
      await AgentWriteTools.listPersonalEventsInRange(dates[0], dates[6]);
    const byDay: Record<string, Object> = {};
    for (let d: number = 0; d < dates.length; d++) {
      const date: string = dates[d];
      const items: Object[] = [];
      for (let i: number = 0; i < courseEvents.length; i++) {
        const ev: ScheduleEvent = courseEvents[i];
        if (ev.date.length >= 10 ? ev.date.substring(0, 10) === date : ev.date === date) {
          const rec: Record<string, Object> = {};
          rec['kind'] = 'course';
          rec['title'] = ev.title;
          rec['time'] = ev.startTime + '-' + ev.endTime;
          rec['location'] = ev.location;
          items.push(rec);
        }
      }
      for (let i: number = 0; i < personal.length; i++) {
        const p: AgentPersonalEvent = personal[i];
        if (normalizeDateString(p.date) === date) {
          const rec: Record<string, Object> = {};
          rec['kind'] = 'personal';
          rec['id'] = p.id;
          rec['title'] = p.title;
          rec['time'] = p.startTime + '-' + p.endTime;
          rec['location'] = p.location;
          rec['note'] = p.note;
          items.push(rec);
        }
      }
      byDay[date] = items;
    }
    const r: Record<string, Object> = {};
    r['weekStart'] = dates[0];
    r['weekEnd'] = dates[6];
    r['days'] = byDay;
    return r;
  };
  return t;
}

// ============================================================
// 合并注册表（35 只读 + AgentWriteTools 10 可逆写 = 45）
// ============================================================

export class AgentTools {
  private static registry: AgentToolDef[] = [];
  private static loaded: boolean = false;

  private static readTools(): AgentToolDef[] {
    return [
      buildGetCampusWeatherTool(),
      buildGetTodayOverviewTool(),
      buildListHomeworkTool(),
      buildGetHomeworkDetailTool(),
      buildGetGradesTool(),
      buildGetElectricityTool(),
      buildListLaundryBuildingsTool(),
      buildGetLaundryStatusTool(),
      buildGetCampusCardBalanceTool(),
      buildGetCampusCardTransactionsTool(),
      buildGetNetworkBalanceTool(),
      buildGetNetworkAccountInfoTool(),
      buildListNetworkDevicesTool(),
      buildListSportsVenuesTool(),
      buildSearchSportsSlotsTool(),
      buildListSportsReservationRecordsTool(),
      buildListClassroomBuildingsTool(),
      buildFindAvailableClassroomsTool(),
      buildListLibrariesTool(),
      buildListFloorsTool(),
      buildListSectionsTool(),
      buildFindSeatsTool(),
      buildListLibraryBookingRecordsTool(),
      buildListLibraryRoomTypesTool(),
      buildFindLibraryRoomsTool(),
      buildSearchLibraryRoomMembersTool(),
      buildListLibraryRoomBookingRecordsTool(),
      buildGetNewsListTool(),
      buildSearchNewsTool(),
      buildGetNewsDetailTool(),
      buildListMailFoldersTool(),
      buildSearchMailMessagesTool(),
      buildReadMailMessageTool(),
      buildListPersonalEventsTool(),
      buildGetWeekScheduleTool(),
    ];
  }

  /** 全量注册表（只读 35 + 可逆写 10；disabledPermissions 可按 permission 剔除） */
  static all(disabledPermissions: string[] = []): AgentToolDef[] {
    if (!AgentTools.loaded) {
      const tools: AgentToolDef[] = AgentTools.readTools();
      const writes: AgentToolDef[] = AgentWriteTools.list();
      for (let i: number = 0; i < writes.length; i++) {
        tools.push(writes[i]);
      }
      AgentTools.registry = tools;
      AgentTools.loaded = true;
    }
    if (disabledPermissions.length === 0) {
      return AgentTools.registry;
    }
    const out: AgentToolDef[] = [];
    for (let i: number = 0; i < AgentTools.registry.length; i++) {
      let disabled: boolean = false;
      for (let j: number = 0; j < disabledPermissions.length; j++) {
        if (AgentTools.registry[i].permission === disabledPermissions[j]) {
          disabled = true;
          break;
        }
      }
      if (!disabled) {
        out.push(AgentTools.registry[i]);
      }
    }
    return out;
  }

  /** 按名查找（未知工具返回 undefined） */
  static byName(name: string): AgentToolDef | undefined {
    const all: AgentToolDef[] = AgentTools.all();
    for (let i: number = 0; i < all.length; i++) {
      if (all[i].name === name) {
        return all[i];
      }
    }
    return undefined;
  }

  /** 全部唯一权限键（保持注册顺序，去重；权限页展示用） */
  static permissionKeys(): string[] {
    const registry: AgentToolDef[] = AgentTools.all();
    const out: string[] = [];
    for (let i: number = 0; i < registry.length; i++) {
      const permission: string = registry[i].permission;
      if (permission.length === 0) {
        continue;
      }
      let exists: boolean = false;
      for (let j: number = 0; j < out.length; j++) {
        if (out[j] === permission) {
          exists = true;
          break;
        }
      }
      if (!exists) {
        out.push(permission);
      }
    }
    return out;
  }
}
