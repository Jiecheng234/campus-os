/**
 * ============================================================================
 * CourseRegSelfTest — 选课系统纯函数 fixture 自测（T03 T009）
 * ============================================================================
 *
 * 【边界】只测纯解析/校验/分类函数：内嵌 fixture，不发起网络请求、
 * 不依赖登录态、不依赖 SessionManager 单例。启动自检由
 * Phase4SelfTest.runPhase4SelfTest() 调用本文件的 runCourseRegSelfTest()。
 *
 * 【fixture 约定】HTML 片段取自 RN 线上响应结构（node-html-parser 选择器
 * 语义改写为正则后的等价断言）；每个用户故事新增 fixture 时在对应
 * runXxxTests() 中追加，不新建文件。
 * ============================================================================
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  CR_WEBVPN_TITLE_MARK,
  CR_SM2_MARK,
  CR_TIMEOUT_MARK,
  stripHtml,
  decodeHtmlEntities,
  extractFormToken,
  extractShowMsg,
  isLoginPage,
  extractBaseSemester,
  parseSemesters,
  parseSelected,
  parseSelectedPage,
  parseRemaining,
  parseRemainingPage,
  isSelectedPage,
  isRemainingPage,
  redactSensitive,
  willStringToNumber,
} from './CourseRegHtml';
import {
  SelectCourseParams,
  DropCourseParams,
  CourseRegPriority,
  CourseRegErrorCode,
  courseRegFieldKey,
  courseRegSaveMethod,
} from '../domain/CourseRegTypes';
import {
  classifyCourseRegMsg,
  CourseRegMsgVerdict,
  parseCrUrlToWebVPN,
  validateSelectCourseParams,
  validateDropCourseParams,
} from '../services/campus/CourseRegService';

const DOMAIN: number = 0xCAFE;
const TAG: string = 'CourseRegTest';

class CourseRegTestRunner {
  static passed: number = 0;
  static failed: number = 0;

  static log(msg: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', msg);
  }

  static test(name: string, fn: () => boolean): void {
    let result: boolean = false;
    try {
      result = fn();
    } catch (e) {
      CourseRegTestRunner.logFail(name, 'Exception: ' + (e instanceof Error ? e.message : 'unknown'));
      return;
    }
    if (result) {
      hilog.info(DOMAIN, TAG, 'PASS: %{public}s', name);
      CourseRegTestRunner.passed = CourseRegTestRunner.passed + 1;
    } else {
      CourseRegTestRunner.logFail(name, 'Assertion failed');
    }
  }

  static logFail(name: string, detail: string): void {
    hilog.error(DOMAIN, TAG, 'FAIL: %{public}s — %{public}s', name, detail);
    CourseRegTestRunner.failed = CourseRegTestRunner.failed + 1;
  }
}

/** 自测汇总（passed/failed；Phase4SelfTest 汇总日志用） */
export class CourseRegSelfTestSummary {
  passed: number = 0;
  failed: number = 0;
}

/** 启动自检入口：返回 passed/failed 汇总（failed=0 表示全部通过） */
export function runCourseRegSelfTest(): CourseRegSelfTestSummary {
  CourseRegTestRunner.passed = 0;
  CourseRegTestRunner.failed = 0;

  CourseRegTestRunner.log('===== CourseReg Self-Test Start =====');

  runHtmlPrimitiveTests();
  runSemesterParseTests();
  runSelectedCourseParseTests();
  runRemainingParseTests();
  runUrlAndMappingTests();
  runSelectCourseFixtureTests();
  runDropCourseFixtureTests();

  const total: number = CourseRegTestRunner.passed + CourseRegTestRunner.failed;
  CourseRegTestRunner.log(`===== CourseReg Self-Test Done: ${CourseRegTestRunner.passed}/${total} passed, ${CourseRegTestRunner.failed} failed =====`);
  const summary: CourseRegSelfTestSummary = new CourseRegSelfTestSummary();
  summary.passed = CourseRegTestRunner.passed;
  summary.failed = CourseRegTestRunner.failed;
  return summary;
}

