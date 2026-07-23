export enum AuthStatus {
  IDLE = 'idle',
  AUTHENTICATING = 'authenticating',
  TWO_FACTOR = 'two_factor',
  AUTHENTICATED = 'authenticated',
  ERROR = 'error'
}

export class TwoFactorApproach {
  type: string = '';
  label: string = '';
}

export class AuthState {
  status: AuthStatus = AuthStatus.IDLE;
  error: string = '';
  twoFactorApproaches: TwoFactorApproach[] = [];
  selectedTwoFactor: string = '';
}

export class CampusCredentials {
  studentId: string = '';
  password: string = '';
  fingerprint: string = '';
}

export class CampusSession {
  isAuthenticated: boolean = false;
  studentId: string = '';
  displayName: string = '';
  authenticatedAt: string = '';
  webvpnReady: boolean = false;
  cookiePool: string = '';
}
