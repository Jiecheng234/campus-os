const STORAGE_KEY_PREFIX: string = '@campusos/';

const COOKIE_STORAGE_KEY: string = STORAGE_KEY_PREFIX + 'webvpn_cookies';
const LEARNING_CACHE_KEY: string = STORAGE_KEY_PREFIX + 'learning_schedule_cache';
const CONVERSATIONS_KEY: string = STORAGE_KEY_PREFIX + 'ai_conversations';
const PERSONAL_EVENTS_KEY: string = STORAGE_KEY_PREFIX + 'personal_events';
const MANUAL_DEADLINES_KEY: string = STORAGE_KEY_PREFIX + 'manual_deadlines';
const AI_MEMORY_KEY: string = STORAGE_KEY_PREFIX + 'ai_memory';
const WORKFLOW_KEY: string = STORAGE_KEY_PREFIX + 'workflows';
const ACTION_AUDIT_KEY: string = STORAGE_KEY_PREFIX + 'action_audit';
/** AI 工具权限开关（ai-governance 特性：key 为权限键，value 为 true=禁用） */
const AI_DISABLED_PERMISSIONS_KEY: string = STORAGE_KEY_PREFIX + 'ai_disabled_permissions';
const SETTINGS_KEY: string = STORAGE_KEY_PREFIX + 'settings';
/** 是否曾显式选择过"信任此设备"（trust-device 特性：决定登录页开关默认值） */
const TRUST_CHOICE_MADE_KEY: string = STORAGE_KEY_PREFIX + 'trust_choice_made';
/** "待清除"标记（trust-device 特性：取消信任后置位，退出/启动兜底清除凭证后复位） */
const TRUST_PENDING_CLEAR_KEY: string = STORAGE_KEY_PREFIX + 'trust_pending_clear';

interface StorageKeysMap {
  WEBVPN_COOKIES: string;
  LEARNING_CACHE: string;
  AI_CONVERSATIONS: string;
  PERSONAL_EVENTS: string;
  MANUAL_DEADLINES: string;
  AI_MEMORY: string;
  WORKFLOWS: string;
  ACTION_AUDIT: string;
  AI_DISABLED_PERMISSIONS: string;
  SETTINGS: string;
  TRUST_CHOICE_MADE: string;
  TRUST_PENDING_CLEAR: string;
}

export const StorageKeys: StorageKeysMap = {
  'WEBVPN_COOKIES': COOKIE_STORAGE_KEY,
  'LEARNING_CACHE': LEARNING_CACHE_KEY,
  'AI_CONVERSATIONS': CONVERSATIONS_KEY,
  'PERSONAL_EVENTS': PERSONAL_EVENTS_KEY,
  'MANUAL_DEADLINES': MANUAL_DEADLINES_KEY,
  'AI_MEMORY': AI_MEMORY_KEY,
  'WORKFLOWS': WORKFLOW_KEY,
  'ACTION_AUDIT': ACTION_AUDIT_KEY,
  'AI_DISABLED_PERMISSIONS': AI_DISABLED_PERMISSIONS_KEY,
  'SETTINGS': SETTINGS_KEY,
  'TRUST_CHOICE_MADE': TRUST_CHOICE_MADE_KEY,
  'TRUST_PENDING_CLEAR': TRUST_PENDING_CLEAR_KEY,
};