/** T003 共享文本与表单原语 fixture */
function runHtmlPrimitiveTests(): void {
  CourseRegTestRunner.test('stripHtml removes tags, entities and extra spaces', () => {
    // &amp; 前后都放 &nbsp;：实体解码为 " & "，与期望值逐字符一致
    return stripHtml('<p>数据结构&nbsp;&amp;&nbsp;算法</p>') === '数据结构 & 算法';
  });

  CourseRegTestRunner.test('stripHtml keeps plain text unchanged', () => {
    return stripHtml('线性代数(2)') === '线性代数(2)';
  });

  CourseRegTestRunner.test('decodeHtmlEntities decodes named and numeric entities', () => {
    return decodeHtmlEntities('a&lt;b&gt;c&quot;d&#39;e&#20013;f') === 'a<b>c"d\'e中f';
  });

  CourseRegTestRunner.test('extractFormToken value-after-name order', () => {
    const html: string = '<input type="hidden" name="token" value="ABC123">';
    return extractFormToken(html) === 'ABC123';
  });

  CourseRegTestRunner.test('extractFormToken value-before-name order', () => {
    const html: string = '<input value="XYZ789" name="token" type="hidden">';
    return extractFormToken(html) === 'XYZ789';
  });

  CourseRegTestRunner.test('extractFormToken missing token input', () => {
    const html: string = '<input type="text" name="p_kch" value="2048012X">';
    return extractFormToken(html) === '';
  });

  CourseRegTestRunner.test('extractShowMsg picks first message', () => {
    const html: string = '<script>showMsg("选课成功");</script><script>showMsg("other");</script>';
    return extractShowMsg(html) === '选课成功';
  });

  CourseRegTestRunner.test('extractShowMsg missing returns empty', () => {
    return extractShowMsg('<html><body>no script here</body></html>') === '';
  });

  CourseRegTestRunner.test('isLoginPage detects webvpn title', () => {
    return isLoginPage('<html><head><title>清华大学WebVPN</title></head></html>') === true;
  });

  CourseRegTestRunner.test('isLoginPage detects sm2 login form', () => {
    const html: string = '<input type="hidden" id="sm2publicKey" value="k">';
    return isLoginPage(html) === true;
  });

  CourseRegTestRunner.test('isLoginPage detects sm2 with single quotes', () => {
    const html: string = "<input type='hidden' id='sm2publicKey' value='k'>";
    return isLoginPage(html) === true;
  });

  CourseRegTestRunner.test('isLoginPage detects timeout page', () => {
    return isLoginPage('<div>用户登陆超时或访问内容不存在</div>') === true;
  });

  CourseRegTestRunner.test('isLoginPage normal page returns false', () => {
    const html: string = '<html><head><title>选课系统</title></head><body>main</body></html>';
    return isLoginPage(html) === false;
  });

  CourseRegTestRunner.test('login page marks are raw constants', () => {
    return CR_WEBVPN_TITLE_MARK === '<title>清华大学WebVPN</title>'
      && CR_SM2_MARK === 'sm2publicKey'
      && CR_TIMEOUT_MARK === '用户登陆超时或访问内容不存在';
  });

  CourseRegTestRunner.test('redactSensitive masks urls and token assignments', () => {
    return redactSensitive('跳转 https://webvpn.tsinghua.edu.cn/https/abc/xkBks.do 失败') === '跳转 <url> 失败'
      && redactSensitive('token=abcdef12345') === 'token=<redacted>'
      && redactSensitive('XSRF-TOKEN=abc123; path=/') === 'XSRF-TOKEN=<redacted> path=/';
  });

  CourseRegTestRunner.test('redactSensitive masks long hex tokens and 10-digit ids', () => {
    // webvpn 长十六进制 token（≥32 位）与 10 位学号形态数字分别归一
    return redactSensitive('77726476706e69737468656265737421f9f9479369247b') === '<token>'
      && redactSensitive('学号 2023011234 已登录') === '学号 <id> 已登录';
  });

  CourseRegTestRunner.test('redactSensitive keeps course ids and normal text unchanged', () => {
    // 8 位含字母课程号、课序号、普通中文文案不受影响
    return redactSensitive('课程号 2048012X 课序号 01 选课成功') === '课程号 2048012X 课序号 01 选课成功';
  });
}

