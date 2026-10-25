import { NavigationDecision } from './model/CertModels';
import { UrlLite } from './UrlLite';

/**
 * 导航策略：一个 URL 应该在哪里打开，只有这一处决策。
 * http/https（含无法解析的兜底）一律应用内加载，享受 mTLS 与证书提醒能力；
 * 其他 scheme（mailto:、tel: 等）交给系统。
 *
 * 与 Android 版的**有意偏离**：Android 把所有非 http/https 都丢给系统 startAbility，
 * 于是页面里一个 `file://` 或 `content://` 链接就能把任意能力唤起。鸿蒙版额外拦掉
 * 危险 scheme（见 DANGEROUS_SCHEMES），不外抛也不加载。理由：本应用访问的都是用户
 * 自己的站点，但"自己的站点被注入了恶意链接"仍然是现实威胁，浏览器不该当跳板。
 */
export interface NavigationPolicy {
  decide(url: string, currentSiteUrl: string | null): NavigationDecision;
}

/** 绝不外抛、绝不加载的 scheme。 */
const DANGEROUS_SCHEMES: string[] = ['file', 'javascript', 'data', 'blob', 'content', 'about'];

/**
 * 允许交给系统的 scheme 白名单。
 * ArkWeb 的 onLoadIntercept 拿不到"是否用户手势触发"，页面里一行
 * `location.href='xxx://...'` 就能静默唤起任意能力。所以只放行少数不会造成
 * 副作用外溢的 scheme，其余一律 BLOCK。
 */
const EXTERNAL_SCHEMES: string[] = ['mailto', 'tel', 'sms', 'geo'];

export class DefaultNavigationPolicy implements NavigationPolicy {
  decide(url: string, currentSiteUrl: string | null): NavigationDecision {
    const trimmed = url.trim();
    // about:blank 是本应用自己的内部空白页（新标签首帧、拦截后卸载文档都用它）。
    // 若把它当危险 scheme 一起 BLOCK，白名单拦截的 loadUrl('about:blank') 会被
    // onLoadIntercept 拦掉，"卸载已提交的恶意页"这一步就永远不生效。
    if (trimmed === 'about:blank') {
      return NavigationDecision.OPEN_IN_APP;
    }
    const scheme = UrlLite.schemeOf(trimmed);
    if (scheme === null || scheme === 'http' || scheme === 'https') {
      return NavigationDecision.OPEN_IN_APP;
    }
    if (DANGEROUS_SCHEMES.indexOf(scheme) >= 0) {
      return NavigationDecision.BLOCK;
    }
    if (EXTERNAL_SCHEMES.indexOf(scheme) >= 0) {
      return NavigationDecision.OPEN_EXTERNAL;
    }
    // 未知自定义 scheme（各类 app 深链）：无手势上下文，不冒这个险
    return NavigationDecision.BLOCK;
  }
}