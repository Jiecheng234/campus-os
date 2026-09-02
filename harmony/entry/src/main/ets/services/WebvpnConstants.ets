/**
 * ============================================================================
 * WebvpnConstants — 清华认证/WebVPN 端点常量与 URL 包装
 * ============================================================================
 *
 * 关键端点：
 *   - WEBVPN_OAUTH_LOGIN_URL   认证启动（预热 WebVPN→OAuth→ID 链）
 *   - ID_LOGIN_URL             ID 登录 POST（i_user/i_pass/fingerPrint/...）
 *   - DOUBLE_AUTH_URL          2FA 端点（SEND_CODE/VERITY_CODE）
 *   - SAVE_FINGER_URL          信任设备（须在 2FA redirectUrl 之前调用）
 *   - LEARN_AUTH_ROAM          learn 域激活（ticket → 建立 learn 会话）
 *
 * yyfwid（应用服务 ID）：
 *   - INFO_PORTAL_YYFWID       信息门户（校园通用门户漫游）
 *
 * wrapWebVPNUrl()：把任意内网 URL 包装为 WebVPN lbredirect 形式（ roam 时 follow callback 用）。
 * ============================================================================
 */
export const WEBVPN_BASE_URL: string = 'https://webvpn.tsinghua.edu.cn';
export const WEBVPN_OAUTH_LOGIN_URL: string = `${WEBVPN_BASE_URL}/login?oauth_login=true`;
export const OAUTH_LBREDIRECT_PREFIX: string = 'https://oauth.tsinghua.edu.cn/lb-auth/lbredirect';
export const ID_HOST_URL: string = 'https://id.tsinghua.edu.cn';
export const ID_LOGIN_URL: string = `${ID_HOST_URL}/do/off/ui/auth/login/check`;
export const DOUBLE_AUTH_URL: string = `${ID_HOST_URL}/b/doubleAuth/login`;
export const SAVE_FINGER_URL: string = `${ID_HOST_URL}/b/doubleAuth/personal/saveFinger`;
export const INFO_PORTAL_YYFWID: string = '10000ea055dd8d81d09d5a1ba55d39ad';
export const LEARN_BASE: string = 'https://learn.tsinghua.edu.cn';
export const LEARN_AUTH_ROAM: string = `${LEARN_BASE}/b/j_spring_security_thauth_roaming_entry`;
export const LEARN_STUDENT_HOME: string = `${LEARN_BASE}/f/wlxt/index/course/student/`;
export const LEARN_CURRENT_SEMESTER: string = `${LEARN_BASE}/b/kc/zhjw_v_code_xnxq/getCurrentAndNextSemester`;
export const LEARN_COURSE_LIST: string = `${LEARN_BASE}/b/kc/v_wlkc_xs_xkb_kcb_extend/student/loadCourseBySemesterId`;

export function wrapWebVPNUrl(targetUrl: string): string {
  const re: RegExp = new RegExp('^(https?):\\/\\/([^\\/:?#]+)(?::(\\d+))?(\\/[^?#]*)?(\\?[^#]*)?(#.*)?$');
  const match = re.exec(targetUrl);
  if (match === null) {
    return targetUrl;
  }
  const scheme: string = match[1] || 'https';
  const host: string = match[2] || '';
  const port: string = match[3] || (scheme === 'https' ? '443' : '80');
  const path: string = match[4] || '/';
  const search: string = match[5] || '';
  const hash: string = match[6] || '';
  const uri: string = path + search + hash;
  return `${OAUTH_LBREDIRECT_PREFIX}?scheme=${scheme}&host=${host}&port=${port}&uri=${encodeURIComponent(uri)}`;
}

export const SUBSYSTEM_INFO: string = 'info';
export const SUBSYSTEM_LEARN: string = 'learn';
export const SUBSYSTEM_ID: string = 'id';

export function getSubsystemUrl(subsystem: string): string {
  if (subsystem === SUBSYSTEM_INFO) {
    return `${WEBVPN_BASE_URL}/https/77726476706e69737468656265737421f9f9479369247b59700f81b9991b2631506205de/b/info/gxfw_fg/common/grjbxx`;
  }
  if (subsystem === SUBSYSTEM_LEARN) {
    return `${LEARN_BASE}/b/j_spring_security_thauth_roaming_entry`;
  }
  if (subsystem === SUBSYSTEM_ID) {
    return `${ID_HOST_URL}/do/off/ui/auth/login/form/`;
  }
  return '';
}

export const CAMPUS_ENDPOINTS: Record<string, string> = {
  'schedule': `${LEARN_BASE}/f/wlxt/index/course/student/`,
  'grades': `${LEARN_BASE}/grade/overview`,
  'homework': `${LEARN_BASE}/b/wlxt/kczy/zy/student/zyListWj`,
  'notifications': `${LEARN_BASE}/b/wlxt/kcgg/wlkc_ggb/student/pageListXsbyWgq`,
  'files': `${LEARN_BASE}/b/wlxt/kj/wlkc_kjxxb/student/kjxxbByWlkcidAndSizeForStudent`,
};

export const ROAM_TARGETS: Record<string, string> = {
  'info': 'info.tsinghua.edu.cn',
  'learn': 'learn.tsinghua.edu.cn',
  'id': 'id.tsinghua.edu.cn',
};
