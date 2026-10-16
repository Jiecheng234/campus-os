import { ActionPreview, ConfirmationSpec, ToolRisk, VerificationResult } from './ActionTypes';

export class AIProviderConfig {
  provider: string = 'openai';
  apiKey: string = '';
  baseURL: string = '';
  model: string = '';
  temperature: number = 0.7;
  maxTokens: number = 4096;
}

export class ChatMessage {
  id: string = '';
  role: string = '';
  content: string = '';
  timestamp: string = '';
  toolCalls: ToolCall[] = [];
  toolResults: ToolResult[] = [];
  /** 本条消息关联的工具轨迹（US3：对话内渲染轨迹卡片；旧数据缺省为空） */
  traces: ToolTrace[] = [];
}

export class ToolCall {
  id: string = '';
  name: string = '';
  parameters: string = '';
}

export class ToolResult {
  callId: string = '';
  content: string = '';
}

export class Conversation {
  id: string = '';
  title: string = '';
  messages: ChatMessage[] = [];
  createdAt: string = '';
  updatedAt: string = '';
  providerConfig: AIProviderConfig = new AIProviderConfig();
}

/**
 * Agent 个人备忘日程（日期化模型，区别于教务周课表）。
 * 对齐 RN personalEvents 语义：用户自建、可增删、按日期存放。
 */
export class AgentPersonalEvent {
  id: string = '';
  /** YYYY-MM-DD */
  date: string = '';
  title: string = '';
  /** HH:mm */
  startTime: string = '';
  /** HH:mm */
  endTime: string = '';
  location: string = '';
  note: string = '';
}

export class AgentContext {
  studentId: string = '';
  semesterName: string = '';
  todayDate: string = '';
  currentWeek: number = 0;
  /** 扩展字段（US4：上下文摘要注入系统提示） */
  memorySummary: string = '';
  weatherSummary: string = '';
  todaySummary: string = '';
  scheduleSummary: string = '';
  ddlSummary: string = '';
  courseSummary: string = '';
  demoMode: boolean = false;
}

export class AIMemory {
  key: string = '';
  value: string = '';
  updatedAt: string = '';
}

export class ToolTrace {
  callId: string = '';
  name: string = '';
  params: string = '';
  result: string = '';
  timestamp: string = '';
  success: boolean = false;
  /** 扩展字段（US3 轨迹卡片展示） */
  title: string = '';
  status: string = '';
  detail: string = '';
}

/**
 * Agent 工具定义（注册表单元；对齐 RN AgentTool 契约）。
 * - 只读工具：requiresConfirmation=false，仅 run。
 * - 可逆写工具：requiresConfirmation=true，治理链 dryRun→确认→run→verify。
 * - parametersJson 为 OpenAI function parameters 的 JSON Schema 文本。
 * - run 入参/出参均为 Record<string, Object>（JSON 兼容的宽松键值结构）。
 */
export class AgentToolDef {
  name: string = '';
  title: string = '';
  description: string = '';
  parametersJson: string = '{}';
  risk: ToolRisk = ToolRisk.NONE;
  permission: string = '';
  requiresConfirmation: boolean = false;
  /** 写工具 dry-run：产出预览（不执行） */
  dryRun: ((args: Record<string, Object>) => Promise<ActionPreview>) | undefined = undefined;
  /** 写工具执行后验证 */
  verify: ((args: Record<string, Object>, result: Record<string, Object>) => Promise<VerificationResult>) | undefined = undefined;
  /** 参数概要（轨迹/审计展示用；需自行脱敏） */
  summarize: ((args: Record<string, Object>) => string) | undefined = undefined;
  /** 确认弹窗文案构造 */
  confirmPrompt: ((args: Record<string, Object>, preview: ActionPreview | undefined) => ConfirmationSpec) | undefined = undefined;
  /** 工具执行：返回结构化结果（error 字段视为失败） */
  run: (args: Record<string, Object>) => Promise<Record<string, Object>> =
    async (args: Record<string, Object>): Promise<Record<string, Object>> => {
      const r: Record<string, Object> = { 'error': '工具未实现' };
      return r;
    };
}
