import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'CookiePersist';

/**
 * Cookie 落盘。
 *
 * ArkWeb 的 cookie 默认只在内存里：不主动写盘，进程被杀掉后会话 cookie 就没了。
 * 表现就是「登录 LibreChat → 从多任务里划掉浏览器 → 再打开又要登录」。
 *
 * 落盘时机必须覆盖「用户直接把应用划掉」这条路径：
 * - UIAbility.onBackground（离开前台，划掉前必经）
 * - 页面加载完成（登录后的跳转/刷新生效时写一次）
 * - 页面销毁
 *
 * 注意：`saveCookieSync` 从 API 15 起才有，且明确「平板/2in1/PC 上会话 cookie 不落盘」，
 * 手机端用异步版本即可，避免在主线程做 I/O。
 */
export class CookiePersistence {
  private static lastSaveAt: number = 0;

  /** 节流后的异步落盘（默认 1.5s 内最多一次），失败只记日志不影响页面。 */
  static save(): void {
    const now = Date.now();
    if (now - CookiePersistence.lastSaveAt < 1500) {
      return;
    }
    CookiePersistence.lastSaveAt = now;
    CookiePersistence.flush();
  }

  /** 立即落盘（离开前台/退出时用，不节流）。 */
  static flush(): void {
    webview.WebCookieManager.saveCookieAsync().catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'saveCookieAsync failed: %{public}s', JSON.stringify(e));
    });
  }
}