/** T010/T012 学期解析 fixture（US1） */
function runSemesterParseTests(): void {
  // 主页面片段：含 showTree 学期标记（RN 线上结构）
  const mainHtml: string = '<html><body><a href="xkBks.vxkBksXkbBs.do?m=showTree&p_xnxq=2024-2025-2">'
    + '学期树</a></body></html>';
  // 树页面片段：占位空选项 + 两个正常选项（含 selected 属性与实体）
  const treeHtml: string = '<select id="xnxq"><option value="">请选择学期</option>'
    + '<option value="2024-2025-1">2024-2025-1 秋季学期</option>'
    + '<option value="2024-2025-2" selected>2024-2025-2&#160;春季学期</option>'
    + '</select>';

  CourseRegTestRunner.test('extractBaseSemester finds showTree semester', () => {
    return extractBaseSemester(mainHtml) === '2024-2025-2';
  });

  CourseRegTestRunner.test('extractBaseSemester missing marker returns empty', () => {
    return extractBaseSemester('<html><body>main page without tree link</body></html>') === '';
  });

  CourseRegTestRunner.test('parseSemesters parses options and drops empty values', () => {
    const list = parseSemesters(mainHtml, treeHtml);
    // &#160; 解码为 \u00a0 后被 \s+ 归一化为普通空格
    return list.length === 2
      && list[0].id === '2024-2025-1' && list[0].name === '2024-2025-1 秋季学期'
      && list[1].id === '2024-2025-2' && list[1].name === '2024-2025-2 春季学期';
  });

  CourseRegTestRunner.test('parseSemesters all-empty options returns empty list', () => {
    const emptyTree: string = '<select><option value="">请选择学期</option></select>';
    return parseSemesters(mainHtml, emptyTree).length === 0;
  });

  CourseRegTestRunner.test('parseSemesters skips options with empty names', () => {
    const nameTree: string = '<select><option value="2024-2025-1"></option>'
      + '<option value="2024-2025-2">2024-2025-2 春季学期</option></select>';
    const list = parseSemesters(mainHtml, nameTree);
    return list.length === 1 && list[0].id === '2024-2025-2';
  });

  CourseRegTestRunner.test('parseSemesters all-empty names returns empty list', () => {
    const nameTree: string = '<select><option value="2024-2025-1"></option>'
      + '<option value="2024-2025-2">   </option></select>';
    return parseSemesters(mainHtml, nameTree).length === 0;
  });

  CourseRegTestRunner.test('parseSemesters missing base semester returns empty list', () => {
    return parseSemesters('<html><body>no marker</body></html>', treeHtml).length === 0;
  });
}

