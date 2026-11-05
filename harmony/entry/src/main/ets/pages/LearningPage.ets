/**
 * LearningPage — 学习页（4 子标签 + DDL 弹窗）
 */
import { Theme, SafeTop, Space, Radius, FontSize } from './Theme';
import { ScreenHeader } from '../components/Ui';
import {
  getTodayDateStr,
  getDemoCampusCourses, getDemoCampusHomework, getDemoCampusNotifications, getDemoCampusFiles,
  CourseItem, HomeworkItem, NotificationItem, FileItem, DeadlineForm
} from './LearningData';
import { Log } from '../utils/Logger';
import { I18n } from '../utils/I18n';
import { CourseDetailPage } from './learning/CourseDetailPage';
import { HomeworkDetailPage } from './learning/HomeworkDetailPage';
import { NotificationDetailPage } from './learning/NotificationDetailPage';
import { FileDetailPage } from './learning/FileDetailPage';
import { WebViewerPage } from './learning/WebViewerPage';
import { SessionManager } from '../services/auth/SessionManager';
import { CampusCourse, CampusDataService, CampusHomework, CampusNotification, CampusFile } from '../services/campus/CampusDataService';
import { AuthManager } from '../state/AuthManager';
import { StateManager } from '../state/StateManager';
import { BackDispatcher, BackOwner, BackHandler } from '../state/BackDispatcher';
import { subscribeNavigate, unsubscribeNavigate, NavigateSubscription, NavTarget, takePendingLearningTab } from '../state/UiEvents';
import { ManualDeadlineStore } from '../state/ManualDeadlineStore';
import { ManualDeadline } from '../domain/DeadlineTypes';
import { parseDeadlineMs, formatDeadlineDistance, compareDeadlineTextAsc } from '../utils/DeadlineFormat';

@Component
struct SegmentBar {
  @Link activeTab: string;
  /** 子标签逻辑标识（中文常量，跨页契约：与 HomeData 的 learningTab/页面 activeTab 匹配） */
  @Prop tabs: string[] = [];
  /** 子标签展示文案（按当前语言翻译，由父组件传入） */
  @Prop labels: string[] = [];
  @Prop counts: number[] = [];

  build() {
    Row() {
      ForEach(this.tabs, (tab: string, index: number) => {
        Row({ space: 4 }) {
          Text(this.labels.length > index ? this.labels[index] : tab)
            .fontSize(FontSize.caption)
            .fontWeight(this.activeTab === tab ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.activeTab === tab ? Theme.text : Theme.textSecondary)
          Text(String(this.counts[index]))
            .fontSize(FontSize.micro)
            .fontColor(this.activeTab === tab ? Theme.primary : Theme.textMuted)
        }
        .justifyContent(FlexAlign.Center)
        .layoutWeight(1)
        .height(38)
        .borderRadius(Radius.sm)
        .backgroundColor(this.activeTab === tab ? Theme.surface : 'transparent')
        .onClick(() => {
          this.activeTab = tab;
        })
      })
    }
    .width('100%')
    .padding(4)
    .borderRadius(Radius.md)
    .backgroundColor(Theme.surfaceAlt)
  }
}

@Component
struct DDLCard {
  @Prop item: HomeworkItem = new HomeworkItem();
  /** 手动来源徽标文案（父组件按当前语言传入） */
  @Prop manualBadgeText: string = '';
  onCardClick: () => void = () => {};
  /** 删除入口（仅手动 DDL 卡片渲染） */
  onDelete: () => void = () => {};

  /** 截止时间已过（过期视觉区分：红条 + 灰标题 + 红状态） */
  private isOverdue(): boolean {
    const ms: number = parseDeadlineMs(this.item.deadline);
    return !isNaN(ms) && ms < Date.now();
  }

