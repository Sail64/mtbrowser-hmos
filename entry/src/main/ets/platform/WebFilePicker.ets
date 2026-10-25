import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'WebFilePicker';

/**
 * 网页 <input type="file"> 的文件选择（对应 Android AppWebChromeClient.onShowFileChooser）。
 *
 * 关键约定：
 * - 必须调用 `result.handleFileList()` 结束这次选择，**即使取消也要传空数组**，
 *   否则内核侧会一直挂着这个 file input（再点一次没有任何反应）。
 * - 只能传文件 URI（file://...），DocumentViewPicker 返回的就是这个形态。
 * - accept 里的 MIME 类型要翻译成后缀过滤器，DocumentViewPicker 只认后缀。
 */
export class WebFilePicker {
  /** 把 `image/*`、`application/pdf` 这类 MIME 翻成 DocumentViewPicker 认的后缀过滤串。 */
  static suffixFilters(acceptTypes: string[]): string[] {
    const out: string[] = [];
    for (const raw of acceptTypes) {
      const t = raw.trim().toLowerCase();
      if (t === '' || t === '*/*' || t === '*') {
        return ['.*'];
      }
      if (t.startsWith('image/')) {
        WebFilePicker.pushAll(out, ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic']);
      } else if (t.startsWith('video/')) {
        WebFilePicker.pushAll(out, ['.mp4', '.mov', '.mkv', '.webm', '.3gp']);
      } else if (t.startsWith('audio/')) {
        WebFilePicker.pushAll(out, ['.mp3', '.m4a', '.wav', '.aac', '.ogg', '.flac']);
      } else if (t === 'application/pdf') {
        WebFilePicker.pushAll(out, ['.pdf']);
      } else if (t === 'text/plain') {
        WebFilePicker.pushAll(out, ['.txt', '.log', '.md', '.csv']);
      } else if (t.startsWith('text/')) {
        WebFilePicker.pushAll(out, ['.txt', '.html', '.css', '.js', '.json', '.md']);
      } else if (t === 'application/json') {
        WebFilePicker.pushAll(out, ['.json']);
      } else if (t.indexOf('/') > 0) {
        // 其它 MIME（含 x-pkcs12 之类）按后缀猜：application/x-pkcs12 → .p12
        const sub = t.substring(t.indexOf('/') + 1);
        if (sub.length >= 2 && sub.length <= 5 && sub.indexOf('+') < 0) {
          WebFilePicker.pushAll(out, ['.' + sub]);
        }
      }
    }
    // 去重
    const uniq: string[] = [];
    for (const s of out) {
      if (uniq.indexOf(s) < 0) {
        uniq.push(s);
      }
    }
    return uniq.length > 0 ? uniq : ['.*'];
  }

  private static pushAll(dst: string[], items: string[]): void {
    for (const it of items) {
      dst.push(it);
    }
  }

  /**
   * 拉起系统文件选择器。
   * @returns 选中的文件 URI 列表；用户取消返回空数组（调用方仍需回传内核）。
   */
  static async pick(context: common.UIAbilityContext, param: FileSelectorParam): Promise<string[]> {
    const mode = param.getMode();
    const multiple = mode === FileSelectorMode.FileOpenMultipleMode;
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = multiple ? 20 : 1;
    options.fileSuffixFilters = WebFilePicker.suffixFilters(param.getAcceptType());
    try {
      const viewPicker = new picker.DocumentViewPicker(context);
      const uris = await viewPicker.select(options);
      return uris === null ? [] : uris;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'file picker cancelled/failed: %{public}s', JSON.stringify(e));
      return [];
    }
  }

  /** 文件名猜后缀用（下载场景共用）。 */
  static extensionOf(nameOrUrl: string): string {
    const clean = nameOrUrl.split('?')[0].split('#')[0];
    const slash = clean.lastIndexOf('/');
    const base = slash >= 0 ? clean.substring(slash + 1) : clean;
    const dot = base.lastIndexOf('.');
    if (dot < 0 || dot === base.length - 1) {
      return '';
    }
    return base.substring(dot);
  }
}