/** T013/T015 已选课程解析 fixture（US2） */
function runSelectedCourseParseTests(): void {
  // 行内容：序号0 类别1 志愿2 课程号3 名称4 课序号5 时间6 教师7 学分8 二级9
  const row1: string = '<tr><td class="tdd2">1</td><td class="tdd2">必修</td>'
    + '<td class="tdd2">第一志愿</td><td class="tdd2">2048012X</td>'
    + '<td class="tdd2">线性代数(2)</td><td class="tdd2">01</td>'
    + '<td class="tdd2">一 1-2节</td><td class="tdd2">张三</td>'
    + '<td class="tdd2">3</td><td class="tdd2">否</td></tr>';
  const row2: string = '<tr><td class="tdd2">2</td><td class="tdd2">限选</td>'
    + '<td class="tdd2">第二志愿</td><td class="tdd2">2070003X</td>'
    + '<td class="tdd2">数据结构</td><td class="tdd2">02</td>'
    + '<td class="tdd2">三 3-4节</td><td class="tdd2">李四</td>'
    + '<td class="tdd2">4</td><td class="tdd2">是</td></tr>';
  // 缺列坏行（仅 5 列）：应被跳过
  const badRow: string = '<tr><td class="tdd2">x</td><td>y</td><td>z</td><td>u</td><td>v</td></tr>';
  // 志愿文本非一/二志愿：映射 3
  const row3: string = '<tr><td class="tdd2">3</td><td class="tdd2">任选</td>'
    + '<td class="tdd2">第三志愿</td><td class="tdd2">1070001X</td>'
    + '<td class="tdd2">西方哲学史</td><td class="tdd2">01</td>'
    + '<td class="tdd2">五 6-7节</td><td class="tdd2">王五</td>'
    + '<td class="tdd2">2</td><td class="tdd2">否</td></tr>';

  CourseRegTestRunner.test('parseSelected container-structure rows with full fields', () => {
    const page: string = '<table class="trr2"><thead><tr><th>序号</th></tr></thead><tbody>'
      + row1 + row2 + '</tbody></table>';
    const list = parseSelected(page);
    return list.length === 2
      && list[0].type === '必修' && list[0].will === 1
      && list[0].id === '2048012X' && list[0].name === '线性代数(2)'
      && list[0].seq === '01' && list[0].time === '一 1-2节'
      && list[0].teacher === '张三' && list[0].credit === 3
      && list[0].secondary === false
      && list[1].will === 2 && list[1].secondary === true && list[1].credit === 4;
  });

  CourseRegTestRunner.test('parseSelected tr.trr2 direct-row structure', () => {
    const page: string = '<tbody>' + '<tr class="trr2">'
      + '<td>1</td><td>必修</td><td>第一志愿</td><td>2048012X</td>'
      + '<td>线性代数(2)</td><td>01</td><td>一 1-2节</td><td>张三</td>'
      + '<td>3</td><td>否</td>' + '</tr></tbody>';
    const list = parseSelected(page);
    return list.length === 1 && list[0].id === '2048012X' && list[0].name === '线性代数(2)';
  });

  CourseRegTestRunner.test('parseSelected skips rows with fewer than 9 cells', () => {
    const page: string = '<table class="trr2"><tbody>' + badRow + row1 + '</tbody></table>';
    const list = parseSelected(page);
    return list.length === 1 && list[0].id === '2048012X';
  });

  CourseRegTestRunner.test('parseSelected empty page returns empty list', () => {
    return parseSelected('<html><body><p>没有已选课程</p></body></html>').length === 0;
  });

  CourseRegTestRunner.test('parseSelected maps unknown will text to 3', () => {
    const page: string = '<table class="trr2"><tbody>' + row3 + '</tbody></table>';
    const list = parseSelected(page);
    return list.length === 1 && list[0].will === 3 && list[0].name === '西方哲学史';
  });

  CourseRegTestRunner.test('parseSelectedPage reports skipped bad-row count', () => {
    const page: string = '<table class="trr2"><tbody>' + badRow + row1 + '</tbody></table>';
    const parsed = parseSelectedPage(page);
    return parsed.recognized === true && parsed.skipped === 1 && parsed.courses.length === 1;
  });

  CourseRegTestRunner.test('parseSelected container truncates at own closing tag', () => {
    // trr2 容器在自身 </table> 处截断：后续无关表格的行不得被当数据
    const page: string = '<table class="trr2"><tbody>' + row1 + '</tbody></table>'
      + '<table><tbody>' + row2 + '</tbody></table>';
    const list = parseSelected(page);
    return list.length === 1 && list[0].id === '2048012X';
  });

  CourseRegTestRunner.test('parseSelected uppercase TD cells parsed in container', () => {
    // 容器分支的数据行 gate 须大小写不敏感：<TD> 行不得因纯 th 判定被跳过
    const page: string = '<table class="trr2"><tbody><TR>'
      + '<TD>1</TD><TD>必修</TD><TD>第一志愿</TD><TD>2048012X</TD>'
      + '<TD>线性代数(2)</TD><TD>01</TD><TD>一 1-2节</TD><TD>张三</TD>'
      + '<TD>3</TD><TD>否</TD></TR></tbody></table>';
    const list = parseSelected(page);
    return list.length === 1 && list[0].id === '2048012X' && list[0].teacher === '张三';
  });

  CourseRegTestRunner.test('parseSelected uppercase closing tag still truncates container', () => {
    // 自身闭合标签为 </TBODY></TABLE> 大写形态：截断判定须大小写不敏感，
    // 不得把后续无关表格的行当数据
    const page: string = '<table class="trr2"><tbody>' + row1 + '</TBODY></TABLE>'
      + '<table><tbody>' + row2 + '</tbody></table>';
    const list = parseSelected(page);
    return list.length === 1 && list[0].id === '2048012X';
  });

  CourseRegTestRunner.test('parseSelected nested same-name table not truncated by inner close', () => {
    // trr2 容器内嵌套同名 <table>：截断须按同名标签深度归零判定，
    // 不得在内层 </table> 处提前截断丢失后续行（row2）
    const page: string = '<table class="trr2"><tbody>' + row1
      + '<table><tr><td>装饰</td></tr></table>'
      + row2 + '</tbody></table>';
    const list = parseSelected(page);
    return list.length === 2 && list[0].id === '2048012X' && list[1].id === '2070003X';
  });

  CourseRegTestRunner.test('parseSelectedPage 200 error page not recognized', () => {
    const errPage: string = '<html><head><title>错误</title></head><body>'
      + '<h1>Service Unavailable</h1><p>网关超时，请稍后重试</p></body></html>';
    const parsed = parseSelectedPage(errPage);
    return parsed.recognized === false && isSelectedPage(errPage) === false;
  });

  CourseRegTestRunner.test('isSelectedPage token-only error page not recognized', () => {
    // 仅含 name="token" 表单（无 trr2/yxSearchTab/tokenPriFlag 强结构标记）
    // 的错误页不得识别为合法已选页：token 只是辅助信号
    const errPage: string = '<html><body><form>'
      + '<input type="hidden" name="token" value="X">'
      + '</form><h1>系统错误</h1><p>请稍后重试</p></body></html>';
    return isSelectedPage(errPage) === false
      && parseSelectedPage(errPage).recognized === false;
  });

  CourseRegTestRunner.test('parseSelectedPage legit empty page recognized with empty list', () => {
    // 合法空已选页：含 token 表单（yxSearchTab 页面结构），无 trr2 行
    const emptyPage: string = '<html><body><form>'
      + '<input type="hidden" name="token" value="X">'
      + '</form><script>var tokenPriFlag = "yx";</script></body></html>';
    const parsed = parseSelectedPage(emptyPage);
    return parsed.recognized === true && parsed.courses.length === 0 && parsed.skipped === 0;
  });

  CourseRegTestRunner.test('willStringToNumber mapping table', () => {
    return willStringToNumber('第一志愿') === 1
      && willStringToNumber('第二志愿') === 2
      && willStringToNumber('第三志愿') === 3
      && willStringToNumber('') === 3;
  });
}