  build() {
    Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Stretch }) {
      Column()
        .width(3)
        .borderRadius(2)
        .backgroundColor(this.isOverdue() ? Theme.error : (this.item.status === '即将截止' ? Theme.warning : Theme.primary))

      Column() {
        Row({ space: 6 }) {
          Text(this.item.title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isOverdue() ? Theme.textMuted : Theme.text)
            .layoutWeight(1)
          if (this.item.manual) {
            Text(this.manualBadgeText)
              .fontSize(10)
              .fontColor(Theme.primary)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)
              .backgroundColor(Theme.primaryMuted)
          }
        }
        .width('100%')

        Text(`${this.item.course}  ·  ${this.item.deadline}`)
          .fontSize(12)
          .fontColor(Theme.textSecondary)
          .margin({ top: 4 })

        if (this.item.manual && this.item.note.length > 0) {
          Text(this.item.note)
            .fontSize(11)
            .fontColor(Theme.textMuted)
            .margin({ top: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      .layoutWeight(1)

      if (this.item.manual) {
        Text('✕')
          .fontSize(13)
          .fontColor(Theme.textMuted)
          .alignSelf(ItemAlign.Center)
          .padding(8)
          .onClick(() => {
            this.onDelete();
          })
      }

      Text(this.item.status)
        .fontSize(11)
        .fontColor(this.isOverdue() ? Theme.error : Theme.warning)
        .alignSelf(ItemAlign.Center)
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .borderRadius(8)
        .backgroundColor(this.isOverdue() ? Theme.errorMuted : 'rgba(217,119,6,0.10)')
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .onClick(() => {
      this.onCardClick();
    })
  }
}

@Component
struct CourseCard {
  @Prop item: CourseItem = new CourseItem();
  onCardClick: () => void = () => {};

  build() {
    Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Stretch }) {
      Column()
        .width(3)
        .borderRadius(2)
        .backgroundColor(Theme.primary)

      Column() {
        Text(this.item.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
        Text(`${this.item.teacher}  ·  ${this.item.code}`)
          .fontSize(12)
          .fontColor(Theme.textSecondary)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .onClick(() => {
      this.onCardClick();
    })
  }
}

@Component
struct NotificationCard {
  @Prop item: NotificationItem = new NotificationItem();
  @Prop badgeText: string = 'NEW';
  onCardClick: () => void = () => {};

  build() {
    Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Stretch }) {
      Column()
        .width(3)
        .borderRadius(2)
        .backgroundColor(this.item.isNew ? Theme.warning : Theme.divider)

      Column() {
        Text(this.item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
        Text(`${this.item.publisher}  ·  ${this.item.time}`)
          .fontSize(12)
          .fontColor(Theme.textSecondary)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      .layoutWeight(1)

      if (this.item.isNew) {
        Text(this.badgeText)
          .fontSize(11)
          .fontColor(Theme.warning)
          .alignSelf(ItemAlign.Center)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
          .backgroundColor('rgba(217,119,6,0.10)')
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .onClick(() => {
      this.onCardClick();
    })
  }
}

@Component
struct FileCard {
  @Prop item: FileItem = new FileItem();
  @Prop badgeText: string = 'NEW';
  onCardClick: () => void = () => {};

  build() {
    Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Stretch }) {
      Column()
        .width(3)
        .borderRadius(2)
        .backgroundColor(this.item.isNew ? Theme.warning : Theme.divider)

      Column() {
        Text(this.item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
        Text(`${this.item.course}  ·  ${this.item.size}`)
          .fontSize(12)
          .fontColor(Theme.textSecondary)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      .layoutWeight(1)

      if (this.item.isNew) {
        Text(this.badgeText)
          .fontSize(11)
          .fontColor(Theme.warning)
          .alignSelf(ItemAlign.Center)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
          .backgroundColor('rgba(217,119,6,0.10)')
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .onClick(() => {
      this.onCardClick();
    })
  }
}

@Component
export struct LearningPage {
  /** 语言订阅：语言切换即时重渲染 */
  @StorageLink('locale') locale: string = 'zh';

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  private trp(key: string, args: Record<string, string>): string {
    return I18n.tp(key, args, this.locale);
  }

  @State activeTab: string = '课程';
  @State showDialog: boolean = false;
  /** 手动 DDL（store 共享数据：页面/AI/首页同源，订阅变更即时刷新） */
  @State manualDdls: ManualDeadline[] = [];
  /** 当前 Tab 是否为学习页：切回时重载手动 DDL（Tabs 常驻页面无页面级 onShow） */
  @Prop @Watch('onActiveChange') active: boolean = false;
  /** store 变更信号：隐藏/常驻页面也能通过 AppStorage 收到手动 DDL 更新（FR-019） */
  @StorageLink('manualDdlTick') @Watch('onManualDdlTick') manualDdlTick: number = 0;
  private storeSubId: number = -1;
  @State form: DeadlineForm = new DeadlineForm();
  /** 保存中标记：防重复提交（保存按钮在请求 settle 前禁用） */
  @State savingDDL: boolean = false;
  @State @Watch('onSubScreenChange') subScreen: string = '';
  /** 嵌套详情来源：'' 从列表进入 / 'course' 从课程详情下钻（返回时回到课程详情） */
  @State detailParent: string = '';
  private backHandler: BackHandler = () => {
    // 预览 WebView 的系统返回：回到文件详情（与 WebViewerPage 左上角返回一致），保留 detailParent
    if (this.subScreen === 'webview') {
      this.subScreen = 'file';
      return true;
    }
    this.exitDetail();
    return true;
  };
  // 列表显示（UI 模型）
  @State realCourses: CourseItem[] = [];
  @State realDdls: HomeworkItem[] = [];
  @State realNotifications: NotificationItem[] = [];
  @State realFiles: FileItem[] = [];
  @State currentSemester: string = '';
  // 选中项（真实数据，传详情页）
  @State selectedCourse: CampusCourse = new CampusCourse();
  @State selectedHomework: CampusHomework = new CampusHomework();
  @State selectedNotification: CampusNotification = new CampusNotification();
  @State selectedFile: CampusFile = new CampusFile();
  // 应用内预览（资料详情 → WebViewer；返回留在文件详情）
  @State previewUrl: string = '';
  @State previewTitle: string = '';
  // 原始 Campus 数据（详情页数据源；@State：数组整体赋值后传给详情页的 @Prop 同步重渲染）
  @State realCampusCourses: CampusCourse[] = [];
  @State realCampusHomework: CampusHomework[] = [];
  @State realCampusNotifications: CampusNotification[] = [];
  @State realCampusFiles: CampusFile[] = [];
  /** 三类扩展数据是否已加载完成（真实模式：三个请求 settle 后置真；演示模式直接置真） */
  @State extrasLoaded: boolean = false;
  /** 三类扩展数据是否正在拉取（重试期间显示加载态，不显示“暂无”） */
  @State extrasLoading: boolean = false;
  /** 三类扩展数据上次拉取是否有失败 */
  @State extrasFailed: boolean = false;
  /** 各标签独立失败态：区分「拉取失败」与「真的没有数据」 */
  @State coursesLoadFailed: boolean = false;
  @State homeworkLoadFailed: boolean = false;
  @State notificationsLoadFailed: boolean = false;
  @State filesLoadFailed: boolean = false;
  private tabs: string[] = ['课程', '作业', '通知', '文件'];
  private navSub: NavigateSubscription = new NavigateSubscription();

  aboutToAppear(): void {
    if (this.isRealMode()) {
      this.loadRealCourses();
    } else {
      // 演示模式：原始对象与 UI 列表统一填充（US5），三级下钻共用真实渲染路径
      this.loadDemoData();
    }
    // 手动 DDL 共享数据：首拉 + 订阅（AI/首页删除或新增后本页即时刷新）
    this.ensureManualDdlSubscription();
    // 跨页导航（如首页"添加 DDL"）：切到学习 Tab 后切到指定子标签
    this.navSub = subscribeNavigate((target: NavTarget) => {
      if (target.learningTab.length > 0 && this.tabs.indexOf(target.learningTab) >= 0) {
        this.activeTab = target.learningTab;
      }
      // 已挂载时实时生效后清除本页负责的待处理字段，避免后续挂载陈旧误触发（字段级）
      takePendingLearningTab();
    });
    // 冷启动补偿：本页挂载前发起的跨页导航已记录为待处理目标，此处消费一次（取值即清除）
    const pendingTab: string = takePendingLearningTab();
    if (pendingTab.length > 0 && this.tabs.indexOf(pendingTab) >= 0) {
      this.activeTab = pendingTab;
    }
  }

  onSubScreenChange(): void {
    if (this.subScreen !== '') {
      BackDispatcher.push(BackOwner.LEARNING, this.backHandler);
    } else {
      BackDispatcher.remove(this.backHandler);
    }
  }

  aboutToDisappear(): void {
    BackDispatcher.remove(this.backHandler);
    unsubscribeNavigate(this.navSub);
    if (this.storeSubId >= 0) {
      ManualDeadlineStore.unsubscribe(this.storeSubId);
      this.storeSubId = -1;
    }
  }

  private isRealMode(): boolean {
    return AuthManager.isLoggedIn() && !StateManager.isDemoMode();
  }

  /** 确保手动 DDL 已加载且订阅存在：Tab 切回时重入，保证与 store/首页/ai 一致（FR-019） */
  private ensureManualDdlSubscription(): void {
    ManualDeadlineStore.listAsync().then((list: ManualDeadline[]) => {
      this.manualDdls = list;
    });
    if (this.storeSubId < 0) {
      this.storeSubId = ManualDeadlineStore.subscribe(() => {
        this.manualDdls = ManualDeadlineStore.list();
      });
    }
  }

  /** Tab 切回学习页：重载手动 DDL（保证列表与 store/首页一致） */
  private onActiveChange(): void {
    if (this.active) {
      this.ensureManualDdlSubscription();
    }
  }

  /** store 变更信号：重载列表（与订阅双保险，覆盖隐藏页面） */
  private onManualDdlTick(): void {
    this.ensureManualDdlSubscription();
  }

  /** 详情返回：从课程详情下钻的详情回到课程详情，其余回列表（FR-003 嵌套返回） */
  private exitDetail(): void {
    if (this.detailParent === 'course') {
      this.subScreen = 'course';
      this.detailParent = '';
    } else {
      this.subScreen = '';
      this.detailParent = '';
    }
  }

  /** 当前课程的三类过滤结果（课程详情聚合用；按 courseId 精确匹配） */
  private getCourseHomework(): CampusHomework[] {
    const list: CampusHomework[] = [];
    for (let i: number = 0; i < this.realCampusHomework.length; i++) {
      if (this.realCampusHomework[i].courseId === this.selectedCourse.id) {
        list.push(this.realCampusHomework[i]);
      }
    }
    return list;
  }

  private getCourseNotifications(): CampusNotification[] {
    const list: CampusNotification[] = [];
    for (let i: number = 0; i < this.realCampusNotifications.length; i++) {
      if (this.realCampusNotifications[i].courseId === this.selectedCourse.id) {
        list.push(this.realCampusNotifications[i]);
      }
    }
    return list;
  }

  private getCourseFiles(): CampusFile[] {
    const list: CampusFile[] = [];
    for (let i: number = 0; i < this.realCampusFiles.length; i++) {
      if (this.realCampusFiles[i].courseId === this.selectedCourse.id) {
        list.push(this.realCampusFiles[i]);
      }
    }
    return list;
  }

  private loadRealCourses(): void {
    if (!this.isRealMode()) {
      return;
    }
    this.coursesLoadFailed = false;
    const service: CampusDataService = SessionManager.getCampusDataService();
    service.fetchCourses().then((courses: CampusCourse[]) => {
      Log.i('LearnAct',  'UI_FETCH_COURSES count=%{public}d trace=%{public}s', courses.length, service.trace);
      // fetchCourses 内部吞异常并返回 []：用 trace 区分「成功但无课(ok:0)」与「拉取失败」
      const ok: boolean = service.trace.indexOf('ok:') === 0;
      if (!ok) {
        this.coursesLoadFailed = true;
        this.homeworkLoadFailed = true;
        this.notificationsLoadFailed = true;
        this.filesLoadFailed = true;
        this.extrasFailed = true;
        return;
      }
      this.coursesLoadFailed = false;
      this.homeworkLoadFailed = false;
      this.notificationsLoadFailed = false;
      this.filesLoadFailed = false;
      this.extrasFailed = false;
      this.realCampusCourses = courses;
      this.currentSemester = service.currentSemester;
      const mapped: CourseItem[] = [];
      for (let i: number = 0; i < courses.length; i++) {
        const item: CourseItem = new CourseItem();
        item.name = courses[i].name;
        item.teacher = courses[i].teacher;
        item.code = courses[i].code;
        mapped.push(item);
      }
      this.realCourses = mapped;
      if (courses.length > 0) {
        this.loadRealExtras(service, courses);
      }
    }).catch((e: Object) => {
      this.coursesLoadFailed = true;
      Log.i('LearnAct',  'UI_FETCH_COURSES ex trace=%{public}s', service.trace);
    });
  }

  private retryLoadCourses(): void {
    if (!this.isRealMode()) {
      return;
    }
    this.realCourses = [];
    this.loadRealCourses();
  }

  private retryLoadExtras(): void {
    if (!this.isRealMode()) {
      return;
    }
    if (this.realCampusCourses.length === 0) {
      // 课程都未加载成功时，重试应从课程列表开始
      this.retryLoadCourses();
      return;
    }
    this.homeworkLoadFailed = false;
    this.notificationsLoadFailed = false;
    this.filesLoadFailed = false;
    this.extrasFailed = false;
    this.extrasLoaded = false;
    this.loadRealExtras(SessionManager.getCampusDataService(), this.realCampusCourses);
  }

  private loadRealExtras(service: CampusDataService, courses: CampusCourse[]): void {
    // 严格方法：无会话/全部失败抛错 → 对应标签 failed；三个都 settle（成功或失败）后 extrasLoaded=true
    this.homeworkLoadFailed = false;
    this.notificationsLoadFailed = false;
    this.filesLoadFailed = false;
    this.extrasFailed = false;
    this.extrasLoaded = false;
    this.extrasLoading = true;
    let settled: number = 0;
    const finishOne: () => void = (): void => {
      settled++;
      if (settled >= 3) {
        this.extrasLoading = false;
        this.extrasLoaded = true;
      }
    };
    service.fetchHomeworkStrict(courses).then((list: CampusHomework[]) => {
      this.realCampusHomework = list;
      const mapped: HomeworkItem[] = [];
      for (let i: number = 0; i < list.length; i++) {
        // FR-021：作业标签仅合并「未提交的远程作业」；已提交/已评分项不进 DDL 列表
        if (list[i].submitted || list[i].graded) {
          continue;
        }
        const item: HomeworkItem = new HomeworkItem();
        item.id = list[i].id;
        item.title = list[i].title;
        item.course = list[i].courseName;
        item.deadline = list[i].deadline;
        item.status = list[i].status;
        mapped.push(item);
      }
      this.realDdls = mapped;
    }).catch(() => {
      this.homeworkLoadFailed = true;
      this.extrasFailed = true;
      Log.i('LearnAct', 'UI_FETCH_HW failed');
    }).then((): void => { finishOne(); });

    service.fetchNotificationsStrict(courses).then((list: CampusNotification[]) => {
      this.realCampusNotifications = list;
      const mapped: NotificationItem[] = [];
      for (let i: number = 0; i < list.length; i++) {
        const item: NotificationItem = new NotificationItem();
        item.title = list[i].title;
        item.publisher = list[i].publisher;
        item.time = list[i].publishTime;
        item.isNew = list[i].isNew;
        mapped.push(item);
      }
      this.realNotifications = mapped;
    }).catch(() => {
      this.notificationsLoadFailed = true;
      this.extrasFailed = true;
      Log.i('LearnAct', 'UI_FETCH_NOTIF failed');
    }).then((): void => { finishOne(); });

    service.fetchFilesStrict(courses).then((list: CampusFile[]) => {
      this.realCampusFiles = list;
      const mapped: FileItem[] = [];
      for (let i: number = 0; i < list.length; i++) {
        const item: FileItem = new FileItem();
        item.title = list[i].title;
        item.course = list[i].courseName;
        item.size = list[i].size;
        item.isNew = list[i].isNew;
        mapped.push(item);
      }
      this.realFiles = mapped;
    }).catch(() => {
      this.filesLoadFailed = true;
      this.extrasFailed = true;
      Log.i('LearnAct', 'UI_FETCH_FILES failed');
    }).then((): void => { finishOne(); });
  }

  /**
   * 演示模式数据填充（US5/FR-022）：原始 Campus* 对象与 UI 列表同源填充，
   * 课程/作业/通知/资料四类均可按课程下钻；演示原始数据不含可请求地址（FR-023）。
   */
  private loadDemoData(): void {
    const courses: CampusCourse[] = getDemoCampusCourses();
    const homework: CampusHomework[] = getDemoCampusHomework();
    const notifs: CampusNotification[] = getDemoCampusNotifications();
    const files: CampusFile[] = getDemoCampusFiles();
    this.realCampusCourses = courses;
    this.realCampusHomework = homework;
    this.realCampusNotifications = notifs;
    this.realCampusFiles = files;
    // 演示数据一次性就绪：课程详情不再补拉（演示零请求）
    this.extrasLoaded = true;
    this.extrasLoading = false;
    this.extrasFailed = false;

    const mappedCourses: CourseItem[] = [];
    for (let i: number = 0; i < courses.length; i++) {
      const item: CourseItem = new CourseItem();
      item.name = courses[i].name;
      item.teacher = courses[i].teacher;
      item.code = courses[i].code;
      mappedCourses.push(item);
    }
    this.realCourses = mappedCourses;

    const mappedDdls: HomeworkItem[] = [];
    for (let i: number = 0; i < homework.length; i++) {
      const item: HomeworkItem = new HomeworkItem();
      item.id = homework[i].id;
      item.title = homework[i].title;
      item.course = homework[i].courseName;
      item.deadline = homework[i].deadline;
      item.status = homework[i].status;
      mappedDdls.push(item);
    }
    this.realDdls = mappedDdls;

    const mappedNotifs: NotificationItem[] = [];
    for (let i: number = 0; i < notifs.length; i++) {
      const item: NotificationItem = new NotificationItem();
      item.title = notifs[i].title;
      item.publisher = notifs[i].publisher;
      item.time = notifs[i].publishTime;
      item.isNew = notifs[i].isNew;
      mappedNotifs.push(item);
    }
    this.realNotifications = mappedNotifs;

    const mappedFiles: FileItem[] = [];
    for (let i: number = 0; i < files.length; i++) {
      const item: FileItem = new FileItem();
      item.title = files[i].title;
      item.course = files[i].courseName;
      item.size = files[i].size;
      item.isNew = files[i].isNew;
      mappedFiles.push(item);
    }
    this.realFiles = mappedFiles;
  }

  private getDisplayCourses(): CourseItem[] {
    return this.realCourses;
  }

  private getDisplayHomework(): HomeworkItem[] {
    // FR-021：未提交作业 + 手动 DDL 合并，按截止时间升序（无法解析排最后）
    return this.mergeManualDdls(this.realDdls);
  }

  /** 手动 DDL 映射进 UI 模型并与远程作业合并升序；手动项可从视觉上区分来源 */
  private mergeManualDdls(remote: HomeworkItem[]): HomeworkItem[] {
    const merged: HomeworkItem[] = [];
    for (let i: number = 0; i < remote.length; i++) {
      merged.push(remote[i]);
    }
    // 使用 @State 列表（读取建立 UI 依赖；列表由订阅/Tick 重载保持最新）
    const manualList: ManualDeadline[] = this.manualDdls;
    for (let i: number = 0; i < manualList.length; i++) {
      const md: ManualDeadline = manualList[i];
      const time: string = md.time.length > 0 ? md.time : '23:59';
      const item: HomeworkItem = new HomeworkItem();
      item.id = md.id;
      item.title = md.title;
      item.course = md.course.length > 0 ? md.course : this.tr('learning.customCourse');
      item.deadline = md.date + ' ' + time;
      item.status = formatDeadlineDistance(md.date + ' ' + time, this.locale);
      item.manual = true;
      item.note = md.note;
      merged.push(item);
    }
    merged.sort((a: HomeworkItem, b: HomeworkItem): number => compareDeadlineTextAsc(a.deadline, b.deadline));
    return merged;
  }

  /** 按 id 在远程原始作业中定位（合并排序后展示序与原始序不再对应） */
  private findCampusHomeworkById(id: string): CampusHomework {
    for (let i: number = 0; i < this.realCampusHomework.length; i++) {
      if (this.realCampusHomework[i].id === id) {
        return this.realCampusHomework[i];
      }
    }
    return this.selectedHomework;
  }

  /** 手动 DDL 删除确认（FR-018：删除前 MUST 有确认） */
  private confirmDeleteManual(id: string, title: string): void {
    AlertDialog.show({
      title: this.tr('learning.ddl.deleteTitle'),
      message: this.trp('learning.ddl.deleteMessage', { 'title': title }),
      primaryButton: {
        value: this.tr('common.cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: this.tr('learning.ddl.deleteOk'),
        fontColor: Theme.error,
        action: (): void => {
          this.deleteManual(id);
        }
      },
      cancel: () => {}
    });
  }

  private deleteManual(id: string): void {
    ManualDeadlineStore.remove(id).then((ok: boolean) => {
      if (ok) {
        this.manualDdls = ManualDeadlineStore.list();
        this.getUIContext().getPromptAction().showToast({
          message: this.tr('learning.ddl.deletedToast'),
          duration: 2000
        });
      } else {
        // 持久化失败：条目保留在列表中并给出可读提示（避免静默丢失导致 UI 与磁盘不一致）
        this.getUIContext().getPromptAction().showToast({
          message: this.tr('learning.ddl.deleteFailed'),
          duration: 2000
        });
      }
    }).catch(() => {
      // 防御：store 未来若 reject，也要给可读失败提示
      this.getUIContext().getPromptAction().showToast({
        message: this.tr('learning.ddl.deleteFailed'),
        duration: 2000
      });
    });
  }

  /** 日期格式校验：YYYY-MM-DD 且为真实日期（解析后回读年月日一致，拒绝 2026-02-31 这类自动进位日期） */
  private isValidDate(s: string): boolean {
    const re: RegExp = new RegExp('^\\d{4}-\\d{2}-\\d{2}$');
    if (!re.test(s)) {
      return false;
    }
    const parts: string[] = s.split('-');
    const y: number = Number(parts[0]);
    const m: number = Number(parts[1]);
    const d: number = Number(parts[2]);
    if (isNaN(y) || isNaN(m) || isNaN(d)) {
      return false;
    }
    const parsed: Date = new Date(y, m - 1, d);
    return parsed.getFullYear() === y && parsed.getMonth() === m - 1 && parsed.getDate() === d;
  }

  /** 时间格式校验：接受 H:mm / HH:mm，且小时 0–23、分钟 0–59 */
  private isValidTime(s: string): boolean {
    return this.normalizeTime(s).length > 0;
  }

  /** 时间归一：H:mm / HH:mm → HH:mm（小时 0–23、分钟 0–59）；非法返回空串 */
  private normalizeTime(s: string): string {
    const re: RegExp = new RegExp('^\\d{1,2}:\\d{2}$');
    if (!re.test(s)) {
      return '';
    }
    const parts: string[] = s.split(':');
    const h: number = Number(parts[0]);
    const m: number = Number(parts[1]);
    if (isNaN(h) || isNaN(m) || h < 0 || h > 23 || m < 0 || m > 59) {
      return '';
    }
    return (h < 10 ? '0' + String(h) : String(h)) + ':' + (m < 10 ? '0' + String(m) : String(m));
  }

  private getDisplayNotifications(): NotificationItem[] {
    return this.realNotifications;
  }

  private getDisplayFiles(): FileItem[] {
    return this.realFiles;
  }

  private getTabCounts(): number[] {
    return [this.getDisplayCourses().length, this.getDisplayHomework().length, this.getDisplayNotifications().length, this.getDisplayFiles().length];
  }

  private getTabCountsSnippet(): string {
    const c: number[] = this.getTabCounts();
    return this.trp('learning.countsSnippet', {
      'a': String(c[0]),
      'b': String(c[1]),
      'c': String(c[2]),
      'd': String(c[3])
    });
  }

  /** 子标签展示文案（按当前语言；逻辑标识仍用 this.tabs 的中文常量） */
  private getTabLabels(): string[] {
    return [
      this.tr('learning.tabCourses'),
      this.tr('learning.tabHomework'),
      this.tr('learning.tabNotifications'),
      this.tr('learning.tabFiles')
    ];
  }

  @Builder
  addActionButton() {
    Button('+')
      .type(ButtonType.Circle)
      .width(36)
      .height(36)
      .fontSize(20)
      .fontColor(Theme.textInvert)
      .backgroundColor(Theme.primary)
      .onClick(() => {
        this.form = new DeadlineForm();
        this.form.date = getTodayDateStr();
        this.form.time = '23:59';
        this.showDialog = true;
      })
  }

  @Builder
  listFailedHint(onRetry: () => void) {
    Row() {
      Text(this.tr('learning.listLoadFailed'))
        .fontSize(14)
        .fontColor(Theme.error)
        .layoutWeight(1)
      Text(this.tr('common.retry'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.primary)
        .onClick(onRetry)
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
  }

  build() {
    if (this.subScreen === 'course') {
      CourseDetailPage({
        onBack: () => { this.subScreen = ''; this.detailParent = ''; },
        course: this.selectedCourse,
        semester: this.currentSemester,
        homework: this.getCourseHomework(),
        notifications: this.getCourseNotifications(),
        files: this.getCourseFiles(),
        extrasLoaded: this.extrasLoaded,
        extrasFailed: this.extrasFailed,
        demoMode: !this.isRealMode(),
        onOpenHomework: (item: CampusHomework) => {
          this.selectedHomework = item;
          this.detailParent = 'course';
          this.subScreen = 'homework';
        },
        onOpenNotification: (item: CampusNotification) => {
          this.selectedNotification = item;
          this.detailParent = 'course';
          this.subScreen = 'notification';
        },
        onOpenFile: (item: CampusFile) => {
          this.selectedFile = item;
          this.detailParent = 'course';
          this.subScreen = 'file';
        }
      })
    } else if (this.subScreen === 'homework') {
      HomeworkDetailPage({ onBack: () => { this.exitDetail(); }, item: this.selectedHomework, demoMode: !this.isRealMode() })
    } else if (this.subScreen === 'notification') {
      NotificationDetailPage({ onBack: () => { this.exitDetail(); }, item: this.selectedNotification, demoMode: !this.isRealMode() })
    } else if (this.subScreen === 'file') {
      FileDetailPage({
        onBack: () => { this.exitDetail(); },
        item: this.selectedFile,
        demoMode: !this.isRealMode(),
        onPreview: (url: string, title: string) => {
          this.previewUrl = url;
          this.previewTitle = title;
          this.subScreen = 'webview';
        }
      })
    } else if (this.subScreen === 'webview') {
      WebViewerPage({
        onBack: () => { this.subScreen = 'file'; },
        url: this.previewUrl,
        title: this.previewTitle
      })
    } else {
    Stack() {
      Scroll() {
        Column() {
          SafeTop()

          Column() {
            ScreenHeader({
              eyebrow: this.tr('learning.eyebrow'),
              title: this.tr('learning.title'),
              subtitle: this.getTabCountsSnippet(),
              right: (): void => this.addActionButton()
            })
          }
          .width('100%')
          .padding({ left: 20, right: 16, top: 12, bottom: 8 })

          SegmentBar({ activeTab: $activeTab, tabs: this.tabs, labels: this.getTabLabels(), counts: this.getTabCounts() })
            .constraintSize({ maxWidth: '100%' })
            .margin({ left: 20, right: 20, bottom: 16 })

          Divider().color(Theme.divider)

          if (this.activeTab === '课程') {
            Column() {
              ForEach(this.getDisplayCourses(), (item: CourseItem, index: number) => {
                CourseCard({ item: item, onCardClick: () => {
                  if (index < this.realCampusCourses.length) { this.selectedCourse = this.realCampusCourses[index]; }
                  this.detailParent = '';
                  this.subScreen = 'course';
                } })
                if (index < this.getDisplayCourses().length - 1) {
                  Divider()
                    .color(Theme.divider)
                    .width('100%')
                    .constraintSize({ maxWidth: '100%' })
                    .margin({ left: 15 })
                }
              })
              if (this.coursesLoadFailed) {
                this.listFailedHint(() => { this.retryLoadCourses(); })
              } else if (this.getDisplayCourses().length === 0) {
                Text(this.tr('learning.emptyCourses'))
                  .fontSize(14)
                  .fontColor(Theme.textMuted)
                  .padding({ top: 16, bottom: 16 })
              }
            }
            .width('100%')
            .constraintSize({ maxWidth: '100%' })
            .padding(16)
            .borderRadius(Theme.cardRadius)
            .backgroundColor(Theme.surface)
            .border({ width: 1, color: Theme.borderSubtle })
            .margin({ left: 16, right: 16 })
          } else if (this.activeTab === '作业') {
            Column() {
              ForEach(this.getDisplayHomework(), (item: HomeworkItem, index: number) => {
                DDLCard({
                  item: item,
                  manualBadgeText: this.tr('learning.ddl.manualBadge'),
                  onCardClick: () => {
                    if (item.manual) {
                      // 手动 DDL 无详情页，点击不跳转（删除走卡片 ✕）
                      return;
                    }
                    this.selectedHomework = this.findCampusHomeworkById(item.id);
                    this.detailParent = '';
                    this.subScreen = 'homework';
                  },
                  onDelete: () => {
                    if (item.manual) {
                      this.confirmDeleteManual(item.id, item.title);
                    }
                  }
                })
                if (index < this.getDisplayHomework().length - 1) {
                  Divider()
                    .color(Theme.divider)
                    .width('100%')
                    .constraintSize({ maxWidth: '100%' })
                    .margin({ left: 15 })
                }
              })
              if (this.homeworkLoadFailed) {
                // 失败提示独立于列表长度：手动 DDL 存在时也要能重试远程作业
                this.listFailedHint(() => { this.retryLoadExtras(); })
              } else if (this.getDisplayHomework().length === 0) {
                if (this.extrasLoading) {
                  Text(this.tr('status.loading'))
                    .fontSize(14)
                    .fontColor(Theme.textMuted)
                    .padding({ top: 16, bottom: 16 })
                } else {
                  Text(this.tr('learning.emptyHomework'))
                    .fontSize(14)
                    .fontColor(Theme.textMuted)
                    .padding({ top: 16, bottom: 16 })
                }
              }
            }
            .width('100%')
            .constraintSize({ maxWidth: '100%' })
            .padding(16)
            .borderRadius(Theme.cardRadius)
            .backgroundColor(Theme.surface)
            .border({ width: 1, color: Theme.borderSubtle })
            .margin({ left: 16, right: 16 })
          } else if (this.activeTab === '通知') {
            Column() {
              ForEach(this.getDisplayNotifications(), (item: NotificationItem, index: number) => {
                NotificationCard({ item: item, badgeText: this.tr('learning.badgeNew'), onCardClick: () => {
                  if (index < this.realCampusNotifications.length) { this.selectedNotification = this.realCampusNotifications[index]; }
                  this.detailParent = '';
                  this.subScreen = 'notification';
                } })
              })
              if (this.notificationsLoadFailed) {
                this.listFailedHint(() => { this.retryLoadExtras(); })
              } else if (this.getDisplayNotifications().length === 0) {
                if (this.extrasLoading) {
                  Text(this.tr('status.loading'))
                    .fontSize(14)
                    .fontColor(Theme.textMuted)
                    .padding({ top: 16, bottom: 16 })
                } else {
                  Text(this.tr('learning.emptyNotifications'))
                    .fontSize(14)
                    .fontColor(Theme.textMuted)
                    .padding({ top: 16, bottom: 16 })
                }
              }
            }
            .width('100%')
            .constraintSize({ maxWidth: '100%' })
            .padding(16)
            .borderRadius(Theme.cardRadius)
            .backgroundColor(Theme.surface)
            .border({ width: 1, color: Theme.borderSubtle })
            .margin({ left: 16, right: 16 })
          } else {
            Column() {
              ForEach(this.getDisplayFiles(), (item: FileItem, index: number) => {
                FileCard({ item: item, badgeText: this.tr('learning.badgeNew'), onCardClick: () => {
                  if (index < this.realCampusFiles.length) { this.selectedFile = this.realCampusFiles[index]; }
                  this.detailParent = '';
                  this.subScreen = 'file';
                } })
              })
              if (this.filesLoadFailed) {
                this.listFailedHint(() => { this.retryLoadExtras(); })
              } else if (this.getDisplayFiles().length === 0) {
                if (this.extrasLoading) {
                  Text(this.tr('status.loading'))
                    .fontSize(14)
                    .fontColor(Theme.textMuted)
                    .padding({ top: 16, bottom: 16 })
                } else {
                  Text(this.tr('learning.emptyFiles'))
                    .fontSize(14)
                    .fontColor(Theme.textMuted)
                    .padding({ top: 16, bottom: 16 })
                }
              }
            }
            .width('100%')
            .constraintSize({ maxWidth: '100%' })
            .padding(16)
            .borderRadius(Theme.cardRadius)
            .backgroundColor(Theme.surface)
            .border({ width: 1, color: Theme.borderSubtle })
            .margin({ left: 16, right: 16 })
          }

          Blank().height(32)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.background)
      .scrollBar(BarState.Off)

      if (this.showDialog) {
        // 半透明遮罩
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.4)')
          .onClick(() => { this.showDialog = false; })
      }
    }
    .width('100%')
    .height('100%')
    // Tab 切回学习页时重载手动 DDL，避免隐藏期间订阅失效导致列表陈旧
    .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, ratio: number) => {
      if (isVisible) {
        this.ensureManualDdlSubscription();
      }
    })
    .bindSheet($$this.showDialog, this.buildDDLSheet(), {
      height: 420,
      showClose: true,
      dragBar: true,
    })
    }
  }

  @Builder
  buildDDLSheet() {
    Column() {
      Text(this.tr('learning.addDdl'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
        .margin({ bottom: 16 })

      TextInput({ placeholder: this.tr('learning.formTitle'), text: this.form.title })
        .width('100%')
        .height(44)
        .fontSize(14)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.border })
        .borderRadius(10)
        .padding({ left: 12 })
        .margin({ bottom: 10 })
        .onChange((v: string) => { this.form.title = v; })

      Row() {
        TextInput({ placeholder: this.tr('learning.formDate'), text: this.form.date })
          .width('48%')
          .height(44)
          .fontSize(14)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.border })
          .borderRadius(10)
          .padding({ left: 12 })
          .onChange((v: string) => { this.form.date = v; })

        Blank()

        TextInput({ placeholder: this.tr('learning.formTime'), text: this.form.time })
          .width('48%')
          .height(44)
          .fontSize(14)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.border })
          .borderRadius(10)
          .padding({ left: 12 })
          .onChange((v: string) => { this.form.time = v; })
      }
      .width('100%')
      .margin({ bottom: 10 })

      TextInput({ placeholder: this.tr('learning.formCourse'), text: this.form.course })
        .width('100%')
        .height(44)
        .fontSize(14)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.border })
        .borderRadius(10)
        .padding({ left: 12 })
        .margin({ bottom: 10 })
        .onChange((v: string) => { this.form.course = v; })

      TextInput({ placeholder: this.tr('learning.formNote'), text: this.form.note })
        .width('100%')
        .height(44)
        .fontSize(14)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.border })
        .borderRadius(10)
        .padding({ left: 12 })
        .margin({ bottom: 16 })
        .onChange((v: string) => { this.form.note = v; })

      Row() {
        Button(this.tr('common.cancel'))
          .type(ButtonType.Normal)
          .width('48%')
          .height(44)
          .fontSize(14)
          .fontColor(Theme.text)
          .backgroundColor(Theme.surfaceAlt)
          .borderRadius(10)
          .onClick(() => { this.showDialog = false; })

        Blank()

        Button(this.tr('learning.save'))
          .type(ButtonType.Normal)
          .width('48%')
          .height(44)
          .fontSize(14)
          .fontColor(Theme.textInvert)
          .backgroundColor(Theme.primary)
          .borderRadius(10)
          .enabled(!this.savingDDL)
          .opacity(this.savingDDL ? 0.6 : 1)
        .onClick(() => {
          if (this.savingDDL) {
            return;
          }
          if (this.form.title.trim() === '') {
            this.getUIContext().getPromptAction().showToast({ message: this.tr('learning.titleRequired'), duration: 2000 });
            return;
          }
          if (!this.isValidDate(this.form.date)) {
            this.getUIContext().getPromptAction().showToast({ message: this.tr('learning.ddl.dateInvalid'), duration: 2000 });
            return;
          }
          if (!this.isValidTime(this.form.time)) {
            this.getUIContext().getPromptAction().showToast({ message: this.tr('learning.ddl.timeInvalid'), duration: 2000 });
            return;
          }
          // 保存中禁用按钮，防重复提交；时间归一为 HH:mm 后落盘
          this.savingDDL = true;
          // 保存走共享 store（FR-019/FR-020：页面/AI/首页同一份数据）
          ManualDeadlineStore.append(
            this.form.title.trim(),
            this.form.date,
            this.normalizeTime(this.form.time),
            this.form.course.trim(),
            this.form.note.trim()
          ).then((md: ManualDeadline | undefined) => {
            this.savingDDL = false;
            if (md !== undefined) {
              this.manualDdls = ManualDeadlineStore.list();
              this.showDialog = false;
              this.form = new DeadlineForm();
              this.activeTab = '作业';
              this.getUIContext().getPromptAction().showToast({ message: this.tr('learning.ddl.savedToast'), duration: 2000 });
            } else {
              this.getUIContext().getPromptAction().showToast({ message: this.tr('learning.ddl.saveFailed'), duration: 2000 });
            }
          }).catch(() => {
            // 防御：store 未来若 reject，必须解除保存中状态，避免表单永久卡死
            this.savingDDL = false;
            this.getUIContext().getPromptAction().showToast({ message: this.tr('learning.ddl.saveFailed'), duration: 2000 });
          });
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .alignItems(HorizontalAlign.Start)
  }
}
