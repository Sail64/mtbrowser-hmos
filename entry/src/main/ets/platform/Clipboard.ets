import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

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
      hilog.error(DOMAIN, TAG, 'copy failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }
}