/** T016/T018 课余量搜索解析 fixture（US3） */
function runRemainingParseTests(): void {
  // ≥8 列行（含队列列）：id=0 seq=1 name=2 capacity=3 remaining=4 queue=5 teacher=6 time=7
  const queueRow: string = '<tr class="trr2">'
    + '<td>2048012X</td><td>1</td><td>线性代数(2)</td><td>120</td><td>15</td>'
    + '<td>3</td><td>张三</td><td>一 1-2节</td></tr>';
  // <8 列行（不含队列列）：teacher=5 time=6，queue=0
  const noQueueRow: string = '<tr class="trr2">'
    + '<td>1070001X</td><td>2</td><td>西方哲学史</td><td>80</td><td>0</td>'
    + '<td>王五</td><td>五 6-7节</td></tr>';
  // <6 列坏行：跳过
  const badRow: string = '<tr class="trr2"><td>a</td><td>b</td><td>c</td></tr>';
  // 分页脚注（RN p.yeM 正则文案）
  const footer: string = '<p class="yeM">第 1 页 / 共 3 页（共 258 条记录）</p>';
  const footerComma: string = '<p class="yeM">第 2 页 / 共 22 页（共 1,258 条记录）</p>';

  CourseRegTestRunner.test('parseRemaining row with queue column', () => {
    const page: string = '<html><body><table>' + queueRow + '</table>' + footer + '</body></html>';
    const result = parseRemaining(page);
    return result.courses.length === 1
      && result.courses[0].id === '2048012X'
      && result.courses[0].seq === 1
      && result.courses[0].name === '线性代数(2)'
      && result.courses[0].capacity === 120
      && result.courses[0].remaining === 15
      && result.courses[0].queue === 3
      && result.courses[0].teacher === '张三'
      && result.courses[0].time === '一 1-2节';
  });

  CourseRegTestRunner.test('parseRemaining row without queue column', () => {
    const page: string = '<html><body><table>' + noQueueRow + '</table>' + footer + '</body></html>';
    const result = parseRemaining(page);
    return result.courses.length === 1
      && result.courses[0].queue === 0
      && result.courses[0].teacher === '王五'
      && result.courses[0].time === '五 6-7节'
      && result.courses[0].remaining === 0;
  });

  CourseRegTestRunner.test('parseRemaining parses p.yeM footer pagination', () => {
    const page: string = '<html><body><table>' + queueRow + '</table>' + footer + '</body></html>';
    const result = parseRemaining(page);
    return result.currPage === 1 && result.totalPage === 3 && result.totalCount === 258;
  });

  CourseRegTestRunner.test('parseRemaining footer with thousand separators', () => {
    const page: string = '<html><body>' + footerComma + '</body></html>';
    const result = parseRemaining(page);
    return result.currPage === 2 && result.totalPage === 22 && result.totalCount === 1258;
  });

  CourseRegTestRunner.test('parseRemaining missing footer falls back to 1/1/0', () => {
    const page: string = '<html><body><table>' + noQueueRow + '</table></body></html>';
    const result = parseRemaining(page);
    return result.currPage === 1 && result.totalPage === 1 && result.totalCount === 0
      && result.courses.length === 1;
  });

  CourseRegTestRunner.test('parseRemaining skips rows with fewer than 6 cells', () => {
    const page: string = '<html><body><table>' + badRow + noQueueRow + '</table>' + footer + '</body></html>';
    const result = parseRemaining(page);
    return result.courses.length === 1 && result.courses[0].id === '1070001X';
  });

  CourseRegTestRunner.test('parseRemaining six-column row has time bounds guard', () => {
    // 恰好 6 列（无队列列）：teacher=第5列、time 越界保护为空串
    const sixColRow: string = '<tr class="trr2">'
      + '<td>2048012X</td><td>1</td><td>线性代数(2)</td><td>120</td><td>15</td>'
      + '<td>张三</td></tr>';
    const page: string = '<html><body><table>' + sixColRow + '</table>' + footer + '</body></html>';
    const result = parseRemaining(page);
    return result.courses.length === 1
      && result.courses[0].teacher === '张三'
      && result.courses[0].time === ''
      && result.courses[0].queue === 0;
  });

  CourseRegTestRunner.test('parseRemainingPage reports skipped bad-row count', () => {
    const page: string = '<html><body><table>' + badRow + noQueueRow + '</table>' + footer + '</body></html>';
    const parsed = parseRemainingPage(page);
    return parsed.recognized === true && parsed.skipped === 1
      && parsed.result.courses.length === 1;
  });

  CourseRegTestRunner.test('parseRemainingPage 200 error page not recognized', () => {
    const errPage: string = '<html><head><title>错误</title></head><body>'
      + '<h1>Service Unavailable</h1><p>网关超时，请稍后重试</p></body></html>';
    const parsed = parseRemainingPage(errPage);
    return parsed.recognized === false && isRemainingPage(errPage) === false;
  });

  CourseRegTestRunner.test('isRemainingPage pathContent-only error page not recognized', () => {
    // 仅回显 pathContent/"课余量" 隐藏域（无 yeM 分页脚注/trr2 强结构标记）
    // 的错误页不得识别为合法搜索结果页：pathContent 只是辅助信号
    const errPage: string = '<html><body><form>'
      + '<input type="hidden" name="pathContent" value="课余量查询">'
      + '</form><h1>系统错误</h1></body></html>';
    return isRemainingPage(errPage) === false
      && parseRemainingPage(errPage).recognized === false;
  });

  CourseRegTestRunner.test('parseRemainingPage legit empty result recognized', () => {
    // 合法空搜索结果：p.yeM 脚注"共 0 条记录"，无 trr2 行
    const emptyPage: string = '<html><body>'
      + '<p class="yeM">第 1 页 / 共 1 页（共 0 条记录）</p></body></html>';
    const parsed = parseRemainingPage(emptyPage);
    return parsed.recognized === true
      && parsed.result.courses.length === 0
      && parsed.result.totalCount === 0
      && parsed.result.currPage === 1
      && parsed.result.totalPage === 1;
  });
}

