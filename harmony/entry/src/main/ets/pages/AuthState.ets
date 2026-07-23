/**
 * AuthState — 本地认证状态机
 * 5 种状态: idle | authenticating | two_factor | authenticated | error
 */
export enum AuthStatus {
  IDLE = 'idle',
  AUTHENTICATING = 'authenticating',
  TWO_FACTOR = 'two_factor',
  AUTHENTICATED = 'authenticated',
  ERROR = 'error'
}

export class TwoFactorMethod {
  type: string = '';
  label: string = '';
}

export class AuthState {
  status: AuthStatus = AuthStatus.IDLE;
  error: string = '';
  twoFactorMethods: TwoFactorMethod[] = [];
  selectedMethod: string = '';
  twoFactorHint: string = '';
}

export function getDefaultTwoFactorMethods(): TwoFactorMethod[] {
  const methods: TwoFactorMethod[] = [];
  const m1: TwoFactorMethod = new TwoFactorMethod();
  m1.type = 'wechat'; m1.label = '微信';
  methods.push(m1);
  const m2: TwoFactorMethod = new TwoFactorMethod();
  m2.type = 'mobile'; m2.label = '短信';
  methods.push(m2);
  const m3: TwoFactorMethod = new TwoFactorMethod();
  m3.type = 'totp'; m3.label = 'TOTP';
  methods.push(m3);
  return methods;
}
