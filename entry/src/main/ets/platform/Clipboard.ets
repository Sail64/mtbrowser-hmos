import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0x0001;
const TAG = 'Clipboard';

/** 系统剪贴板适配：ui 层不得直接 import @kit.*，只能经 AppGraph 转发到这里。 */
export class Clipboard {
  /** @return 是否写入成功（失败时调用方负责提示，不静默） */
  static copy(text: string): boolean {
    if (text === '') {
      return false;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setDataSync(data);
      return true;
    } catch (e) {
      // BusinessError 的 code 才是排查依据；JSON.stringify 会把它压成 "{}"
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'copy failed: code=%{public}d message=%{public}s',
        err.code, err.message);
      return false;
    }
  }
}