/** 评审补充：URL 包装与优先级映射纯函数 fixture */
function runUrlAndMappingTests(): void {
  CourseRegTestRunner.test('courseRegFieldKey mapping table', () => {
    return courseRegFieldKey('bx') === 'bxk'
      && courseRegFieldKey('xx') === 'xxk'
      && courseRegFieldKey('rx') === 'rx'
      && courseRegFieldKey('ty') === 'rxTy';
  });

  CourseRegTestRunner.test('courseRegSaveMethod mapping table', () => {
    return courseRegSaveMethod('bx') === 'saveBxKc'
      && courseRegSaveMethod('xx') === 'saveXxKc'
      && courseRegSaveMethod('rx') === 'saveRxKc'
      && courseRegSaveMethod('ty') === 'saveTyKc';
  });

  CourseRegTestRunner.test('parseCrUrlToWebVPN wraps domain host', () => {
    const wrapped: string = parseCrUrlToWebVPN('http://zhjw.cic.tsinghua.edu.cn/jw_xk.aspx');
    return wrapped === 'https://webvpn.tsinghua.edu.cn/http/77726476706e69737468656265737421eaff4b8b69336153301c9aa596522b20bc86e6e559a9b290/jw_xk.aspx';
  });

  CourseRegTestRunner.test('parseCrUrlToWebVPN wraps ip host with port', () => {
    const wrapped: string = parseCrUrlToWebVPN('http://166.111.14.8:8080/xk/main');
    return wrapped === 'https://webvpn.tsinghua.edu.cn/http-8080/77726476706e69737468656265737421a1a117d27661391e2f5cc7f4/xk/main';
  });

  CourseRegTestRunner.test('parseCrUrlToWebVPN passthrough cases', () => {
    return parseCrUrlToWebVPN('https://webvpn.tsinghua.edu.cn/https/abc/')
      === 'https://webvpn.tsinghua.edu.cn/https/abc/'
      && parseCrUrlToWebVPN('http://unknown.example.com/path') === 'http://unknown.example.com/path';
  });
}

