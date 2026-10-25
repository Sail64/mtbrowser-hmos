import { request } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileNameFrom } from '../domain/FileName';

const DOMAIN = 0x0001;
const TAG = 'DownloadSaver';

export class DownloadOutcome {
  ok: boolean;
  /** 成功时是落盘绝对路径，失败时是给用户看的中文原因 */
  detail: string;
  constructor(ok: boolean, detail: string) {
    this.ok = ok;
    this.detail = detail;
  }
}

/**
 * 网页下载（对应 Android web/DownloadHandler）。
 *
 * 保存位置：应用私有目录 `<filesDir>/downloads/`，不申请公共存储权限。
 * 之所以不直接写系统「下载」目录：三方应用写公共目录要走 MediaStore/saf，
 * 为了一个浏览器自用场景把权限面放大不值得；导出到公共目录用户可用文件管理器复制。
 */
export class DownloadSaver {
  /** 下载到应用私有 downloads 目录；返回给用户看的落点说明。 */
  static async save(context: common.UIAbilityContext, url: string, contentDisposition: string,
    mimetype: string, cookie: string, userAgent: string): Promise<DownloadOutcome> {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      // data:/blob: 这类需要内核侧先取内容，ArkWeb 的 onDownloadStart 不给内容体，
      // 只能引导用户另存；这里如实说明，不假装支持。
      return new DownloadOutcome(false, '该链接不是 http/https，暂不支持下载');
    }
    const dir = `${context.filesDir}/downloads`;
    try {
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir);
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'mkdir downloads failed: %{public}s', JSON.stringify(e));
      return new DownloadOutcome(false, '无法创建下载目录');
    }
    const name = fileNameFrom(contentDisposition, url, mimetype);
    // 同名不覆盖：加 -1 / -2 后缀
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
    const header: Record<string, string> = {};
    if (cookie !== undefined && cookie !== '') {
      header['Cookie'] = cookie;
    }
    if (userAgent !== undefined && userAgent !== '') {
      header['User-Agent'] = userAgent;
    }
    const config: request.DownloadConfig = {
      url: url,
      filePath: target,
      header: header,
      enableMetered: true,
      enableRoaming: false,
      background: true
    };
    try {
      await request.downloadFile(context, config);
      const shown = target.substring(dir.length + 1);
      return new DownloadOutcome(true, `已下载：${shown}`);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'downloadFile failed: %{public}s', JSON.stringify(e));
      return new DownloadOutcome(false, '下载失败');
    }
  }
}