import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { UrlLite } from '../domain/UrlLite';

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
    webview.WebCookieManager.saveCookieAsync()
      .then(() => {
        hilog.info(DOMAIN, TAG, 'saveCookieAsync ok');
      })
      .catch((e: Error) => {
        hilog.error(DOMAIN, TAG, 'saveCookieAsync failed: %{public}s', JSON.stringify(e));
      });
  }

  /**
   * 诊断用：打印某 URL 当前可见的 cookie 数量/长度（**不打印内容**，避免把会话令牌写进日志）。
   * `when` 用来区分调用时机（startup / pageEnd），排查"登录态没保住"时对照这两行即可判断
   * 是「没写盘」还是「写盘了但启动时没读回来」。
   */
  static report(url: string, when: string): void {
    if (url === '' || url === 'about:blank') {
      return;
    }
    const host = UrlLite.hostOf(url);
    let raw = '';
    try {
      raw = webview.WebCookieManager.fetchCookieSync(url);
    } catch (e) {
      // 17100002 = 该 URL 没有任何 cookie：这是"空"，不是"异常"。
      // 混成错误日志会让诊断结论完全反过来（看起来像 cookie 系统坏了）。
      const err = e as BusinessError;
      if (err !== undefined && err.code === 17100002) {
        hilog.info(DOMAIN, TAG, 'cookie[%{public}s] host=%{public}s n=0 (no cookie)',
          when, host === null ? '?' : host);
        return;
      }
      hilog.error(DOMAIN, TAG, 'fetchCookieSync failed: %{public}s', JSON.stringify(e));
      return;
    }
    const names: string[] = [];
    if (raw !== '') {
      for (const part of raw.split(';')) {
        const eq = part.indexOf('=');
        const name = (eq > 0 ? part.substring(0, eq) : part).trim();
        if (name !== '') {
          names.push(name);
        }
      }
    }
    // 只打名字和长度：值里是会话令牌，绝不落日志
    hilog.info(DOMAIN, TAG, 'cookie[%{public}s] host=%{public}s n=%{public}d names=%{public}s len=%{public}d',
      when, host === null ? '?' : host, names.length, names.join(','), raw.length);
  }
}