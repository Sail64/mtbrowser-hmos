import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { suffixFilters } from '../domain/AcceptTypes';

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
  /**
   * 拉起系统文件选择器。
   * @returns 选中的文件 URI 列表；用户取消返回空数组（调用方仍需回传内核）。
   */
  static async pick(context: common.UIAbilityContext, param: FileSelectorParam): Promise<string[]> {
    const mode = param.getMode();
    const multiple = mode === FileSelectorMode.FileOpenMultipleMode;
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = multiple ? 20 : 1;
    const filters = suffixFilters(param.getAcceptType());
    if (filters.length > 0) {
      options.fileSuffixFilters = filters;
    }
    try {
      const viewPicker = new picker.DocumentViewPicker(context);
      const uris = await viewPicker.select(options);
      return uris === null ? [] : uris;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'file picker cancelled/failed: %{public}s', JSON.stringify(e));
      return [];
    }
  }
}