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

export class AgentContext {
  studentId: string = '';
  semesterName: string = '';
  todayDate: string = '';
  currentWeek: number = 0;
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
}
