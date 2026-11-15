import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * 窗口隐私模式：开启后本窗口**不允许截屏/录屏**，任务列表（最近任务）里的缩略图也不再显示页面内容。
 *
 * 为什么整窗口开、而不是"进后台时再开"：最近任务的缩略图是系统在切换动画那一刻取的，
 * onBackground 回来时图已经生成了 —— 那时候再开隐私模式只能挡住下一次，挡不住这一次。
 * 所以只能常开。代价是同窗口内用户也截不了图，因此做成设置项（默认开）。
 */
export class WindowPrivacy {
  /** 上一次成功下发的值：避免每帧重复 IPC（这个调用跨进程） */
  private static _applied: boolean | undefined = undefined;

  static apply(context: common.UIAbilityContext | undefined, enabled: boolean): void {
    if (context === undefined) {
      return;
    }
    if (WindowPrivacy._applied === enabled) {
      return;
    }
    // 先记下"已下发"，失败时回滚，避免调用方高频重试打满 IPC
    WindowPrivacy._applied = enabled;
    window.getLastWindow(context).then((win: window.Window) => {
      win.setWindowPrivacyMode(enabled).then(() => {
        hilog.info(0x0000, 'WindowPrivacy', 'privacy mode = %{public}s', String(enabled));
      }).catch((err: Error) => {
        WindowPrivacy._applied = undefined;
        hilog.error(0x0000, 'WindowPrivacy', 'setWindowPrivacyMode(%{public}s) failed: %{public}s',
          String(enabled), err.message);
      });
    }).catch((err: Error) => {
      WindowPrivacy._applied = undefined;
      hilog.error(0x0000, 'WindowPrivacy', 'getLastWindow failed: %{public}s', err.message);
    });
  }
}