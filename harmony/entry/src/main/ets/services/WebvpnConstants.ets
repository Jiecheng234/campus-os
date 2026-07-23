export const WEBVPN_BASE_URL: string = 'https://webvpn.tsinghua.edu.cn';
export const WEBVPN_OAUTH_LOGIN_URL: string = `${WEBVPN_BASE_URL}/login`;
export const WEBVPN_ROAMING_URL: string = `${WEBVPN_BASE_URL}/portal/roaming.htm`;

export const SUBSYSTEM_INFO: string = 'info';
export const SUBSYSTEM_LEARN: string = 'learn';
export const SUBSYSTEM_ID: string = 'id';

export function getSubsystemUrl(subsystem: string): string {
  if (subsystem === SUBSYSTEM_INFO) {
    return `${WEBVPN_BASE_URL}/http/77726476706e69737468656265737421.../`;
  }
  if (subsystem === SUBSYSTEM_LEARN) {
    return `${WEBVPN_BASE_URL}/http/77726476706e69737468656265737421.../learn/`;
  }
  if (subsystem === SUBSYSTEM_ID) {
    return `${WEBVPN_BASE_URL}/http/77726476706e69737468656265737421.../id/`;
  }
  return '';
}

export const CAMPUS_ENDPOINTS: Record<string, string> = {
  'schedule': `${WEBVPN_BASE_URL}/http/learn.tsinghua.edu.cn/admin/...`,
  'grades': `${WEBVPN_BASE_URL}/http/learn.tsinghua.edu.cn/grade/...`,
  'classroom': `${WEBVPN_BASE_URL}/http/learn.tsinghua.edu.cn/classroom/...`,
  'homework': `${WEBVPN_BASE_URL}/http/learn.tsinghua.edu.cn/homework/...`,
  'notifications': `${WEBVPN_BASE_URL}/http/learn.tsinghua.edu.cn/notification/...`,
  'files': `${WEBVPN_BASE_URL}/http/learn.tsinghua.edu.cn/coursefile/...`,
  'finance_balance': `${WEBVPN_BASE_URL}/http/info.tsinghua.edu.cn/card/balance`,
  'finance_transactions': `${WEBVPN_BASE_URL}/http/info.tsinghua.edu.cn/card/transactions`,
  'network_info': `${WEBVPN_BASE_URL}/http/info.tsinghua.edu.cn/network/info`,
  'network_devices': `${WEBVPN_BASE_URL}/http/info.tsinghua.edu.cn/network/devices`,
  'electricity': `${WEBVPN_BASE_URL}/http/info.tsinghua.edu.cn/dorm/electricity`,
  'laundry': `${WEBVPN_BASE_URL}/http/info.tsinghua.edu.cn/dorm/laundry`,
  'mail_inbox': `${WEBVPN_BASE_URL}/http/mail.tsinghua.edu.cn/inbox`,
  'mail_detail': `${WEBVPN_BASE_URL}/http/mail.tsinghua.edu.cn/mail/detail`,
  'library_seats': `${WEBVPN_BASE_URL}/http/lib.tsinghua.edu.cn/seat/list`,
  'library_reserve': `${WEBVPN_BASE_URL}/http/lib.tsinghua.edu.cn/seat/reserve`,
  'petest': `${WEBVPN_BASE_URL}/http/info.tsinghua.edu.cn/sport/petest`,
  'sports_venues': `${WEBVPN_BASE_URL}/http/info.tsinghua.edu.cn/sport/venues`,
  'news_channels': `${WEBVPN_BASE_URL}/http/info.tsinghua.edu.cn/news/channels`,
  'news_list': `${WEBVPN_BASE_URL}/http/info.tsinghua.edu.cn/news/list`,
  'program': `${WEBVPN_BASE_URL}/http/info.tsinghua.edu.cn/program/completion`,
};

export const ROAM_TARGETS: Record<string, string> = {
  'info': 'info.tsinghua.edu.cn',
  'learn': 'learn.tsinghua.edu.cn',
  'id': 'id.tsinghua.edu.cn',
};
