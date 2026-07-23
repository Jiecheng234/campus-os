import { AuthStatus, AuthState, CampusSession } from '../domain/AuthTypes';
import { LearningSnapshot } from '../domain/LearningTypes';
import { CampusSchedule, SemesterCalendar, PersonalEvent } from '../domain/ScheduleTypes';
import { ManualDeadline } from '../domain/DeadlineTypes';
import { Conversation, AIProviderConfig, ChatMessage } from '../domain/AIAgentTypes';
import { PreferencesStorage } from '../storage/PreferencesStorage';
import { StorageKeys } from '../storage/StorageKeys';

export enum DataSourceType {
  DEMO = 'demo',
  CAMPUS = 'campus',
}

export class AppSettings {
  locale: string = 'zh';
  demoMode: boolean = true;
  trustDevice: boolean = false;
  apiProvider: string = 'openai';
  apiKey: string = '';
}

export class StateManager {
  static authState: AuthState = new AuthState();
  static learningData: LearningSnapshot = new LearningSnapshot();
  static personalEvents: PersonalEvent[] = [];
  static campusSchedules: CampusSchedule[] = [];
  static semesterCalendar: SemesterCalendar = new SemesterCalendar();
  static manualDeadlines: ManualDeadline[] = [];
  static conversations: Conversation[] = [];
  static activeConversationId: string = '';
  static settings: AppSettings = new AppSettings();
  static dataSource: DataSourceType = DataSourceType.DEMO;
  static lastSyncedAt: string = '';

  static async init(): Promise<void> {
    const loaded: AppSettings | undefined = await PreferencesStorage.getJson<AppSettings>(StorageKeys.SETTINGS);
    if (loaded !== undefined) {
      StateManager.settings = loaded;
    }
  }

  static async saveSettings(): Promise<void> {
    await PreferencesStorage.setJson<AppSettings>(StorageKeys.SETTINGS, StateManager.settings);
  }

  static isDemoMode(): boolean {
    return StateManager.settings.demoMode;
  }

  static isAuthenticated(): boolean {
    return StateManager.authState.status === AuthStatus.AUTHENTICATED;
  }
}