/** T019/T020 选课 fixture（US4）：token 提取两种属性顺序、成功/拒绝/缺失消息、非法优先级本地拒绝 */
function runSelectCourseFixtureTests(): void {
  // 预检页 token 输入框：属性顺序无关
  const preflightA: string = '<form><input type="hidden" name="token" value="TOK123">'
    + '<input type="text" name="p_kch"></form>';
  const preflightB: string = '<form><input value="TOK456" name="token" type="hidden"></form>';

  CourseRegTestRunner.test('select fixture: token input value-after-name order', () => {
    return extractFormToken(preflightA) === 'TOK123';
  });

  CourseRegTestRunner.test('select fixture: token input value-before-name order', () => {
    return extractFormToken(preflightB) === 'TOK456';
  });

  CourseRegTestRunner.test('select fixture: success message classified as SUCCESS', () => {
    return classifyCourseRegMsg('选课成功') === CourseRegMsgVerdict.SUCCESS;
  });

  CourseRegTestRunner.test('select fixture: failure message classified as REJECTED', () => {
    return classifyCourseRegMsg('选课失败：课程容量已满') === CourseRegMsgVerdict.REJECTED;
  });

  CourseRegTestRunner.test('select fixture: fail word wins over success word', () => {
    // 服务端"成功提交但…冲突"类文案按拒绝处理（RD-08：只认明确成功）
    return classifyCourseRegMsg('选课成功，但与已选课程冲突') === CourseRegMsgVerdict.REJECTED;
  });

  CourseRegTestRunner.test('select fixture: ambiguous message classified as UNCONFIRMED', () => {
    return classifyCourseRegMsg('系统处理中，请稍后查询') === CourseRegMsgVerdict.UNCONFIRMED;
  });

  CourseRegTestRunner.test('select fixture: missing showMsg in select response', () => {
    return extractShowMsg('<html><body><div>no script</div></body></html>') === '';
  });

  CourseRegTestRunner.test('select fixture: unsupported priority rejected locally', () => {
    const params: SelectCourseParams = new SelectCourseParams();
    params.semester = '2024-2025-2';
    params.priority = 'xwk';
    params.courseId = '2048012X';
    params.courseSeq = '01';
    params.will = 1;
    return validateSelectCourseParams(params) === CourseRegErrorCode.UNSUPPORTED_PRIORITY;
  });

  CourseRegTestRunner.test('select fixture: empty priority rejected as invalid param', () => {
    const params: SelectCourseParams = new SelectCourseParams();
    params.semester = '2024-2025-2';
    params.priority = '';
    params.courseId = '2048012X';
    params.courseSeq = '01';
    params.will = 1;
    return validateSelectCourseParams(params) === CourseRegErrorCode.INVALID_PARAM;
  });

  CourseRegTestRunner.test('select fixture: valid params pass validation', () => {
    const params: SelectCourseParams = new SelectCourseParams();
    params.semester = '2024-2025-2';
    params.priority = CourseRegPriority.TY;
    params.courseId = '2048012X';
    params.courseSeq = '01';
    params.will = 2;
    return validateSelectCourseParams(params) === null;
  });
}

