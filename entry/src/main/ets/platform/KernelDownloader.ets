import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileNameFrom } from '../domain/FileName';
import { UrlLite } from '../domain/UrlLite';
import { DomainWhitelist } from '../domain/DomainWhitelist';
import { CertReminderNotifier } from '../domain/ServerCertReminderService';

const DOMAIN = 0x0001;
const TAG = 'KernelDownload';

/** 超过这个大小先拦下，避免后台悄悄写满磁盘（不弹确认框，直接告知去别的浏览器下） */
const MAX_DOWNLOAD_BYTES: number = 512 * 1024 * 1024;

/**
 * 网页下载：走**内核**下载栈（对应 Android WebView 的 DownloadListener + 内核下载）。
 *
 * 为什么不用 `@ohos.request.downloadFile`：那是系统下载服务自己的网络栈，
 * 既拿不到本应用选定的客户端证书、也不继承用户对自签证书的「仍要继续」豁免，
 * 对 mTLS 站点必然握手失败；而且它的 Promise 只表示"任务已创建"，不是下载完成。
 * 内核栈与页面共用连接语义（cookie / 重定向 / 证书 / UA 全部一致），
 * 并且 onDownloadFinish / onDownloadFailed 给出真实结果。
 */
export class KernelDownloader {
  private static installed: boolean = false;

  /**
   * 全局注册一次（WebviewController.setDownloadDelegate 是静态的）。
   * 之后任意 Web 实例触发的下载都会走这里。
   */
  static install(context: common.UIAbilityContext, whitelist: DomainWhitelist,
    notifier: CertReminderNotifier): void {
    if (KernelDownloader.installed) {
      return;
    }
    const dir = `${context.filesDir}/downloads`;
    try {
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir);
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'mkdir downloads failed: %{public}s', JSON.stringify(e));
    }

    const delegate = new webview.WebDownloadDelegate();

    delegate.onBeforeDownload((item: webview.WebDownloadItem): void => {
      const url = item.getUrl();
      // 子框架/子资源不受白名单约束（已知边界），所以下载必须自己再过一道：
      // 否则白名单页里嵌的第三方 iframe 就能静默往应用目录写文件。
      if (!whitelist.allows(url)) {
        hilog.warn(DOMAIN, TAG, 'download from non-whitelisted host blocked: %{public}s',
          UrlLite.hostOf(url) ?? '');
        notifier.show('已阻止下载：该域名不在白名单');
        item.cancel();
        return;
      }
      const total = item.getTotalBytes();
      if (total > MAX_DOWNLOAD_BYTES) {
        notifier.show(`文件过大（${Math.trunc(total / 1024 / 1024)}MB），已取消`);
        item.cancel();
        return;
      }
      const name = fileNameFrom('', url, item.getMimeType());
      let target = `${dir}/${name}`;
      let seq = 1;
      while (fileIo.accessSync(target)) {
        const dot = name.lastIndexOf('.');
        const stem = dot > 0 ? name.substring(0, dot) : name;
        const ext = dot > 0 ? name.substring(dot) : '';
        target = `${dir}/${stem}-${seq}${ext}`;
        seq = seq + 1;
        if (seq > 100) {
          break;
        }
      }
      try {
        item.start(target);
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'WebDownloadItem.start failed: %{public}s', JSON.stringify(e));
        notifier.show('下载启动失败');
        return;
      }
      notifier.show(`开始下载：${name}`);
    });

    delegate.onDownloadFinish((item: webview.WebDownloadItem): void => {
      notifier.show(`已下载：${item.getSuggestedFileName()}`);
    });

    delegate.onDownloadFailed((item: webview.WebDownloadItem): void => {
      const code = item.getLastErrorCode();
      hilog.error(DOMAIN, TAG, 'download failed guid=%{public}s code=%{public}d',
        item.getGuid(), code);
      // 错误码对用户没有意义，只给一句可行动的话
      notifier.show(code === webview.WebDownloadErrorCode.USER_CANCELED
        ? '下载已取消' : '下载失败，可稍后重试');
    });

    try {
      webview.WebDownloadManager.setDownloadDelegate(delegate);
      KernelDownloader.installed = true;
      hilog.info(DOMAIN, TAG, 'kernel download delegate installed');
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'setDownloadDelegate failed: %{public}s', JSON.stringify(e));
    }
  }
}