/** T021/T022 退课 fixture（US5）：已选页 token、退课成功/拒绝消息、缺失 showMsg */
function runDropCourseFixtureTests(): void {
  // 已选页（yxSearchTab）含 token 输入框
  const yxPage: string = '<html><body><form>'
    + '<input type="hidden" name="token" value="YXTOK789">'
    + '<table class="trr2"><tbody><tr><td>1</td><td>必修</td><td>第一志愿</td>'
    + '<td>2048012X</td><td>线性代数(2)</td><td>01</td><td>一 1-2节</td>'
    + '<td>张三</td><td>3</td><td>否</td></tr></tbody></table></form></body></html>';

  CourseRegTestRunner.test('drop fixture: selected page token extraction', () => {
    return extractFormToken(yxPage) === 'YXTOK789';
  });

  CourseRegTestRunner.test('drop fixture: drop success message classified as SUCCESS', () => {
    return classifyCourseRegMsg('退课成功') === CourseRegMsgVerdict.SUCCESS;
  });

  CourseRegTestRunner.test('drop fixture: drop failure message classified as REJECTED', () => {
    return classifyCourseRegMsg('退课失败：不能删除必修课程') === CourseRegMsgVerdict.REJECTED;
  });

  CourseRegTestRunner.test('drop fixture: missing showMsg in drop response', () => {
    return extractShowMsg('<html><body>plain response</body></html>') === '';
  });

  CourseRegTestRunner.test('drop fixture: missing fields rejected as invalid param', () => {
    const params: DropCourseParams = new DropCourseParams();
    params.semester = '2024-2025-2';
    params.courseId = '';
    params.courseSeq = '01';
    return validateDropCourseParams(params) === CourseRegErrorCode.INVALID_PARAM;
  });

  CourseRegTestRunner.test('drop fixture: valid params pass validation', () => {
    const params: DropCourseParams = new DropCourseParams();
    params.semester = '2024-2025-2';
    params.courseId = '2048012X';
    params.courseSeq = '01';
    return validateDropCourseParams(params) === null;
  });
}
